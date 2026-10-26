#!/usr/bin/env bash
# Estado do ambiente: acesso (tailscale e tunnel), docker, ultimo backup, disco. Saida curta, exit 1 se algo falhar.
set -uo pipefail
fail=0
ok(){ printf '  ok    %s\n' "$*"; }
bad(){ printf '  FALHA %s\n' "$*"; fail=1; }

echo "acesso"
if systemctl is-active --quiet tailscaled && ip4=$(tailscale ip -4 2>/dev/null | head -1) && [[ $ip4 == 100.* ]]; then
  ok "tailscale na tailnet ($ip4)"
else bad "tailscale fora da tailnet"; fi
if systemctl is-active --quiet cloudflared; then ok "cloudflared ativo (reserva)"
else bad "cloudflared parado"; fi
if grep -q 'hostname: emergencia\.' "${STACK_CF_DIR:-/etc/cloudflared}/config.yml" 2>/dev/null; then bad "web de emergência ligada (stack-emergencia off)"
else ok "web de emergência desligada"; fi
oc=$(curl -s -o /dev/null -w '%{http_code}' --max-time 5 "${HEALTH_OPENCODE_URL:-http://127.0.0.1:4096/}" 2>/dev/null)
case $oc in 200|302|401) ok "opencode web" ;; *) bad "opencode web" ;; esac
# 9router: so conta se a unidade do agente estiver instalada (como o opencode, vale a resposta HTTP).
# GET / responde 307 para /dashboard; /api/health responde 200.
nr_unit=${HEALTH_9ROUTER_UNIT:-/home/agente/.config/systemd/user/9router.service}
if [[ -f $nr_unit ]]; then
  nr=$(curl -s -o /dev/null -w '%{http_code}' --max-time 5 "${HEALTH_9ROUTER_URL:-http://127.0.0.1:20128/api/health}" 2>/dev/null)
  case $nr in 200) ok "9router" ;; *) bad "9router" ;; esac
  # a exigencia de chave vem de settings.requireApiKey no banco do 9router (desligavel no painel): POST /v1/chat/completions sem chave tem de dar 401 (GET /v1/models e publico)
  nrk=$(curl -s -o /dev/null -w '%{http_code}' --max-time 5 -X POST -H 'Content-Type: application/json' -d '{"model":"x","messages":[{"role":"user","content":"oi"}]}' "${HEALTH_9ROUTER_CHAT_URL:-http://127.0.0.1:20128/v1/chat/completions}" 2>/dev/null)
  case $nrk in 401) ok "9router exige chave de API" ;; 2??) bad "9router sem exigir chave de API" ;; *) bad "9router: POST /v1/chat/completions sem chave respondeu ${nrk:-sem resposta}" ;; esac
