#!/usr/bin/env bash
# Instala os jobs agendados: valida TODOS os jobs/*.job (mesmo parser do bin/stack-job) e gera
# stack-job-<nome>.service/.timer do systemd so para HABILITADO=sim; remove as unidades de jobs que sumiram
# ou viraram nao. Fail-closed: um .job invalido recusa tudo e nada e instalado. Idempotente: unidade
# igual nao e reescrita. As unidades nao levam segredo (o executor le /srv/dev/secrets/jobs na hora).
# Uso: sudo ./45-jobs.sh [--listar]   (--listar mostra o estado de cada .job e nao muda nada)
# Pastas do agente/dev: se existem, tem de ser diretorio (nunca link) do dono certo, senao recusa tudo; so as que
# faltam sao criadas (mkdir + chown -h), nunca chown/chmod em algo que ja existia.
# Sobrescreviveis nos testes (so com STACK_TESTE=1): JOBS_DIR, JOBS_UNIT_DIR, JOBS_BIN, JOBS_ANALYZE, JOBS_SRV,
# JOBS_USER_AGENTE, JOBS_USER_DEV, JOBS_GROUP.
set -euo pipefail

# Em producao o ambiente herdado e ignorado: atribui sem ler.
# >>> normaliza
REPO=$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)
if [[ ${STACK_TESTE:-} != 1 ]]; then
  JOBS_DIR=$REPO/jobs; JOBS_UNIT_DIR=/etc/systemd/system; JOBS_BIN=/opt/stack-vps/bin/stack-job; JOBS_ANALYZE=systemd-analyze
  JOBS_SRV=/srv/dev; JOBS_USER_AGENTE=agente; JOBS_USER_DEV=dev; JOBS_GROUP=agente
fi
# <<< normaliza
JOBS_DIR=${JOBS_DIR:-$REPO/jobs}; JOBS_UNIT_DIR=${JOBS_UNIT_DIR:-/etc/systemd/system}
JOBS_BIN=${JOBS_BIN:-/opt/stack-vps/bin/stack-job}; JOBS_ANALYZE=${JOBS_ANALYZE:-systemd-analyze}
JOBS_SRV=${JOBS_SRV:-/srv/dev}; JOBS_USER_AGENTE=${JOBS_USER_AGENTE:-agente}; JOBS_USER_DEV=${JOBS_USER_DEV:-dev}; JOBS_GROUP=${JOBS_GROUP:-agente}

modo=${1:-}
case $modo in ""|--listar) ;; *) echo "uso: $0 [--listar]"; exit 2 ;; esac
[[ $modo == --listar || $EUID -eq 0 || ${STACK_TESTE:-} == 1 ]] || { echo "rode como root"; exit 1; }

# o parser roda como root: so de codigo do root (/opt/stack-vps ou dono root)
if [[ ${STACK_TESTE:-} != 1 && $REPO != /opt/stack-vps && $(stat -c %u -- "$REPO/scripts/lib/job-parse.sh") != 0 ]]; then
  echo "recuso: $REPO nao e /opt/stack-vps nem do root"; exit 1
fi
# shellcheck source=scripts/lib/job-parse.sh
. "$REPO/scripts/lib/job-parse.sh"

# agenda valida: systemd-analyze quando existir; senao uma regex conservadora
agenda_ok() {
  if command -v "$JOBS_ANALYZE" >/dev/null 2>&1; then "$JOBS_ANALYZE" calendar -- "$1" >/dev/null 2>&1; return; fi
  local dia='(Mon|Tue|Wed|Thu|Fri|Sat|Sun)' h='[0-9*]{1,2}:[0-9*/]{1,5}(:[0-9*/]{1,5})?'
  [[ $1 =~ ^(minutely|hourly|daily|weekly|monthly|quarterly|semiannually|yearly)$ ]] ||
    [[ $1 =~ ^($dia([,.-]+$dia)* )?([0-9*]{1,4}-[0-9*]{1,2}-[0-9*/,]{1,8} )?$h$ ]]
}

