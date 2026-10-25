#!/usr/bin/env bash
# shellcheck source=tests/lib.sh
. "$(dirname "$0")/lib.sh"
S=$RAIZ_REPO/scripts/44-clis-via-9router.sh
CHAVE=chave-sentinela-9r-xyz
echo "44-clis-via-9router (claude-9r e codex-9r opt-in)"

prepara() {
  novo_tmp; export HOME=$T/home; mkdir -p "$HOME/.config/9router"
  CL=$HOME/.config/9router/client.env; B=$HOME/.local/bin; CFG=$HOME/.codex/config.toml
  unset NINE_ROUTER_CODEX_MODEL NINE_ROUTER_CLAUDE_MODEL ANTHROPIC_API_KEY
  # stub de claude/codex: argv numa linha, variaveis de interesse em outro arquivo
  for c in claude codex; do
    cat > "$STUBS/$c" <<'EOS'
#!/usr/bin/env bash
echo "$(basename "$0") $*" >> "$STUB_LOG"
{ echo "BASE=${ANTHROPIC_BASE_URL:-}"; echo "TOKEN=${ANTHROPIC_AUTH_TOKEN:-}"; echo "MODEL=${ANTHROPIC_MODEL:-}"
  echo "CFGDIR=${CLAUDE_CONFIG_DIR:-}"; echo "APIKEY=${ANTHROPIC_API_KEY:-}"; echo "NRKEY=${NINE_ROUTER_API_KEY:-}"; } > "$STUB_ENV"
EOS
    chmod +x "$STUBS/$c"
  done
  export STUB_ENV=$T/stub.env
}
chave() { echo "NINE_ROUTER_API_KEY=$CHAVE" > "$CL"; chmod 600 "$CL"; }
roda() { bash "$S" > "$T/saida" 2>&1; RC=$?; }
nao() { local d=$1; shift; if "$@"; then falha "$d"; else ok "$d"; fi; }

prepara; chave; roda; afirma_rc $RC 0 "instala"
[[ -x $B/claude-9r && -x $B/codex-9r ]] && ok "wrappers criados e executaveis" || falha "wrappers criados e executaveis"
[[ $(stat -c %a "$B/claude-9r") == 755 && $(stat -c %a "$B/codex-9r") == 755 ]] && ok "modo 0755" || falha "modo 0755"
[[ $(sed -n 2p "$B/claude-9r") == '# stack-vps' && $(sed -n 2p "$B/codex-9r") == '# stack-vps' ]] && ok "marcador na 2a linha" || falha "marcador na 2a linha"
nao "chave fora dos wrappers e da saida" grep -qF "$CHAVE" "$B/claude-9r" "$B/codex-9r" "$T/saida"
grep -qx '\[model_providers.9router\]' "$CFG" && grep -qx 'wire_api = "responses"' "$CFG" && grep -qx 'base_url = "http://127.0.0.1:20128/v1"' "$CFG" && grep -qx 'env_key = "NINE_ROUTER_API_KEY"' "$CFG"; afirma $? "provedor 9router no config.toml"
nao "config.toml sem model_provider no topo" grep -qE '^model_provider' "$CFG"
P=$HOME/.codex/9router.config.toml
grep -qx 'model_provider = "9router"' "$P" && grep -qx 'model = "cx/gpt-5"' "$P"; afirma $? "perfil com modelo padrao cx/gpt-5"
nao "sem temporarios sobrando" compgen -G "$B/*.??????"
[[ ! -e $HOME/.claude ]] && ok "config do claude padrao intocado" || falha "config do claude padrao intocado"

# idempotencia
SUM=$(cat "$B/claude-9r" "$B/codex-9r" "$CFG" "$P"); roda; afirma_rc $RC 0 "segunda execucao"
if [[ $SUM == "$(cat "$B/claude-9r" "$B/codex-9r" "$CFG" "$P")" ]]; then ok "idempotente"; else falha "idempotente"; fi
[[ $(grep -c '^\[model_providers.9router\]' "$CFG") == 1 ]] && ok "provedor nao duplicado" || falha "provedor nao duplicado"

# modelo na instalacao
NINE_ROUTER_CODEX_MODEL=cx/gpt-5-codex roda; grep -qx 'model = "cx/gpt-5-codex"' "$P"; afirma $? "NINE_ROUTER_CODEX_MODEL vai para o perfil"
NINE_ROUTER_CODEX_MODEL='x"
model_provider = "y' roda; afirma_rc $RC 1 "modelo com caracteres invalidos: recusa"