fi
pmo_env=${HEALTH_PMO_ENV:-/etc/pmo/servidor.env}
if [[ ! -f $pmo_env ]]; then printf '  pend  %s\n' "painel do PMO sem /etc/pmo/servidor.env (34-pmo.sh ainda não rodou)"
else
  # sem source: o arquivo e do servico, aqui so lemos a chave
  pmo_host=$(sed -n 's/^PMO_HOSTS=//p' "$pmo_env" | head -1 | cut -d, -f1 | tr -d ' "'"'"'')
  pc=$(curl -s -o /dev/null -w '%{http_code}' --max-time 5 --unix-socket "${HEALTH_PMO_SOCKET:-/run/pmo/pmo.sock}" -H "Host: $pmo_host" http://localhost/ 2>/dev/null)
  if [[ $pc == 200 ]]; then ok "painel do PMO"; else bad "painel do PMO"; fi
fi
# unidade inexistente (espelho nao instalado) nao conta como falhada
if systemctl is-failed --quiet pmo-linear.service; then bad "espelho do Linear (pmo-linear.service falhou)"; fi

echo "docker"
if systemctl is-active --quiet docker; then ok "docker ativo, $(timeout 10 docker ps -q 2>/dev/null | wc -l) container(s)"
else bad "docker parado"; fi

echo "backup"
stamp=/var/lib/stack-vps/last-backup
if ! systemctl is-enabled --quiet stack-backup.timer 2>/dev/null; then
  # decisao de 05/10/2026: restic so depois da migracao; ate la vale o backup diario da Hostinger
  printf '  pend  %s\n' "backup restic desligado — montar depois da migracao (Hostinger cobre ate la)"
elif [[ -f $stamp ]]; then
  age=$(( ($(date +%s) - $(stat -c %Y "$stamp")) / 3600 ))
  (( age <= 36 )) && ok "ultimo backup ha ${age}h" || bad "ultimo backup ha ${age}h (>36h)"
else bad "nunca rodou (sem $stamp)"; fi

echo "sistema"
mem=$(awk '/MemAvailable/{a=$2}/MemTotal/{t=$2}END{print int(a*100/t)}' /proc/meminfo)
if (( mem >= 10 )); then ok "memoria livre ${mem}%"; else bad "memoria livre ${mem}%"; fi
if [[ -f /var/run/reboot-required ]]; then bad "reboot pendente ($(head -3 /var/run/reboot-required.pkgs 2>/dev/null | tr '\n' ' '))"
else ok "sem reboot pendente"; fi
wl=/srv/dev/state/weekly.log
if [[ -f $wl ]] && (( ($(date +%s) - $(stat -c %Y "$wl")) / 86400 <= 8 )); then ok "rotina semanal em dia"
else bad "rotina semanal sem rodar ha mais de 8 dias"; fi

hs=${HEALTH_HOSTINGER:-/usr/local/bin/hostinger.sh}
if [[ -x $hs ]]; then
  echo "hostinger"
  # API externa fora do ar nao e falha do ambiente: so pend, sem fail
  if linha=$("$hs" metricas 2>/dev/null); then printf '%s\n' "$linha"
  else printf '  pend  %s\n' "hostinger indisponível"; fi
fi

unit_ci=stack-ci-runners.service
if systemctl cat "$unit_ci" >/dev/null 2>&1; then
  echo "ci"
  # tudo que vem de /srv/ci e da conta ci (nao confiavel): so contagens formatadas aqui sao impressas
  rede=/usr/local/lib/stack-vps/39-ci-rede.sh
  [[ ${STACK_TESTE:-} == 1 ]] && rede=${HEALTH_CI_REDE:-$rede}
  if [[ ! -x $rede ]]; then bad "isolamento de rede da conta ci inativo (sem 39-ci-rede.sh)"
  elif out=$(timeout 10 "$rede" --status 2>/dev/null) && [[ $out == ativa ]]; then ok "isolamento de rede da conta ci"
  else bad "isolamento de rede da conta ci inativo"; fi
  if systemctl is-active --quiet "$unit_ci"; then
    ci_status=${HEALTH_CI_STATUS:-/srv/ci/status.json}
    r=invalido
    if [[ -f $ci_status && ! -L $ci_status ]]; then
      r=$(timeout 10 python3 -I -c '
import json, math, os, sys, time
try:
    fd = os.open(sys.argv[1], os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK)
    bruto = os.read(fd, 65536 + 1)
    if len(bruto) > 65536: raise ValueError
    d = json.loads(bruto.decode("utf-8"))
    if not isinstance(d, dict): raise ValueError
    a, n, e = d["atualizado"], d["runners"], d["erro"]
    if isinstance(a, bool) or not isinstance(a, (int, float)) or not 0 < a < 4e9: raise ValueError
    if isinstance(n, bool) or not isinstance(n, int) or not 0 <= n <= 1000000: raise ValueError
    if e is not None and not isinstance(e, str): raise ValueError
    idade = time.time() - a
    if idade < -60: raise ValueError
    print("erro" if e is not None else "velho %d" % (idade // 60) if idade > 180 else "ok %d" % n)
except Exception:
    print("invalido")
' "$ci_status" 2>/dev/null) || r=invalido
    fi
    case $r in
      ok\ *) ok "runners (${r#ok })" ;;
      velho\ *) bad "runners sem atualização há ${r#velho } min" ;;
      erro) bad "runners com erro registrado (ver journalctl -u stack-ci-runners)" ;;
      *) bad "runners sem status (arquivo ausente ou inválido)" ;;
    esac
  elif systemctl is-enabled --quiet "$unit_ci" 2>/dev/null; then bad "runners parados (stack-ci-runners inativo)"
  else printf '  pend  %s\n' "runners instalados, mas não habilitados"; fi
fi

