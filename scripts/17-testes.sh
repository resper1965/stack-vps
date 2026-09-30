#!/usr/bin/env bash
# Postgres de teste descartavel em /srv/dev/bin, onde os agentes acham.
# Roda COMO dev. Idempotente. Regra de uso: CLAUDE.md/AGENTS.md §8.
set -euo pipefail
[[ $(id -un) == dev ]] || { echo "rode como dev"; exit 1; }
R=$(cd "$(dirname "$0")/.." && pwd)
id -nG | grep -qw docker || { echo "dev fora do grupo docker: rode 03-tooling.sh e entre de novo"; exit 1; }
install -m 644 "$R/compose/postgres.yml" /srv/dev/bin/postgres.yml
docker compose -f /srv/dev/bin/postgres.yml config -q
echo "ok: /srv/dev/bin/postgres.yml"
