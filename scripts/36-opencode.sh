#!/usr/bin/env bash
# OpenCode web do agente: unidade de usuario so em 127.0.0.1:4096, senha vinda de ~/.config/opencode/web.env
# (criado pelo dono; este script so valida, nunca gera, imprime nem sobrescreve). Nao instala o OpenCode.
# Idempotente. Uso: sudo -u agente -H bash -c 'cd ~ && /opt/stack-vps/scripts/36-opencode.sh'
set -euo pipefail
[[ $(id -un) == agente || ${STACK_TESTE:-} == 1 ]] || { echo "rode como agente"; exit 1; }
# sob "sudo -u agente -H bash -c" a variavel vem vazia e o systemctl --user nao acha o bus
export XDG_RUNTIME_DIR=${XDG_RUNTIME_DIR:-/run/user/$(id -u)}
REPO=$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)
BIN=${OPENCODE_BIN:-$HOME/.opencode/bin/opencode}
ENV_SENHA=$HOME/.config/opencode/web.env
MSG_ENV='~'/.config/opencode/web.env  # so para mensagens
UNIDADES=${OPENCODE_UNIT_DIR:-$HOME/.config/systemd/user}
CONFIG=$HOME/.config/opencode/opencode.json
JQ=jq
[[ ${STACK_TESTE:-} == 1 ]] && JQ=${JQ_BIN:-jq}

[[ -x $BIN ]] || { echo "OpenCode nao encontrado em $BIN (instale antes)"; exit 1; }
[[ -f $ENV_SENHA ]] || { echo "crie $MSG_ENV"; exit 1; }
[[ $(stat -c %a "$ENV_SENHA") == 600 ]] || { echo "$MSG_ENV deve ter modo 0600"; exit 1; }
grep -Eq '^OPENCODE_SERVER_PASSWORD=.+' "$ENV_SENHA" || { echo "$MSG_ENV sem OPENCODE_SERVER_PASSWORD= preenchido"; exit 1; }
command -v "$JQ" >/dev/null || { echo "jq nao encontrado (apt install jq)"; exit 1; }
[[ -f $REPO/opencode/command/novo-projeto.md ]] || { echo "falta $REPO/opencode/command/novo-projeto.md"; exit 1; }
[[ -f $REPO/opencode/provider-9router.json ]] || { echo "falta $REPO/opencode/provider-9router.json"; exit 1; }

install -d "$UNIDADES/opencode-web.service.d"
install -m 644 "$REPO/opencode/opencode-web.service" "$UNIDADES/opencode-web.service"
install -m 644 "$REPO/opencode/password.conf" "$UNIDADES/opencode-web.service.d/password.conf"
# comando /novo-projeto: o marcador identifica a copia do repo; arquivo do dono sem ele nunca e sobrescrito
install -d "$HOME/.config/opencode/command"  # readlink -f exige o diretorio
CMD=$(readlink -f "$HOME/.config/opencode/command/novo-projeto.md")  # link do dono: decide e escreve no alvo
novo=""; cmd_novo=""
trap 'rm -f "$novo" "$cmd_novo"' EXIT
if [[ -e $CMD ]] && ! head -n 6 "$CMD" | grep -qF '<!-- stack-vps -->'; then
  echo "AVISO: $CMD e do dono (sem o marcador <!-- stack-vps -->); comando /novo-projeto nao instalado"
else
  install -d "$(dirname "$CMD")"
  cmd_novo=$(mktemp "$CMD.XXXXXX")
  install -m 644 "$REPO/opencode/command/novo-projeto.md" "$cmd_novo"
  mv "$cmd_novo" "$CMD"
fi
# provedor 9router: o bloco do repo vence, o resto do opencode.json (e os modelos do dono) fica; model/small_model nunca
CONFIG=$(readlink -f "$CONFIG")  # link do dono: escreve no alvo, nunca troca o link
[[ -f $CONFIG ]] || (umask 077; echo '{}' > "$CONFIG")
[[ -s $CONFIG ]] || echo '{}' > "$CONFIG"  # arquivo vazio nao tem o que perder
novo=$(mktemp "$CONFIG.XXXXXX")
"$JQ" --slurpfile p "$REPO/opencode/provider-9router.json"   '.provider["9router"] = ((.provider["9router"] // {}) * $p[0].provider["9router"])' "$CONFIG" > "$novo"   && [[ -s $novo ]] || { echo "opencode.json invalido, nada alterado"; exit 1; }
chmod --reference="$CONFIG" "$novo"; mv "$novo" "$CONFIG"
systemctl --user daemon-reload
systemctl --user enable --now opencode-web.service
systemctl --user try-restart opencode-web.service  # unidade ou senha trocadas valem ja, nao so no proximo boot
echo "opencode-web ativo em 127.0.0.1:4096"
