#!/usr/bin/env bash
# Modelos extras no Codex via OpenRouter, sem mexer no padrao (assinatura ChatGPT Pro).
# Roda COMO dev, depois do 04-agents.sh. Idempotente.
# Uso depois: codex -p openrouter [-m fornecedor/modelo]
# Chave: OPENROUTER_API_KEY em /srv/dev/secrets/.env, lida so na hora da chamada.
#
# Featherless fica de fora: o Codex so fala a Responses API e a Featherless so tem
# /v1/chat/completions (/v1/responses devolve 404, conferido em 30/09/2026).
set -euo pipefail
[[ $(id -un) == dev ]] || { echo "rode como dev"; exit 1; }
export PATH="$HOME/.local/bin:$HOME/.local/share/mise/shims:$PATH"
X=~/.codex/config.toml; mkdir -p ~/.codex; touch "$X"

# provedor fica declarado no config.toml (o unico lugar onde o Codex aceita provedor)...
grep -q '^\[model_providers\.openrouter\]' "$X" || cat >> "$X" <<'EOF'

[model_providers.openrouter]
name = "OpenRouter"
base_url = "https://openrouter.ai/api/v1"

[model_providers.openrouter.auth]
command = "sh"
args = ["-c", ". /srv/dev/secrets/.env && printf %s \"$OPENROUTER_API_KEY\""]
EOF

# ...mas so e usado por quem pede -p openrouter: o perfil e um arquivo a parte
cat > ~/.codex/openrouter.config.toml <<'EOF'
model_provider = "openrouter"
model = "openrouter/auto"
EOF

# trava: provedor padrao no config.toml tiraria todo codex da assinatura
grep -qE '^model_provider *=' "$X" && { echo "ERRO: $X tem model_provider no topo; remova para manter o ChatGPT Pro como padrao"; exit 1; }
grep -q '^OPENROUTER_API_KEY=' /srv/dev/secrets/.env 2>/dev/null \
  || echo "falta OPENROUTER_API_KEY=... em /srv/dev/secrets/.env"

echo "codex        -> assinatura ChatGPT Pro (padrao)"
echo "codex -p openrouter [-m fornecedor/modelo] -> OpenRouter, cobra por uso"
