#!/usr/bin/env bash
# Claude Code e Codex com as assinaturas pelo 9router, OPT-IN: claude-9r e codex-9r. `claude` e `codex` seguem com login proprio.
# Roda COMO agente, depois do 04-agents.sh e do 41-9router.sh. Idempotente. Nao instala os CLIs, nao le nem imprime a chave.
# Uso: sudo -u agente -H bash -c 'cd ~ && /opt/stack-vps/scripts/44-clis-via-9router.sh'
# Modelo do Codex: so vai ao perfil se NINE_ROUTER_CODEX_MODEL vier explicito (IDs: passo 1.11a do runbook); no codex-9r vale tambem a cada chamada.
# Se o Codex mudar o formato de provedor/perfil, conferir com `codex -p 9router --help` na VPS (padrao do 24-modelos.sh).
set -euo pipefail
cd /
[[ $(id -un) == agente || ${STACK_TESTE:-} == 1 ]] || { echo "rode como agente"; exit 1; }
BIN=$HOME/.local/bin
X=$HOME/.codex/config.toml
P=$HOME/.codex/9router.config.toml
MODELO=${NINE_ROUTER_CODEX_MODEL:-}
[[ -z $MODELO || $MODELO =~ ^[A-Za-z0-9._/:-]+$ ]] || { echo "NINE_ROUTER_CODEX_MODEL com caracteres invalidos"; exit 1; }
# base_url do bloco [model_providers.9router] (valor cru, com aspas); o codex-9r repete esta mesma conferencia
AWK_BASE='/^\[/{b=($0=="[model_providers.9router]")} b&&/^base_url[ \t]*=/{sub(/^[^=]*=[ \t]*/,"");sub(/[ \t\r]+$/,"");print;exit}'

# travas antes de escrever qualquer coisa
if [[ -f $X ]]; then
  if grep -qE '^[[:space:]]*model_provider[[:space:]]*=' "$X"; then
    echo "ERRO: ~/.codex/config.toml tem model_provider no topo; remova para manter o login proprio como padrao"; exit 1
  fi
  u=$(awk "$AWK_BASE" "$X")
  if [[ -n $u && $u != '"http://127.0.0.1:20128/v1"' ]]; then
    echo "ERRO: [model_providers.9router] em ~/.codex/config.toml com base_url diferente de http://127.0.0.1:20128/v1; corrija a mao"; exit 1
  fi
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

# grava o wrapper (stdin) de forma atomica; recusa link; so sobrescreve o que tem o marcador na 2a linha
grava() {
  local d=$BIN/$1 t; mkdir -p "$BIN"
  if [[ -L $d ]]; then echo "AVISO: $d e link; $1 nao instalado"; cat >/dev/null; return; fi
  if [[ -e $d ]] && [[ $(sed -n 2p "$d") != '# stack-vps' ]]; then
    echo "AVISO: $d e do dono (sem o marcador # stack-vps na 2a linha); $1 nao instalado"; cat >/dev/null; return
  fi
  t=$(mktemp "$d.XXXXXX"); cat > "$t"; chmod 755 "$t"; mv "$t" "$d"
}

{ printf '#!/usr/bin/env bash\n# stack-vps\n# claude com a assinatura pelo 9router (opt-in); gerado por scripts/44-clis-via-9router.sh\n%s\n' "$PRELUDIO"
  cat <<'EOF'
# nada herdado do ambiente pode desviar a chamada para fora do 9router
unset ANTHROPIC_API_KEY ANTHROPIC_CUSTOM_HEADERS CLAUDE_CODE_USE_BEDROCK CLAUDE_CODE_USE_VERTEX \
  ANTHROPIC_BEDROCK_BASE_URL ANTHROPIC_VERTEX_BASE_URL ANTHROPIC_MODEL ANTHROPIC_SMALL_FAST_MODEL \
  ANTHROPIC_DEFAULT_OPUS_MODEL ANTHROPIC_DEFAULT_SONNET_MODEL ANTHROPIC_DEFAULT_HAIKU_MODEL \
  HTTP_PROXY http_proxy HTTPS_PROXY https_proxy ALL_PROXY all_proxy
export NO_PROXY=127.0.0.1,localhost no_proxy=127.0.0.1,localhost
export ANTHROPIC_BASE_URL=http://127.0.0.1:20128 ANTHROPIC_AUTH_TOKEN=$k
[[ -z ${NINE_ROUTER_CLAUDE_MODEL:-} ]] || export ANTHROPIC_MODEL=$NINE_ROUTER_CLAUDE_MODEL
[[ -z ${NINE_ROUTER_CLAUDE_SMALL_MODEL:-} ]] || export ANTHROPIC_SMALL_FAST_MODEL=$NINE_ROUTER_CLAUDE_SMALL_MODEL
export CLAUDE_CONFIG_DIR=$HOME/.claude-9router  # login e historico separados do claude padrao
exec claude "$@"
EOF
} | grava claude-9r

{ printf '#!/usr/bin/env bash\n# stack-vps\n# codex com a assinatura pelo 9router (opt-in); gerado por scripts/44-clis-via-9router.sh\n%s\n' "$PRELUDIO"
  printf "AWK_BASE='%s'\n" "$AWK_BASE"
  cat <<'EOF'
export CODEX_HOME=$HOME/.codex
# a chave so sai se o provedor 9router aponta para o proprio 9router
u=$(awk "$AWK_BASE" "$CODEX_HOME/config.toml" 2>/dev/null || true)
[[ $u == '"http://127.0.0.1:20128/v1"' ]] || { echo "base_url do [model_providers.9router] em ~/.codex/config.toml diferente de http://127.0.0.1:20128/v1; chave nao exportada" >&2; exit 1; }
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
if [[ -L $P ]] || { [[ -e $P ]] && ! head -n 3 "$P" | grep -qxF '# stack-vps'; }; then
  echo "AVISO: $P e do dono (sem o marcador # stack-vps) ou link; perfil nao gravado"
else
  t=$(mktemp "$P.XXXXXX")
  { printf '# stack-vps\nmodel_provider = "9router"\n'; [[ -z $MODELO ]] || printf 'model = "%s"\n' "$MODELO"; } > "$t"
  chmod 600 "$t"; mv "$t" "$P"
fi
[[ -n $MODELO ]] || echo "modelo nao definido: liste os IDs com o passo 1.11a do runbook e rode de novo com NINE_ROUTER_CODEX_MODEL"

echo "claude       -> login proprio (padrao); claude-9r -> assinatura pelo 9router"
echo "codex        -> login proprio (padrao); codex-9r  -> assinatura pelo 9router"
