#!/usr/bin/env bash
# 9router (faixa 1: so chaves de API) do agente: instala a versao fixa em ~/.local e sobe a unidade de usuario
# em 127.0.0.1:20128. Segredos vem de ~/.config/9router/9router.env (criado pelo dono; este script so valida,
# nunca gera, imprime nem sobrescreve). Idempotente.
# Uso: sudo -u agente -H bash -c 'cd ~ && /opt/stack-vps/scripts/41-9router.sh'
set -euo pipefail
[[ $(id -un) == agente || ${STACK_TESTE:-} == 1 ]] || { echo "rode como agente"; exit 1; }
# sob "sudo -u agente -H bash -c" a variavel vem vazia e o systemctl --user nao acha o bus
export XDG_RUNTIME_DIR=${XDG_RUNTIME_DIR:-/run/user/$(id -u)}
REPO=$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)
VERSAO=0.5.104
PREFIXO=$HOME/.local
AMBIENTE=$HOME/.config/9router/9router.env
UNIDADES=$HOME/.config/systemd/user
NPM=npm
if [[ ${STACK_TESTE:-} == 1 ]]; then
  PREFIXO=${NR_PREFIX:-$PREFIXO}; AMBIENTE=${NR_ENV:-$AMBIENTE}
  UNIDADES=${NR_UNIT_DIR:-$UNIDADES}; NPM=${NR_NPM:-$NPM}
fi
MSG_ENV='~'/.config/9router/9router.env  # so para mensagens

valor() { grep -E "^$1=" "$AMBIENTE" | tail -n1 | cut -d= -f2-; }

[[ -f $AMBIENTE && ! -L $AMBIENTE ]] || { echo "crie $MSG_ENV (arquivo comum, nao link)"; exit 1; }
[[ $(stat -c %U "$AMBIENTE") == "$(id -un)" ]] || { echo "$MSG_ENV deve pertencer ao usuario atual"; exit 1; }
[[ $(stat -c %a "$AMBIENTE") == 600 ]] || { echo "$MSG_ENV deve ter modo 0600"; exit 1; }
# o systemd interpreta aspas e o grep nao: recusar o que os dois leriam diferente
if grep -q $'\r' "$AMBIENTE"; then echo "$MSG_ENV tem CR (fim de linha do Windows)"; exit 1; fi
senha=$(valor INITIAL_PASSWORD || true)
jwt=$(valor JWT_SECRET || true)
# o minimo de 16 e o unico criterio de senha fraca (123456 cai nele)
[[ ${#senha} -ge 16 ]] || { echo "$MSG_ENV: INITIAL_PASSWORD ausente ou curta (< 16)"; exit 1; }
[[ -n $jwt ]] || { echo "$MSG_ENV sem JWT_SECRET= preenchido"; exit 1; }
[[ $senha != [\'\"]* && $jwt != [\'\"]* ]] || { echo "$MSG_ENV: INITIAL_PASSWORD/JWT_SECRET nao podem comecar com aspas"; exit 1; }
[[ -f $REPO/9router/9router.service ]] || { echo "falta $REPO/9router/9router.service"; exit 1; }

instalada=$(grep -m1 '"version"' "$PREFIXO/lib/node_modules/9router/package.json" 2>/dev/null | cut -d'"' -f4 || true)
if [[ $instalada != "$VERSAO" ]]; then
  "$NPM" install -g --prefix "$PREFIXO" "9router@$VERSAO" >&2
fi

install -d -m 700 "$HOME/.9router"
chmod 700 "$HOME/.9router"
install -d "$UNIDADES"
install -m 644 "$REPO/9router/9router.service" "$UNIDADES/9router.service"
systemctl --user daemon-reload
systemctl --user enable --now 9router.service
systemctl --user try-restart 9router.service  # unidade ou ambiente trocados valem ja, nao so no proximo boot
echo "9router ativo em 127.0.0.1:20128"
