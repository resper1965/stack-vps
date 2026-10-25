#!/usr/bin/env bash
# API da Hostinger: metricas (so leitura), snapshot, reiniciar e recuperacao.
# Uso: hostinger.sh metricas | snapshot|reiniciar|recuperacao [--sim]
# Os tres que alteram estado exigem --sim; sem ele mostram o que fariam e saem com rc 3.
# Token vai ao curl pelo stdin (-K -), nunca na linha de comando (visivel em ps).
# Endpoints: docs/spikes/2026-10-18-hostinger.md (so documentacao, nada foi chamado na API real).
set -uo pipefail
ENVF=${HOSTINGER_ENV:-/srv/dev/secrets/admin.env}
# variavel ja definida no ambiente vence o arquivo
env_token=${HOSTINGER_API_TOKEN-}; env_vm=${HOSTINGER_VM_ID-}
if [[ -s $ENVF ]]; then
  set -a
  # shellcheck source=/dev/null
  . "$ENVF"
  set +a
fi
[[ -n $env_token ]] && HOSTINGER_API_TOKEN=$env_token
[[ -n $env_vm ]] && HOSTINGER_VM_ID=$env_vm
BASE=https://developers.hostinger.com
P_VM=/api/vps/v1/virtual-machines
CMD=${1:-}; SIM=${2:-}

[[ $CMD =~ ^(metricas|snapshot|reiniciar|recuperacao)$ ]] || { echo "uso: $0 metricas | snapshot|reiniciar|recuperacao [--sim]"; exit 1; }
if [[ -z ${HOSTINGER_API_TOKEN:-} || -z ${HOSTINGER_VM_ID:-} ]]; then
  echo "hostinger: defina HOSTINGER_API_TOKEN e HOSTINGER_VM_ID em $ENVF"; exit 1
