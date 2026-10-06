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

# segredos em niveis: admin.env so do dev; agente.env e projetos/ legiveis pelo grupo agente
getent group agente >/dev/null || groupadd agente   # o usuario nasce no 16; o grupo ja serve as permissoes
install -d -m 750 -o dev -g agente /srv/dev/secrets /srv/dev/secrets/projetos
[[ -f /srv/dev/secrets/admin.env ]]  || install -m 600 -o dev -g dev    /dev/null /srv/dev/secrets/admin.env
[[ -f /srv/dev/secrets/agente.env ]] || install -m 640 -o dev -g agente /dev/null /srv/dev/secrets/agente.env
# chaves de projeto: um arquivo so para todos (decisao de 30/09); o dev edita, o agente le
[[ -f /srv/dev/secrets/projetos.env ]] || install -m 640 -o dev -g agente /dev/null /srv/dev/secrets/projetos.env
# dados de cliente e evidencias: so o dev
chmod 750 /srv/dev/data
install -d -m 750 -o dev -g dev /srv/forense

echo "layout ok:"; find /srv/dev -maxdepth 2 -type d -printf '%M %u %p\n' | sort -k3
