#!/usr/bin/env bash
# shellcheck source=tests/lib.sh
. "$(dirname "$0")/lib.sh"
S=$RAIZ_REPO/scripts/36-opencode.sh
SENHA=senha-de-teste-xyz
echo "36-opencode (web.env validado antes de tocar em qualquer coisa)"

# cenario: HOME temporario, binario e unidade em pastas do teste
prepara() {
  novo_tmp; stub systemctl
  export HOME=$T/home OPENCODE_UNIT_DIR=$T/unit OPENCODE_BIN=$T/opencode
  mkdir -p "$HOME/.config/opencode"; printf '#!/bin/sh\n' > "$OPENCODE_BIN"; chmod +x "$OPENCODE_BIN"
  ENV=$HOME/.config/opencode/web.env
}
roda() { bash "$S" > "$T/saida" 2>&1; RC=$?; }
nada() { nega_log systemctl "$1: systemctl nao chamado"; [[ ! -e $OPENCODE_UNIT_DIR/opencode-web.service ]]; afirma $? "$1: unidade nao instalada"; }

prepara; roda; afirma_rc $RC 1 "sem web.env"
grep -qF 'crie ~/.config/opencode/web.env' "$T/saida"; afirma $? "mensagem pede para criar o web.env"; nada "sem web.env"

prepara; : > "$ENV"; chmod 600 "$ENV"; roda; afirma_rc $RC 1 "web.env vazio"; nada "web.env vazio"
prepara; echo 'OUTRA=1' > "$ENV"; chmod 600 "$ENV"; roda; afirma_rc $RC 1 "sem OPENCODE_SERVER_PASSWORD"; nada "sem a chave"
prepara; echo 'OPENCODE_SERVER_PASSWORD=' > "$ENV"; chmod 600 "$ENV"; roda; afirma_rc $RC 1 "senha em branco"; nada "senha em branco"
prepara; echo "OPENCODE_SERVER_PASSWORD=$SENHA" > "$ENV"; chmod 644 "$ENV"; roda; afirma_rc $RC 1 "web.env 0644"; nada "web.env 0644"
prepara; echo "OPENCODE_SERVER_PASSWORD=$SENHA" > "$ENV"; chmod 600 "$ENV"; rm "$OPENCODE_BIN"; roda; afirma_rc $RC 1 "sem binario"; nada "sem binario"

prepara; echo "OPENCODE_SERVER_PASSWORD=$SENHA" > "$ENV"; chmod 600 "$ENV"; roda; afirma_rc $RC 0 "caso valido"
U=$OPENCODE_UNIT_DIR/opencode-web.service; D=$OPENCODE_UNIT_DIR/opencode-web.service.d/password.conf
grep -q '127.0.0.1' "$U" && grep -q '4096' "$U"; afirma $? "unidade escuta 127.0.0.1:4096"
! grep -q '0.0.0.0' "$U"; afirma $? "unidade sem 0.0.0.0"
grep -q 'EnvironmentFile=%h/.config/opencode/web.env' "$D"; afirma $? "drop-in aponta o web.env"
afirma_log "--user daemon-reload" "daemon-reload"
afirma_log "--user enable --now opencode-web.service" "enable --now"
! grep -qF "$SENHA" "$T/saida" "$STUB_LOG"; afirma $? "senha fora da saida e do log"
if [[ $(stat -c %a "$ENV") == 600 && $(cat "$ENV") == "OPENCODE_SERVER_PASSWORD=$SENHA" ]]; then ok "web.env intocado"; else falha "web.env intocado"; fi
SUM=$(cat "$U" "$D"); roda; afirma_rc $RC 0 "segunda execucao"
[[ $SUM == "$(cat "$U" "$D")" ]]; afirma $? "idempotente"
fim
