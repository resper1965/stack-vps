#!/usr/bin/env bash
# Coder Community (compose/coder.yml) em /srv/coder. Idempotente. Uso: sudo ./32-coder.sh
# Gera /srv/coder/coder.env na primeira vez (senha do Postgres aleatoria) e atualiza o OAuth do
# GitHub a partir do admin.env (CODER_GITHUB_CLIENT_ID / CODER_GITHUB_CLIENT_SECRET) quando existir.
set -euo pipefail
[[ $EUID -eq 0 ]] || { echo "rode como root"; exit 1; }
REPO=$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)
E=/srv/coder/coder.env
install -d -m 700 /srv/coder /srv/coder/postgres
install -d -m 700 -o 1000 -g 1000 /srv/coder/home

[[ -f $E ]] || { umask 077; printf 'PG_SENHA=%s\n' "$(head -c 24 /dev/urandom | base64 | tr -dc 'A-Za-z0-9')" > "$E"; }
sed -i '/^DOCKER_GID=/d' "$E"; echo "DOCKER_GID=$(getent group docker | cut -d: -f3)" >> "$E"
A=/srv/dev/secrets/admin.env
for k in CODER_GITHUB_CLIENT_ID CODER_GITHUB_CLIENT_SECRET; do
  v=$(grep -m1 "^$k=" "$A" 2>/dev/null | cut -d= -f2- || true)
  if [[ -n $v ]]; then sed -i "/^$k=/d" "$E"; echo "$k=$v" >> "$E"; fi
done
chmod 600 "$E"

docker compose -p coder --env-file "$E" -f "$REPO/compose/coder.yml" up -d --quiet-pull
for _ in $(seq 1 60); do curl -fs http://127.0.0.1:7080/healthz >/dev/null 2>&1 && break; sleep 2; done
echo "coder: $(curl -fs http://127.0.0.1:7080/healthz || echo sem resposta) | $(docker exec coder-coder-1 coder --version 2>/dev/null | head -1)"
grep -q '^CODER_GITHUB_CLIENT_ID=.' "$E" || echo "login GitHub ainda sem OAuth App (ver plano, Task 5)"
