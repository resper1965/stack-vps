#!/usr/bin/env bash
# shellcheck source=tests/lib.sh
. "$(dirname "$0")/lib.sh"
S=$RAIZ_REPO/scripts/41-9router.sh
SENHA=senha-bem-longa-xyz-123
JWT=jwt-de-teste-abc
echo "41-9router (ambiente validado antes de instalar ou subir qualquer coisa)"

prepara() {
  novo_tmp; stub systemctl; stub npm
  export HOME=$T/home NR_PREFIX=$T/prefix NR_UNIT_DIR=$T/unit NR_NPM=$STUBS/npm
  mkdir -p "$HOME/.config/9router"
  ENV=$HOME/.config/9router/9router.env
}
# escreve o ambiente (0600) com os valores dados; senha e JWT opcionais
env_com() { # senha jwt
  : > "$ENV"
  [[ -n $1 ]] && echo "INITIAL_PASSWORD=$1" >> "$ENV"
  [[ -n $2 ]] && echo "JWT_SECRET=$2" >> "$ENV"
  chmod 600 "$ENV"
}
roda() { bash "$S" > "$T/saida" 2>&1; RC=$?; }
nada() {
  nega_log systemctl "$1: systemctl nao chamado"; nega_log npm "$1: npm nao chamado"
  [[ ! -e $NR_UNIT_DIR/9router.service ]]; afirma $? "$1: unidade nao instalada"
}

prepara; roda; afirma_rc $RC 1 "sem arquivo de ambiente"; nada "sem ambiente"
prepara; env_com "$SENHA" "$JWT"; chmod 644 "$ENV"; roda; afirma_rc $RC 1 "modo 0644"; nada "modo 0644"
# o minimo de 16 e o unico criterio: 123456 cai nele; fronteira 15 recusa, 16 aceita
for fraca in 123456 123456789012345; do
  prepara; env_com "$fraca" "$JWT"; roda; afirma_rc $RC 1 "senha fraca (${#fraca} caracteres)"; nada "senha ${#fraca} caracteres"
  ! grep -qF "$fraca" "$T/saida"; afirma $? "senha ${#fraca} caracteres fora da saida"
done
prepara; env_com 1234567890123456 "$JWT"; roda; afirma_rc $RC 0 "senha com 16 caracteres"
for q in "'" '"'; do
  prepara; env_com "${q}${SENHA}${q}" "$JWT"; roda; afirma_rc $RC 1 "senha entre aspas ($q)"; nada "senha com aspas $q"
  ! grep -qF "$SENHA" "$T/saida"; afirma $? "senha com aspas fora da saida"
  prepara; env_com "$SENHA" "${q}${JWT}${q}"; roda; afirma_rc $RC 1 "JWT_SECRET entre aspas ($q)"; nada "JWT com aspas $q"
done
prepara; env_com "$SENHA" "$JWT"; printf 'OUTRA=1\r\n' >> "$ENV"; roda; afirma_rc $RC 1 "linha com CR"; nada "CR"
prepara; env_com "$SENHA" "$JWT"; mv "$ENV" "$T/real.env"; ln -s "$T/real.env" "$ENV"; roda; afirma_rc $RC 1 "ambiente symlink"; nada "symlink"
prepara; env_com "$SENHA" "$JWT"; stub stat 0 root; roda; afirma_rc $RC 1 "ambiente de outro dono"; nada "outro dono"
prepara; env_com "$SENHA" "$JWT"; roda_sem_unidade() { mkdir -p "$T/repo/scripts"; cp "$S" "$T/repo/scripts/"; bash "$T/repo/scripts/41-9router.sh" > "$T/saida" 2>&1; RC=$?; }
roda_sem_unidade; afirma_rc $RC 1 "sem 9router/9router.service no repo"; nada "sem unidade no repo"
prepara; env_com "" "$JWT"; roda; afirma_rc $RC 1 "sem INITIAL_PASSWORD"; nada "sem senha"
prepara; env_com "$SENHA" ""; roda; afirma_rc $RC 1 "sem JWT_SECRET"; nada "sem JWT"

