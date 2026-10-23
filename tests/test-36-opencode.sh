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
if [[ $SUM == "$(cat "$U" "$D")" ]]; then ok "idempotente"; else falha "idempotente"; fi
afirma_log "--user try-restart opencode-web.service" "try-restart para pegar unidade ou senha novas"

# sob sudo -u agente -H bash -c o XDG_RUNTIME_DIR vem vazio: o systemctl --user precisa recebe-lo preenchido
prepara; echo "OPENCODE_SERVER_PASSWORD=$SENHA" > "$ENV"; chmod 600 "$ENV"
cat > "$STUBS/systemctl" <<'EOS'
#!/usr/bin/env bash
echo "systemctl $* [XDG_RUNTIME_DIR=${XDG_RUNTIME_DIR:-}]" >> "$STUB_LOG"
[[ -n ${XDG_RUNTIME_DIR:-} ]] || exit 1
EOS
chmod +x "$STUBS/systemctl"
XDG_RUNTIME_DIR='' roda; afirma_rc $RC 0 "XDG_RUNTIME_DIR vazio: o script o preenche"
uid=$(id -u); afirma_log "[XDG_RUNTIME_DIR=/run/user/$uid]" "systemctl --user recebeu /run/user/<uid>"
roda_com() { XDG_RUNTIME_DIR=$1 roda; }; roda_com /outro; afirma_log "[XDG_RUNTIME_DIR=/outro]" "valor ja definido e respeitado"

# provedor 9router no opencode.json: merge com jq, preserva as chaves do dono, nunca define model/small_model
prepara; echo "OPENCODE_SERVER_PASSWORD=$SENHA" > "$ENV"; chmod 600 "$ENV"
CFG=$HOME/.config/opencode/opencode.json
printf '{"theme":"dark","model":"x/y","provider":{"outro":{"npm":"z"},"9router":{"models":{"m1":{}}}}}
' > "$CFG"
roda; afirma_rc $RC 0 "merge em opencode.json existente"
jq -e '.theme=="dark" and .model=="x/y" and .provider.outro.npm=="z"' "$CFG" >/dev/null; afirma $? "preserva as demais chaves do dono"
jq -e '.provider["9router"].npm=="@ai-sdk/openai-compatible" and .provider["9router"].options.baseURL=="http://127.0.0.1:20128/v1" and .provider["9router"].options.apiKey=="{env:NINE_ROUTER_API_KEY}" and .provider["9router"].models.m1' "$CFG" >/dev/null; afirma $? "provedor 9router por referencia, modelos do dono mantidos"
SUM=$(cat "$CFG"); roda; if [[ $SUM == "$(cat "$CFG")" ]]; then ok "merge idempotente"; else falha "merge idempotente"; fi
rm "$CFG"; roda; afirma_rc $RC 0 "sem opencode.json: cria"
jq -e 'has("model")==false and has("small_model")==false and (.provider|keys)==["9router"]' "$CFG" >/dev/null; afirma $? "criado sem model/small_model"
echo '{quebrado' > "$CFG"; roda; afirma_rc $RC 1 "opencode.json invalido: recusa"
if [[ $(cat "$CFG") == '{quebrado' ]]; then ok "opencode.json invalido intocado"; else falha "opencode.json invalido intocado"; fi
prepara; echo "OPENCODE_SERVER_PASSWORD=$SENHA" > "$ENV"; chmod 600 "$ENV"
JQ_BIN=jq-que-nao-existe roda; afirma_rc $RC 1 "sem jq: falha"
grep -q 'jq' "$T/saida"; afirma $? "sem jq: mensagem clara"; nada "sem jq"
fim
