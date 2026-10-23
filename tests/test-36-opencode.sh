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
if ls "$CFG".* >/dev/null 2>&1; then falha "sem temporario sobrando apos falha"; else ok "sem temporario sobrando apos falha"; fi
# arquivo de 0 bytes: tratado como {} (nada a perder)
: > "$CFG"; roda; afirma_rc $RC 0 "opencode.json de 0 bytes: tratado como {}"
jq -e '.provider["9router"]' "$CFG" >/dev/null; afirma $? "0 bytes: provedor escrito"
# modo preservado
chmod 644 "$CFG"; roda; if [[ $(stat -c %a "$CFG") == 644 ]]; then ok "modo 0644 preservado"; else falha "modo 0644 preservado"; fi
chmod 600 "$CFG"; roda; if [[ $(stat -c %a "$CFG") == 600 ]]; then ok "modo 0600 preservado"; else falha "modo 0600 preservado"; fi
rm "$CFG"; roda; if [[ $(stat -c %a "$CFG") == 600 ]]; then ok "criado do zero com 0600"; else falha "criado do zero com 0600"; fi
# symlink: escreve no alvo e mantem o link
mv "$CFG" "$T/alvo.json"; ln -s "$T/alvo.json" "$CFG"; roda; afirma_rc $RC 0 "opencode.json symlink"
if [[ -L $CFG ]] && jq -e '.provider["9router"]' "$T/alvo.json" >/dev/null; then ok "symlink mantido, alvo atualizado"; else falha "symlink mantido, alvo atualizado"; fi
prepara; echo "OPENCODE_SERVER_PASSWORD=$SENHA" > "$ENV"; chmod 600 "$ENV"
JQ_BIN=jq-que-nao-existe roda; afirma_rc $RC 1 "sem jq: falha"
grep -q 'jq' "$T/saida"; afirma $? "sem jq: mensagem clara"; nada "sem jq"
# comando /novo-projeto: copia idempotente; arquivo do dono sem marcador e preservado
prepara; echo "OPENCODE_SERVER_PASSWORD=$SENHA" > "$ENV"; chmod 600 "$ENV"
CMD=$HOME/.config/opencode/command/novo-projeto.md
roda; afirma_rc $RC 0 "instala o comando"
cmp -s "$CMD" "$RAIZ_REPO/opencode/command/novo-projeto.md"; afirma $? "comando igual ao do repo"
SUM=$(cat "$CMD"); roda; if [[ $SUM == "$(cat "$CMD")" ]]; then ok "comando idempotente"; else falha "comando idempotente"; fi
echo '<!-- stack-vps -->
antigo' > "$CMD"; roda; cmp -s "$CMD" "$RAIZ_REPO/opencode/command/novo-projeto.md"; afirma $? "com marcador: atualiza"
echo 'meu comando' > "$CMD"; roda; afirma_rc $RC 0 "comando do dono: segue"
if [[ $(cat "$CMD") == 'meu comando' ]]; then ok "comando do dono preservado"; else falha "comando do dono preservado"; fi
grep -qF 'AVISO' "$T/saida"; afirma $? "comando do dono: avisa"
# marcador no repo, convergencia e limite das 6 linhas
CMDREPO=$RAIZ_REPO/opencode/command/novo-projeto.md
head -n 6 "$CMDREPO" | grep -qF '<!-- stack-vps -->'; afirma $? "repo: marcador nas 6 primeiras linhas"
cp "$CMDREPO" "$CMD"; printf '\nextra\n' >> "$CMD"; roda; cmp -s "$CMD" "$CMDREPO"; afirma $? "copia com marcador alterada converge"
printf 'a\nb\nc\nd\ne\nf\n<!-- stack-vps -->\n' > "$CMD"; roda
if [[ $(head -n1 "$CMD") == a ]]; then ok "marcador na linha 7: arquivo do dono"; else falha "marcador na linha 7: arquivo do dono"; fi
# repo mudou depois da 1a instalacao: reexecucao converge (repo falso em arvore temporaria)
prepara; echo "OPENCODE_SERVER_PASSWORD=$SENHA" > "$ENV"; chmod 600 "$ENV"
FAKE=$T/repo; mkdir -p "$FAKE/scripts" "$FAKE/opencode/command"
cp "$S" "$FAKE/scripts/"; cp "$RAIZ_REPO"/opencode/*.* "$FAKE/opencode/"; cp "$CMDREPO" "$FAKE/opencode/command/"
bash "$FAKE/scripts/36-opencode.sh" >/dev/null 2>&1; printf 'novidade\n' >> "$FAKE/opencode/command/novo-projeto.md"
bash "$FAKE/scripts/36-opencode.sh" >/dev/null 2>&1; cmp -s "$HOME/.config/opencode/command/novo-projeto.md" "$FAKE/opencode/command/novo-projeto.md"; afirma $? "repo alterado: reexecucao converge"
# repo sem o comando: exit 1
rm "$FAKE/opencode/command/novo-projeto.md"; bash "$FAKE/scripts/36-opencode.sh" >"$T/saida" 2>&1; afirma_rc $? 1 "sem comando no repo"
grep -q 'novo-projeto.md' "$T/saida"; afirma $? "sem comando no repo: mensagem"
# symlink do dono
prepara; echo "OPENCODE_SERVER_PASSWORD=$SENHA" > "$ENV"; chmod 600 "$ENV"
CMD=$HOME/.config/opencode/command/novo-projeto.md; mkdir -p "${CMD%/*}"
printf '<!-- stack-vps -->\nvelho\n' > "$T/alvo.md"; ln -s "$T/alvo.md" "$CMD"; roda
if [[ -L $CMD ]] && cmp -s "$T/alvo.md" "$CMDREPO"; then ok "symlink com marcador: alvo atualizado, link mantido"; else falha "symlink com marcador: alvo atualizado, link mantido"; fi
echo 'do dono' > "$T/alvo.md"; roda
if [[ -L $CMD && $(cat "$T/alvo.md") == 'do dono' ]]; then ok "symlink sem marcador: intocado"; else falha "symlink sem marcador: intocado"; fi
if ls "$T"/alvo.md.* >/dev/null 2>&1; then falha "sem temporario do comando sobrando"; else ok "sem temporario do comando sobrando"; fi

# flags, caminho e valores citados no comando vs. gerador: conjuntos exatos
GER=$RAIZ_REPO/scripts/42-novo-projeto.py
AJUDA=$(python3 "$GER" --help)
FLAGS_AJUDA=$(grep -o -- '--[a-z]\+' <<<"$AJUDA" | sort -u)
FLAGS_MD=$(grep -o -- '--[a-z]\+' "$CMDREPO" | grep -vx -- '--private' | sort -u)  # --private e do gh
if [[ -n $FLAGS_MD && -z $(comm -23 <(echo "$FLAGS_MD") <(echo "$FLAGS_AJUDA")) ]]; then ok "flags do comando contidas nas do gerador"; else falha "flags do comando contidas nas do gerador"; fi
for f in --apply --destino --natureza --nome; do grep -qx -- "$f" <<<"$FLAGS_MD"; afirma $? "comando cita $f"; done
grep -qF '/opt/stack-vps/scripts/42-novo-projeto.py' "$CMDREPO" && [[ -f $GER ]]; afirma $? "caminho do gerador citado existe no repo"
ESC=$(grep -o '{[a-z,]*}' <<<"$AJUDA" | head -1 | tr -d '{}' | tr ',' '\n' | sort)
CIT=$(grep -o '`[a-z]*`' "$CMDREPO" | tr -d '`' | grep -Fxf <(echo "$ESC") | sort -u)
if [[ $CIT == "$ESC" ]]; then ok "valores de --natureza citados = choices do gerador"; else falha "valores de --natureza citados = choices do gerador"; fi
fim