fi
if [[ ! $HOSTINGER_VM_ID =~ ^[0-9]+$ ]]; then echo "hostinger: HOSTINGER_VM_ID deve ser numerico"; exit 1; fi
# o token vai dentro de uma string entre aspas na config do curl
nl=$'\n'
if [[ $HOSTINGER_API_TOKEN == *'"'* || $HOSTINGER_API_TOKEN == *'\'* || $HOSTINGER_API_TOKEN == *"$nl"* ]]; then
  echo "hostinger: HOSTINGER_API_TOKEN tem caractere invalido (aspas, barra invertida ou quebra de linha)"; exit 1
fi
VM=$P_VM/$HOSTINGER_VM_ID
# confirmar na VPS: spike (caminhos e campos vem da spec OpenAPI, nao de chamada real)
P_DETALHE=$VM                  # campos memory e disk: unidade (MB) nao verificada
P_METRICAS=$VM/metrics         # cpu_usage, ram_usage, disk_space: {unit, usage:{ts:valor}}
P_SNAPSHOT=$VM/snapshot        # GET: created_at; POST: cria e sobrescreve
P_REINICIAR=$VM/restart
P_RECUPERACAO=$VM/recovery     # POST exige corpo {root_password}

# api <metodo> <caminho> [corpo-json]: imprime corpo e, na ultima linha, o status HTTP.
# So o cabecalho (token) e o corpo (pode ter senha) vao pelo stdin.
api() {
  local metodo=$1 caminho=$2 corpo=${3:-} cfg
  cfg="header = \"Authorization: Bearer $HOSTINGER_API_TOKEN\""
  [[ -n $corpo ]] && cfg+=$'\n'"header = \"Content-Type: application/json\""$'\n'"data = \"${corpo//\"/\\\"}\""
  printf '%s\n' "$cfg" | curl -sS --max-time 15 -w '\n%{http_code}' -K - -X "$metodo" "$BASE$caminho" 2>/dev/null
}
# campo <json> <expressao-python-sobre-d>: imprime o valor ou nada
campo() { python3 -c 'import json,sys
try:
    d=json.loads(sys.argv[1]); v=eval(sys.argv[2])
    if v is not None: print(v)
except Exception: pass' "$1" "$2"; }
# acao <metodo> <caminho> [corpo]: chamada que altera estado; rc 1 se status >= 300 ou campo error
acao() {
  local r cod corpo
  r=$(api "$@") || { echo "FALHA: sem resposta da API"; return 1; }
  cod=${r##*$'\n'}; corpo=${r%$'\n'*}
  if [[ ! $cod =~ ^[0-9]+$ ]] || (( cod >= 300 )) || [[ -n $(campo "$corpo" 'd.get("error")') ]]; then
    echo "FALHA: API respondeu $cod $(campo "$corpo" 'd.get("message") or d.get("error")')"; return 1
  fi
  echo "ok: ação $(campo "$corpo" 'd.get("id")') estado $(campo "$corpo" 'd.get("state")')"
}

# ultimo valor nao nulo de d[chave].usage (chave em argv[2])
ultimo='max(((int(k),x) for k,x in d[sys.argv[2]]["usage"].items() if x is not None))[1]'
metricas() {
  local de ate m det cpu ram disco r
  de=$(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%SZ); ate=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  r=$(api GET "$P_METRICAS?date_from=$de&date_to=$ate") || r=
  [[ ${r##*$'\n'} == 200 ]] && m=${r%$'\n'*} || m=
  r=$(api GET "$P_DETALHE") || r=
  [[ ${r##*$'\n'} == 200 ]] && det=${r%$'\n'*} || det=
  if [[ -n $m && -n $det ]]; then
    cpu=$(python3 -c "import json,sys
d=json.loads(sys.argv[1])
print(round($ultimo))" "$m" cpu_usage 2>/dev/null)
    ram=$(python3 -c "import json,sys
d=json.loads(sys.argv[1]); t=json.loads(sys.argv[3])['memory']*1048576
print(round(100*$ultimo/t))" "$m" ram_usage "$det" 2>/dev/null)
    disco=$(python3 -c "import json,sys
d=json.loads(sys.argv[1]); t=json.loads(sys.argv[3])['disk']*1048576
print(round(100*$ultimo/t))" "$m" disk_space "$det" 2>/dev/null)
  fi
  if [[ -n ${cpu:-} && -n ${ram:-} && -n ${disco:-} ]]; then
    printf '  ok    hostinger cpu %s%% ram %s%% disco %s%%\n' "$cpu" "$ram" "$disco"
  else
    echo "  FALHA hostinger indisponível"; return 1
  fi
}

if [[ $CMD == metricas ]]; then metricas; exit; fi

case $CMD in
  snapshot)    caminho=$P_SNAPSHOT ;;
  reiniciar)   caminho=$P_REINICIAR ;;
  recuperacao) caminho=$P_RECUPERACAO ;;
esac
if [[ $SIM != --sim ]]; then
  echo "faria: POST $caminho (nada foi enviado; repita com --sim)"; exit 3
fi

corpo=
case $CMD in
  snapshot)
    echo "ATENÇÃO: a Hostinger guarda UM snapshot por VM; este substitui o existente"
    r=$(api GET "$P_SNAPSHOT") || r=
    atual=
    [[ ${r##*$'\n'} == 200 ]] && atual=$(campo "${r%$'\n'*}" 'd.get("created_at")')
    if [[ -n $atual ]]; then echo "snapshot atual: criado em $atual"; else echo "não foi possível ler a data do snapshot atual"; fi ;;
  recuperacao)
    # senha temporaria: gerada agora, mostrada uma vez, nunca gravada
    senha=$(head -c 48 /dev/urandom | base64 | tr -dc 'A-Za-z0-9' | head -c 20)
    corpo="{\"root_password\":\"$senha\"}"
    echo "senha root temporária do modo de recuperação (anote, não será mostrada de novo): $senha" ;;
esac
acao POST "$caminho" "$corpo"