# execucao com chave de sentinela
prepara; chave; roda
"$B/claude-9r" --foo bar; afirma_rc $? 0 "claude-9r roda"
afirma_log "claude --foo bar" "claude recebe os argumentos"
grep -qx 'BASE=http://127.0.0.1:20128' "$STUB_ENV" && grep -qx "TOKEN=$CHAVE" "$STUB_ENV" && grep -qx "CFGDIR=$HOME/.claude-9router" "$STUB_ENV" && grep -qx 'MODEL=' "$STUB_ENV"; afirma $? "claude-9r exporta base, token e config dir separado"
nao "chave fora do argv do claude" grep -qF "$CHAVE" "$STUB_LOG"
ANTHROPIC_API_KEY=outra NINE_ROUTER_CLAUDE_MODEL=cc/sonnet "$B/claude-9r"; grep -qx 'MODEL=cc/sonnet' "$STUB_ENV" && grep -qx 'APIKEY=' "$STUB_ENV"; afirma $? "ANTHROPIC_MODEL vem de NINE_ROUTER_CLAUDE_MODEL; ANTHROPIC_API_KEY limpa"
"$B/codex-9r" exec oi; afirma_rc $? 0 "codex-9r roda"
afirma_log "codex -p 9router exec oi" "codex recebe -p 9router e os argumentos"
grep -qx "NRKEY=$CHAVE" "$STUB_ENV"; afirma $? "codex-9r exporta NINE_ROUTER_API_KEY"
nao "chave fora do argv do codex" grep -qF "$CHAVE" "$STUB_LOG"
NINE_ROUTER_CODEX_MODEL=cx/gpt-5 "$B/codex-9r"; afirma_log "codex -p 9router -m cx/gpt-5" "NINE_ROUTER_CODEX_MODEL vira -m"

# client.env invalido: wrapper falha sem exec
recusa() { # $1 descricao
  : > "$STUB_LOG"
  for w in claude-9r codex-9r; do "$B/$w" > "$T/w.out" 2>&1; afirma_rc $? 1 "$1: $w falha"; done
  [[ ! -s $STUB_LOG ]] && ok "$1: sem exec" || falha "$1: sem exec"
  nao "$1: chave fora da saida" grep -qF "$CHAVE" "$T/w.out"
}
chmod 644 "$CL"; recusa "client.env 0644"
chmod 600 "$CL"; REAL_STAT=$(command -v stat)
printf '#!/usr/bin/env bash
[[ "$*" == *client.env* && "$*" == *%%U* ]] && { echo root; exit 0; }
exec %s "$@"
' "$REAL_STAT" > "$STUBS/stat"; chmod +x "$STUBS/stat"; recusa "client.env de outro dono"; rm "$STUBS/stat"
mv "$CL" "$T/real"; ln -s "$T/real" "$CL"; recusa "client.env link"
rm "$CL"; recusa "sem client.env"
echo "OUTRA=1" > "$CL"; chmod 600 "$CL"; recusa "client.env sem a chave"

# arquivo do dono sem marcador: intocado, com aviso; o outro wrapper segue
prepara; chave; mkdir -p "$B"; printf '#!/bin/sh\necho meu\n' > "$B/claude-9r"; chmod 755 "$B/claude-9r"
roda; afirma_rc $RC 0 "wrapper do dono: segue"
grep -q 'AVISO:.*claude-9r.*e do dono' "$T/saida"; afirma $? "aviso do arquivo do dono"
[[ $(cat "$B/claude-9r") == $'#!/bin/sh\necho meu' ]] && ok "claude-9r do dono intocado" || falha "claude-9r do dono intocado"
[[ $(sed -n 2p "$B/codex-9r") == '# stack-vps' ]] && ok "codex-9r instalado" || falha "codex-9r instalado"

# marcador existente: sobrescrito
printf '#!/usr/bin/env bash\n# stack-vps\nvelho\n' > "$B/codex-9r"; roda; nao "wrapper com marcador e atualizado" grep -q velho "$B/codex-9r"

# trava: model_provider no topo do config.toml
prepara; chave; mkdir -p "$HOME/.codex"; printf 'model_provider = "x"\n' > "$CFG"
roda; afirma_rc $RC 1 "model_provider no topo: recusa"
[[ ! -e $B/claude-9r && ! -e $B/codex-9r && ! -e $HOME/.codex/9router.config.toml ]] && ok "recusa antes de escrever" || falha "recusa antes de escrever"
[[ $(cat "$CFG") == 'model_provider = "x"' ]] && ok "config.toml intocado" || falha "config.toml intocado"
fim