nomes=(); erros=(); linhas=(); reiniciar=()
err=$(mktemp); tmps=()
# nada de temporario solto em /etc/systemd/system se o script morrer no meio
trap 'rm -f "$err" "${tmps[@]}"' EXIT
shopt -s nullglob
for f in "$JOBS_DIR"/*.job; do
  n=$(basename "$f" .job); t=nao; [[ -f $JOBS_UNIT_DIR/stack-job-$n.timer ]] && t=sim
  if ! job_carregar "$f" 2>"$err"; then msg=$(head -1 "$err")
  elif ! agenda_ok "$J_AGENDA"; then msg="$f: AGENDA invalida ($J_AGENDA)"
  else
    nomes+=("$n"); linhas+=("$(printf '%-30s %s, timer instalado: %s' "$n" "$([[ $J_HABILITADO == sim ]] && echo habilitado || echo desligado)" "$t")")
    continue
  fi
  erros+=("$msg"); linhas+=("$(printf '%-30s INVALIDO (%s)' "$n" "$msg")")
done
shopt -u nullglob

if [[ $modo == --listar ]]; then
  (( ${#linhas[@]} == 0 )) || printf '%s\n' "${linhas[@]}"
  exit 0
fi

if (( ${#erros[@]} > 0 )); then
  printf '%s\n' "${erros[@]}"
  echo "jobs: ha .job invalido; nada foi instalado nem removido"; exit 1
fi

# pastas: <caminho> <dono> <grupo> <modo>. Valida tudo ANTES de escrever qualquer coisa.
DIRS=("$JOBS_SRV/jobs $JOBS_USER_AGENTE $JOBS_GROUP 750" "$JOBS_SRV/jobs/work $JOBS_USER_AGENTE $JOBS_GROUP 750"
      "$JOBS_SRV/state/jobs $JOBS_USER_AGENTE $JOBS_GROUP 750"
      "$JOBS_SRV/secrets/jobs $JOBS_USER_DEV $JOBS_GROUP 2750"   # setgid: o 43-segredos-guiado.sh job (dev) grava 0640 dev:agente
      "$JOBS_SRV/backups $JOBS_USER_AGENTE $JOBS_GROUP 750")     # destino local do n360-alt-backup (o job cria o 0700)
recusa_dir() { echo "jobs: $1; nada foi instalado"; exit 1; }
confere_dir() { # <caminho> <dono>: existente tem de ser diretorio real do dono; ausente passa
  [[ -L $1 ]] && recusa_dir "$1 e link simbolico"
  [[ -e $1 ]] || return 0
  [[ -d $1 ]] || recusa_dir "$1 existe e nao e diretorio"
  [[ $(stat -c %U -- "$1") == "$2" ]] || recusa_dir "$1 nao e do dono $2"
}
for d in "${DIRS[@]}"; do
  read -r caminho dono _ _ <<<"$d"
  confere_dir "$caminho" "$dono"
  pai=$(dirname "$caminho")   # o pai (que o script nao cria, exceto jobs/) tem de existir e ser diretorio real
  [[ $pai == "$JOBS_SRV/jobs" ]] || [[ -d $pai && ! -L $pai ]] || recusa_dir "$pai ausente ou link simbolico"
done

mudou=0; declare -A querido=()
# grava <destino> <conteudo>: so troca o arquivo se o conteudo mudou
grava() {
  local dest=$1 tmp
  tmp=$(mktemp "$dest.XXXXXX"); tmps+=("$tmp"); printf '%s\n' "$2" > "$tmp"; chmod 644 "$tmp"
  if [[ -f $dest ]] && cmp -s "$tmp" "$dest"; then rm -f "$tmp"; return 1; fi
  mv -f "$tmp" "$dest"; mudou=1; return 0
}

install -d -m 755 "$JOBS_UNIT_DIR"
for d in "${DIRS[@]}"; do   # so cria o que falta: mkdir falha em qualquer coisa que ja exista (inclusive link)
  read -r caminho dono grupo modo <<<"$d"
  [[ -e $caminho ]] || { mkdir -m "$modo" -- "$caminho" && chown -h "$dono:$grupo" -- "$caminho" && chmod "$modo" -- "$caminho"; }
done

for f in "$JOBS_DIR"/*.job; do
  [[ -e $f ]] || continue
  job_carregar "$f"
  [[ $J_HABILITADO == sim ]] || continue
  n=$J_NOME; querido[$n]=1
  grava "$JOBS_UNIT_DIR/stack-job-$n.service" "[Unit]
Description=Job agendado: $J_DESCRICAO
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
User=agente
WorkingDirectory=/
ExecStart=$JOBS_BIN $n
TimeoutStartSec=$((J_TIMEOUT_MIN + 10))min
NoNewPrivileges=yes
PrivateTmp=yes
ProtectSystem=full
MemoryMax=2G" || true
  if grava "$JOBS_UNIT_DIR/stack-job-$n.timer" "[Unit]
Description=Agenda do job $n

[Timer]
OnCalendar=$J_AGENDA
Persistent=true
RandomizedDelaySec=300

[Install]
WantedBy=timers.target"; then reiniciar+=("stack-job-$n.timer"); fi
done

# unidades de jobs que sumiram ou viraram nao
shopt -s nullglob
for u in "$JOBS_UNIT_DIR"/stack-job-*.timer "$JOBS_UNIT_DIR"/stack-job-*.service; do
  b=$(basename "$u"); n=${b#stack-job-}; n=${n%.*}
  [[ -z ${querido[$n]:-} ]] || continue
  if [[ $u == *.timer ]]; then systemctl disable --now "$b" >/dev/null 2>&1 || true; fi
  rm -f "$u"; mudou=1; echo "jobs: removido $b"
done
shopt -u nullglob

(( mudou == 0 )) || systemctl daemon-reload
for n in "${!querido[@]}"; do systemctl enable --now "stack-job-$n.timer" >/dev/null; done
for t in "${reiniciar[@]}"; do systemctl try-restart "$t" || true; done
echo "jobs: ${#querido[@]} habilitado(s) de ${#nomes[@]} definido(s)"
