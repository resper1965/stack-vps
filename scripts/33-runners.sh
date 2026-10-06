#!/usr/bin/env bash
# Runners efemeros (compose/runners.yml) para as organizacoes indicadas. Idempotente.
# Uso: sudo ./33-runners.sh <org> [<org> ...]   ex.: sudo ./33-runners.sh nessenergy bekaa-trusted-advisors
# Token: RUNNER_TOKEN no admin.env (PAT com admin:org, ou fine-grained com "Self-hosted runners: write"
# na organizacao). Nunca registrar runner em organizacao com repositorio publico que use o rotulo stack:
# um fork poderia rodar codigo na VPS. Na organizacao, restringir o grupo de runners a repos privados.
set -euo pipefail
[[ $EUID -eq 0 ]] || { echo "rode como root"; exit 1; }
(( $# )) || { echo "uso: $0 <org> [<org> ...]"; exit 1; }
REPO=$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)
T=$(grep -m1 '^RUNNER_TOKEN=' /srv/dev/secrets/admin.env | cut -d= -f2- || true)
[[ -n $T ]] || { echo "falta RUNNER_TOKEN no admin.env"; exit 1; }
install -d -m 700 /srv/runners
ESCALA=${RUNNERS_POR_ORG:-3}
for org in "$@"; do
  (umask 077; printf 'ORG=%s\nRUNNER_TOKEN=%s\n' "$org" "$T" > "/srv/runners/$org.env")
  docker compose -p "runners-$org" --env-file "/srv/runners/$org.env" -f "$REPO/compose/runners.yml" \
    up -d --quiet-pull --scale runner="$ESCALA"
  echo "$org: $(docker ps --filter "label=com.docker.compose.project=runners-$org" -q | wc -l) runner(s)"
done
