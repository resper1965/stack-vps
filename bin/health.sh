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

echo "docker"
if systemctl is-active --quiet docker; then ok "docker ativo, $(docker ps -q 2>/dev/null | wc -l) container(s)"
else bad "docker parado"; fi

echo "backup"
stamp=/srv/dev/state/.last-backup
if [[ -f $stamp ]]; then
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

echo "disco"
use=$(df --output=pcent /srv | tail -1 | tr -dc '0-9')
(( use < 85 )) && ok "/srv em ${use}%" || bad "/srv em ${use}%"

exit $fail
