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

echo "disco"
use=$(df --output=pcent /srv | tail -1 | tr -dc '0-9')
(( use < 85 )) && ok "/srv em ${use}%" || bad "/srv em ${use}%"

exit $fail
