#!/usr/bin/env bash
# Arvore /srv/dev. Idempotente. Uso: sudo ./02-layout.sh
set -euo pipefail
[[ $EUID -eq 0 ]] || { echo "rode como root"; exit 1; }
id dev &>/dev/null || { echo "usuario dev nao existe: rode 01-baseline.sh antes"; exit 1; }

for d in repos/apps repos/orm repos/agents repos/infra data state/reviews bin skills; do
  install -d -m 755 -o dev -g dev "/srv/dev/$d"
done
# install -d nao aplica o dono nos diretorios-pai que ele cria
chown dev:dev /srv/dev /srv/dev/repos /srv/dev/state

install -d -m 700 -o dev -g dev /srv/dev/secrets
[[ -f /srv/dev/secrets/.env ]] || install -m 600 -o dev -g dev /dev/null /srv/dev/secrets/.env

echo "layout ok:"; find /srv/dev -maxdepth 2 -type d -printf '%M %u %p\n' | sort -k3
