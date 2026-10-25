#!/usr/bin/env bash
# Claude Code e Codex com as assinaturas pelo 9router, OPT-IN: claude-9r e codex-9r. `claude` e `codex` seguem com login proprio.
# Roda COMO agente, depois do 04-agents.sh e do 41-9router.sh. Idempotente. Nao instala os CLIs, nao le nem imprime a chave.
# Uso: sudo -u agente -H bash -c 'cd ~ && /opt/stack-vps/scripts/44-clis-via-9router.sh'
# Modelo do Codex: NINE_ROUTER_CODEX_MODEL no momento da instalacao (padrao cx/gpt-5) e, a cada chamada, no ambiente do codex-9r.
# Se o Codex mudar o formato de provedor/perfil, conferir com `codex -p 9router --help` na VPS (padrao do 24-modelos.sh).
set -euo pipefail
cd /
[[ $(id -un) == agente || ${STACK_TESTE:-} == 1 ]] || { echo "rode como agente"; exit 1; }
BIN=$HOME/.local/bin
X=$HOME/.codex/config.toml
MODELO=${NINE_ROUTER_CODEX_MODEL:-cx/gpt-5}
[[ $MODELO =~ ^[A-Za-z0-9._/:-]+$ ]] || { echo "NINE_ROUTER_CODEX_MODEL com caracteres invalidos"; exit 1; }

# trava antes de escrever qualquer coisa: provedor padrao no config.toml tiraria todo codex da assinatura
if [[ -f $X ]] && grep -qE '^model_provider *=' "$X"; then
  echo "ERRO: ~/.codex/config.toml tem model_provider no topo; remova para manter o login proprio como padrao"; exit 1
fi

# leitura da chave nos dois wrappers: sem source/eval, so arquivo comum, do usuario, 0600
PRELUDIO=$(cat <<'EOF'
set -euo pipefail
f=$HOME/.config/9router/client.env
[[ -f $f && ! -L $f ]] || { echo "~/.config/9router/client.env deve ser arquivo comum, nao link" >&2; exit 1; }
[[ $(stat -c %U "$f") == "$(id -un)" ]] || { echo "~/.config/9router/client.env deve pertencer ao usuario atual" >&2; exit 1; }
[[ $(stat -c %a "$f") == 600 ]] || { echo "~/.config/9router/client.env deve ter modo 0600" >&2; exit 1; }
k=$(grep -m1 '^NINE_ROUTER_API_KEY=' "$f" | cut -d= -f2- | tr -d '\r') || true
[[ -n $k ]] || { echo "sem NINE_ROUTER_API_KEY= em ~/.config/9router/client.env" >&2; exit 1; }
EOF
)

# grava o wrapper (stdin) de forma atomica; so sobrescreve o que tem o marcador na 2a linha
grava() {
  local d t; mkdir -p "$BIN"; d=$(readlink -f "$BIN/$1")
  if [[ -e $d ]] && [[ $(sed -n 2p "$d") != '# stack-vps' ]]; then
    echo "AVISO: $d e do dono (sem o marcador # stack-vps na 2a linha); $1 nao instalado"; cat >/dev/null; return
  fi
  t=$(mktemp "$d.XXXXXX"); cat > "$t"; chmod 755 "$t"; mv "$t" "$d"
}

{ printf '#!/usr/bin/env bash\n# stack-vps\n# claude com a assinatura pelo 9router (opt-in); gerado por scripts/44-clis-via-9router.sh\n%s\n' "$PRELUDIO"
  cat <<'EOF'
export ANTHROPIC_BASE_URL=http://127.0.0.1:20128 ANTHROPIC_AUTH_TOKEN=$k
unset ANTHROPIC_API_KEY
[[ -z ${NINE_ROUTER_CLAUDE_MODEL:-} ]] || export ANTHROPIC_MODEL=$NINE_ROUTER_CLAUDE_MODEL
export CLAUDE_CONFIG_DIR=$HOME/.claude-9router  # login e historico separados do claude padrao
exec claude "$@"
EOF
} | grava claude-9r

{ printf '#!/usr/bin/env bash\n# stack-vps\n# codex com a assinatura pelo 9router (opt-in); gerado por scripts/44-clis-via-9router.sh\n%s\n' "$PRELUDIO"
  cat <<'EOF'
export NINE_ROUTER_API_KEY=$k
m=()
[[ -z ${NINE_ROUTER_CODEX_MODEL:-} ]] || m=(-m "$NINE_ROUTER_CODEX_MODEL")
exec codex -p 9router "${m[@]}" "$@"
EOF
} | grava codex-9r

# Codex: provedor declarado no config.toml (sem model_provider no topo), perfil em arquivo a parte (como o 24-modelos.sh)
mkdir -p "$HOME/.codex"; touch "$X"
grep -q '^\[model_providers\.9router\]' "$X" || cat >> "$X" <<'EOF'

[model_providers.9router]
name = "9router"
base_url = "http://127.0.0.1:20128/v1"
wire_api = "responses"
env_key = "NINE_ROUTER_API_KEY"
EOF
p=$(mktemp "$HOME/.codex/9router.config.toml.XXXXXX")
printf 'model_provider = "9router"\nmodel = "%s"\n' "$MODELO" > "$p"; chmod 600 "$p"; mv "$p" "$HOME/.codex/9router.config.toml"

echo "claude       -> login proprio (padrao); claude-9r -> assinatura pelo 9router"
echo "codex        -> login proprio (padrao); codex-9r  -> assinatura pelo 9router (modelo $MODELO)"
