#!/usr/bin/env bash
# Confere o Postgres de teste descartavel (/srv/dev/bin/postgres.yml, instalado pelo 05).
# Roda COMO agente. Idempotente. Regra de uso: docs/AGENTS.md, secao Ambiente.
set -euo pipefail
[[ $(id -un) == agente ]] || { echo "rode como agente: sudo -u agente -H $0"; exit 1; }
DOCKER_HOST="unix:///run/user/$(id -u)/docker.sock"; export DOCKER_HOST
docker info >/dev/null 2>&1 || { echo "docker rootless do agente parado: rode 16-agente.sh"; exit 1; }
[[ -f /srv/dev/bin/postgres.yml ]] || { echo "falta /srv/dev/bin/postgres.yml: rode 05-servicos.sh"; exit 1; }
docker compose -f /srv/dev/bin/postgres.yml config -q
echo "ok: /srv/dev/bin/postgres.yml"
