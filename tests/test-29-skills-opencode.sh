#!/usr/bin/env bash
# 29-skills.sh: as regras globais chegam ao OpenCode (~/.config/opencode/AGENTS.md).
# O script inteiro nao roda fora da VPS (npx, claude, agy); testa-se o codigo REAL da secao de
# regras, extraido entre as ancoras `bloco() {` e a ultima grava_bloco do OpenCode. A secao roda em
# <tmp>/repo/scripts/, entao o DOCS que o proprio script calcula cai no docs/ falso, sem override.
. "$(dirname "$0")/lib.sh"
novo_tmp
SRC=$RAIZ_REPO/scripts/29-skills.sh
REPO=$T/repo; mkdir -p "$REPO/scripts" "$REPO/docs"
printf 'REGRA-GLOBAL-FALSA\n' > "$REPO/docs/AGENTS.md"
printf 'COMPLEMENTO-CLAUDE-FALSO\n' > "$REPO/docs/CLAUDE.md"

# falha alto se uma ancora sumir: o teste nao pode passar no vazio
{ echo 'set -euo pipefail'; awk '/^bloco\(\) \{/{d=1} d{print} d && /^grava_bloco ~\/\.config\/opencode\/AGENTS\.md "instrucoes do agente"/{f=1; exit} END{exit !(f)}' "$SRC"; } > "$REPO/scripts/secao.sh"
rc=$?
afirma_rc "$rc" 0 "ancoras da secao de regras presentes no 29-skills.sh"
[[ $rc == 0 ]] || fim
grep -q '^DOCS=' "$REPO/scripts/secao.sh" || { falha "secao sem o calculo de DOCS"; fim; }

H=$T/home; OC=$H/.config/opencode
mkdir -p "$H/.codex" "$H/.claude" "$H/.claude-ionic" "$H/.gemini/config/rules" "$OC"
chmod 700 "$OC"
printf 'SENHA=x\n' > "$OC/web.env"; chmod 600 "$OC/web.env"
printf '{"a":1}\n' > "$OC/service.json"; chmod 640 "$OC/service.json"
printf 'MINHA-NOTA\n' > "$OC/AGENTS.md"
web_antes=$(stat -c '%a %s' "$OC/web.env"; cat "$OC/web.env")
svc_antes=$(stat -c '%a %s' "$OC/service.json"; cat "$OC/service.json")

roda() { HOME=$H bash "$REPO/scripts/secao.sh"; }
roda; afirma_rc $? 0 "secao roda"
roda; afirma_rc $? 0 "secao roda de novo"

conta() { grep -c -- "$2" "$1" || true; }
for f in "$OC/AGENTS.md" "$H/.codex/AGENTS.md"; do
  n=${f#"$H"/}
  [[ $(conta "$f" '^# >>> instrucoes do agente (29-skills.sh)') == 1 ]] && ok "$n: um bloco de instrucoes" || falha "$n: bloco de instrucoes"
  [[ $(conta "$f" '^# >>> modos padrao (29-skills.sh)') == 1 ]] && ok "$n: um bloco de modos" || falha "$n: bloco de modos"
  [[ $(conta "$f" 'REGRA-GLOBAL-FALSA') == 1 ]] && ok "$n: regras dentro, sem duplicar" || falha "$n: regras"
done
grep -q 'COMPLEMENTO-CLAUDE-FALSO' "$OC/AGENTS.md" && falha "OpenCode nao recebe o complemento do Claude" || ok "OpenCode sem o complemento do Claude"
[[ $(conta "$OC/AGENTS.md" 'MINHA-NOTA') == 1 ]] && ok "texto do usuario preservado" || falha "texto do usuario"
[[ $(stat -c '%a %s' "$OC/web.env"; cat "$OC/web.env") == "$web_antes" ]] && ok "web.env intacto" || falha "web.env mudou"
[[ $(stat -c '%a %s' "$OC/service.json"; cat "$OC/service.json") == "$svc_antes" ]] && ok "service.json intacto" || falha "service.json mudou"
[[ $(stat -c '%a' "$OC") == 700 ]] && ok "diretorio segue 0700" || falha "modo do diretorio"
fim
