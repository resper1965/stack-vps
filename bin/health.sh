#!/usr/bin/env bash
# Estado do ambiente: tunnel, docker, ultimo backup, disco. Saida curta, exit 1 se algo falhar.
set -uo pipefail
fail=0
ok(){ printf '  ok    %s\n' "$*"; }
bad(){ printf '  FALHA %s\n' "$*"; fail=1; }

echo "tunnel"
if systemctl is-active --quiet cloudflared; then ok "cloudflared ativo ($(systemctl show -p ActiveEnterTimestamp --value cloudflared))"
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

echo "disco"
use=$(df --output=pcent /srv | tail -1 | tr -dc '0-9')
(( use < 85 )) && ok "/srv em ${use}%" || bad "/srv em ${use}%"

exit $fail
