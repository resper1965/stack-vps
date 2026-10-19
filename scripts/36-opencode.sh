#!/usr/bin/env bash
# OpenCode web do agente: unidade de usuario so em 127.0.0.1:4096, senha vinda de ~/.config/opencode/web.env
# (criado pelo dono; este script so valida, nunca gera, imprime nem sobrescreve). Nao instala o OpenCode.
# Idempotente. Uso: sudo -u agente -H bash -c 'cd ~ && /opt/stack-vps/scripts/36-opencode.sh'
set -euo pipefail
[[ $(id -un) == agente || ${STACK_TESTE:-} == 1 ]] || { echo "rode como agente"; exit 1; }
REPO=$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)
BIN=${OPENCODE_BIN:-$HOME/.opencode/bin/opencode}
ENV_SENHA=$HOME/.config/opencode/web.env
MSG_ENV='~'/.config/opencode/web.env  # so para mensagens
UNIDADES=${OPENCODE_UNIT_DIR:-$HOME/.config/systemd/user}

[[ -x $BIN ]] || { echo "OpenCode nao encontrado em $BIN (instale antes)"; exit 1; }
[[ -f $ENV_SENHA ]] || { echo "crie $MSG_ENV"; exit 1; }
[[ $(stat -c %a "$ENV_SENHA") == 600 ]] || { echo "$MSG_ENV deve ter modo 0600"; exit 1; }
grep -Eq '^OPENCODE_SERVER_PASSWORD=.+' "$ENV_SENHA" || { echo "$MSG_ENV sem OPENCODE_SERVER_PASSWORD= preenchido"; exit 1; }

install -d "$UNIDADES/opencode-web.service.d"
install -m 644 "$REPO/opencode/opencode-web.service" "$UNIDADES/opencode-web.service"
install -m 644 "$REPO/opencode/password.conf" "$UNIDADES/opencode-web.service.d/password.conf"
systemctl --user daemon-reload
systemctl --user enable --now opencode-web.service
echo "opencode-web ativo em 127.0.0.1:4096"