prepara; env_com "$SENHA" "$JWT"; roda; afirma_rc $RC 0 "caso valido"
afirma_log "9router@0.5.104" "npm instala a versao fixa"
afirma_log "--prefix $NR_PREFIX" "npm com --prefix"
U=$NR_UNIT_DIR/9router.service
if [[ -f $U ]]; then ok "unidade instalada"; else falha "unidade instalada"; fi
grep -q 'HOSTNAME=127.0.0.1' "$U" && grep -q 'PORT=20128' "$U"; afirma $? "unidade escuta 127.0.0.1:20128"
! grep -q '0.0.0.0' "$U"; afirma $? "unidade sem 0.0.0.0"
afirma_log "--user enable --now 9router.service" "enable --now"
# o binario 9router e um lancador interativo: sem --host ele escuta 0.0.0.0 e sem --skip-update/TTY sai com 0
EX=$(grep '^ExecStart=' "$U")
for a in '--host 127.0.0.1' '--port 20128' '--no-browser' '--skip-update'; do
  grep -qF -- " $a" <<<"$EX"; afirma $? "ExecStart com $a"
done
grep -q '^ExecStart=%h/.local/bin/9router ' "$U"; afirma $? "ExecStart no 9router de ~/.local/bin"
grep -q '^Environment=PATH=%h/.local/bin:%h/.local/share/mise/shims:' "$U"; afirma $? "PATH da unidade com os shims do mise (shebang env node)"
if [[ $(stat -c %a "$HOME/.9router") == 700 ]]; then ok "DATA_DIR 0700"; else falha "DATA_DIR 0700"; fi
! grep -qF -e "$SENHA" -e "$JWT" "$T/saida" "$STUB_LOG"; afirma $? "segredos fora da saida e do log"
afirma_log "--user try-restart 9router.service" "try-restart para pegar unidade ou ambiente novos"
grep -q '^UMask=0077' "$U"; afirma $? "unidade com UMask=0077"
SUM=$(cat "$U"); roda; afirma_rc $RC 0 "segunda execucao"
if [[ $SUM == "$(cat "$U")" ]]; then ok "idempotente"; else falha "idempotente"; fi

# npm que de fato instala (cria package.json): com a versao ja instalada, o npm nao e chamado de novo
prepara; env_com "$SENHA" "$JWT"
cat > "$STUBS/npm" <<'EOS'
#!/usr/bin/env bash
echo "npm $*" >> "$STUB_LOG"
mkdir -p "$NR_PREFIX/lib/node_modules/9router"
printf '{\n  "name": "9router",\n  "version": "0.5.104"\n}\n' > "$NR_PREFIX/lib/node_modules/9router/package.json"
EOS
chmod +x "$STUBS/npm"
roda; afirma_rc $RC 0 "primeira execucao instala"; afirma_log "npm install" "npm chamado na primeira vez"
: > "$STUB_LOG"; roda; afirma_rc $RC 0 "versao ja instalada"; nega_log "npm" "versao ja instalada: npm nao chamado"
printf '{"version": "0.5.1"}\n' > "$NR_PREFIX/lib/node_modules/9router/package.json"
roda; afirma_log "9router@0.5.104" "versao diferente: npm reinstala"

# DATA_DIR pre-existente e aberto vira 0700
prepara; env_com "$SENHA" "$JWT"; mkdir -p "$HOME/.9router"; chmod 755 "$HOME/.9router"
roda; afirma_rc $RC 0 ".9router pre-existente"
if [[ $(stat -c %a "$HOME/.9router") == 700 ]]; then ok ".9router 0755 virou 0700"; else falha ".9router 0755 virou 0700"; fi

# nao-agente sem STACK_TESTE recusa (e ignora os overrides)
prepara; env_com "$SENHA" "$JWT"
STACK_TESTE='' bash "$S" > "$T/saida" 2>&1; afirma_rc $? 1 "nao-agente sem STACK_TESTE"
fim