# jobs agendados (scripts/45-jobs.sh): so aparece se ha timer stack-job-* instalado. O JSON e do agente (nao
# confiavel): so numeros e o nome do job (validado pelo nome do arquivo) sao impressos.
jobs_units=/etc/systemd/system; jobs_state=/srv/dev/state/jobs
[[ ${STACK_TESTE:-} == 1 ]] && { jobs_units=${HEALTH_JOBS_UNITS:-$jobs_units}; jobs_state=${HEALTH_JOBS_STATE:-$jobs_state}; }
# limite (horas) de idade do ultimo resultado de um job: 2x o maior intervalo entre execucoes + 1h. O intervalo vem do
# systemd-analyze (8 iteracoes: cobre fim de semana em Mon..Fri); sem ele, um palpite pelo texto da agenda
# (diario 36h, semanal ou dias da semana 9d, mensal 33d, anual 400d). Agenda de alta frequencia fica tolerante no palpite.
jobs_limite() {
  local an=systemd-analyze out x e prev=0 max=0 ts=() bx=${1,,}
  [[ ${STACK_TESTE:-} == 1 ]] && an=${HEALTH_ANALYZE:-systemd-analyze}
  if command -v "$an" >/dev/null 2>&1 && [[ $1 != -* ]] && out=$(timeout 10 "$an" calendar --iterations=8 -- "$1" 2>/dev/null); then
    mapfile -t ts < <(sed -nE 's/^[[:space:]]*(Next elapse|Iter[^:]*#[0-9]+):[[:space:]]*//p' <<<"$out")
    for x in "${ts[@]}"; do
      e=$(date -d "$x" +%s 2>/dev/null) || { max=0; break; }
      if (( prev != 0 && e - prev > max )); then max=$((e - prev)); fi
      prev=$e
    done
    if (( max > 0 )); then echo $(( 2 * max / 3600 + 1 )); return; fi
  fi
  case $bx in
    *quarterly*|*semiannually*|*yearly*|*annually*) echo 9600 ;;
    *monthly*) echo 792 ;;
    [0-9*]*-[0-9][0-9]-[0-9]*|[0-9*]*-[0-9]-[0-9]*) echo 9600 ;;   # *-MM-DD: uma vez por ano
    [0-9*]*-\*-[0-9]*) echo 792 ;;                                    # *-*-DD: uma vez por mes
    *weekly*|*mon*|*tue*|*wed*|*thu*|*fri*|*sat*|*sun*) echo 216 ;;
    *) echo 36 ;;
  esac
}
shopt -s nullglob; jobs_timers=("$jobs_units"/stack-job-*.timer); shopt -u nullglob
if (( ${#jobs_timers[@]} > 0 )); then
  echo "jobs"
  for t in "${jobs_timers[@]}"; do
    jn=${t##*/stack-job-}; jn=${jn%.timer}
    [[ $jn =~ ^[a-z0-9-]+$ ]] || continue
    ag=$(sed -n 's/^OnCalendar=//p' "$t" | head -1)
    lim=$(jobs_limite "$ag")
    jf=$jobs_state/$jn.json; r=invalido
    if [[ -f $jf && ! -L $jf ]]; then
      r=$(timeout 10 python3 -I -c '
import json, os, sys, time
try:
    fd = os.open(sys.argv[1], os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK)
    bruto = os.read(fd, 65536 + 1)
    if len(bruto) > 65536: raise ValueError
    d = json.loads(bruto.decode("utf-8"))
    if not isinstance(d, dict): raise ValueError
    rc, fim = d["rc"], d["fim"]
    if isinstance(rc, bool) or not isinstance(rc, int) or not 0 <= rc <= 100000: raise ValueError
    ach = d.get("achados", 0)
    if isinstance(ach, bool) or not isinstance(ach, int) or not 0 <= ach <= 1000000: raise ValueError
    if isinstance(fim, bool) or not isinstance(fim, (int, float)) or not 0 < fim < 4e9: raise ValueError
    idade = time.time() - fim
    if idade < -60: raise ValueError
    h = int(idade // 3600)
    print("rc %d" % rc if rc != 0 else "velho %d" % h if h > int(sys.argv[2]) else "achados" if ach > 0 else "ok %d" % h)
except Exception:
    print("invalido")
' "$jf" "$lim" 2>/dev/null) || r=invalido
    elif [[ ! -e $jf && ! -L $jf ]]; then
      r=ausente
    fi
    case $r in
      ok\ *) ok "job $jn (rc 0 há ${r#ok }h)" ;;
      achados) printf '  pend  %s\n' "job $jn: achados na ultima varredura" ;;
      rc\ *) bad "job $jn falhou (rc ${r#rc })" ;;
      velho\ *) bad "job $jn sem rodar há ${r#velho }h (limite ${lim}h)" ;;
      ausente)
        ti=$(( ($(date +%s) - $(stat -c %Y "$t")) / 3600 ))
        if (( ti < lim )); then printf '  pend  %s\n' "job $jn aguardando o primeiro ciclo"
        else bad "job $jn nunca rodou (timer instalado há ${ti}h)"; fi ;;
      *) bad "job $jn com status inválido" ;;
    esac
  done
fi

echo "disco"
use=$(df --output=pcent /srv | tail -1 | tr -dc '0-9')
(( use < 85 )) && ok "/srv em ${use}%" || bad "/srv em ${use}%"

exit $fail
