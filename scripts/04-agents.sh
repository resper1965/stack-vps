#!/usr/bin/env bash
# Claude Code + Codex no usuario dev, com marketplaces, plugins, MCP e skills proprias.
# Roda COMO dev (nao como root). Idempotente.
set -euo pipefail
[[ $(id -un) == dev ]] || { echo "rode como dev"; exit 1; }
export PATH="$HOME/.local/bin:$HOME/.local/share/mise/shims:$PATH"

# npm 11 bloqueia postinstall por padrao; o claude-code precisa do dele
npm i -g --allow-scripts=@anthropic-ai/claude-code @anthropic-ai/claude-code @openai/codex >/dev/null
mise reshim

MPS=(obra/superpowers-marketplace DietrichGebert/ponytail Sushegaad/Claude-Skills-Governance-Risk-and-Compliance)
PLUGINS=(superpowers@superpowers-marketplace ponytail@ponytail
         lgpd@grc-skills iso27001@grc-skills iso27701@grc-skills iso42001@grc-skills
         nist-csf@grc-skills cis-controls@grc-skills soc2@grc-skills pci-compliance@grc-skills
         dora@grc-skills nis2@grc-skills eu-ai-act@grc-skills)

for mp in "${MPS[@]}" ComposioHQ/composio-plugin-cc; do claude plugin marketplace add "$mp" >/dev/null 2>&1 || true; done
for p in "${PLUGINS[@]}" composio@composio; do claude plugin install "$p" >/dev/null 2>&1 || true; done
for mp in "${MPS[@]}"; do codex plugin marketplace add "$mp" >/dev/null 2>&1 || true; done
for p in "${PLUGINS[@]}"; do codex plugin add "$p" >/dev/null 2>&1 || true; done

# o endpoint SSE da Cloudflare responde 410; o transporte atual e HTTP streamable
claude mcp add --scope user --transport http cloudflare-docs https://docs.mcp.cloudflare.com/mcp >/dev/null 2>&1 || true
codex mcp add cloudflare-docs -- npx -y mcp-remote https://docs.mcp.cloudflare.com/mcp >/dev/null 2>&1 || true

# skills proprias: um clone, dois agentes.
# Claude le por symlink; Codex nao tem diretorio de skills, so plugin — dai o marketplace local.
D=/srv/dev/repos/infra/claude-skills
[[ -d $D/.git ]] || { set -a; . /srv/dev/secrets/.env; set +a
  git clone -q "https://x-access-token:${GITHUB_TOKEN}@github.com/resper1965/claude-skills.git" "$D"
  git -C "$D" remote set-url origin https://github.com/resper1965/claude-skills.git; }
mkdir -p ~/.claude/skills
for s in "$D"/skills/*/; do ln -sfn "$s" ~/.claude/skills/"$(basename "$s")"; done
codex plugin marketplace add "$D" >/dev/null 2>&1 || true
codex plugin add ness-skills@ness-skills >/dev/null 2>&1 || true

# CLAUDE.md §2: escrita em /srv/dev/state (pareceres, inventario). Sessao aberta num repo
# so escreve no proprio repo; sem isto o revisor nao grava em state/reviews.
C=~/.claude/settings.json; [[ -f $C ]] || echo '{}' > "$C"
jq '.permissions.additionalDirectories = ((.permissions.additionalDirectories // []) + ["/srv/dev/state"] | unique)' "$C" > "$C.tmp" && mv "$C.tmp" "$C"
X=~/.codex/config.toml; mkdir -p ~/.codex; touch "$X"
if ! grep -q '^\[sandbox_workspace_write\]' "$X"; then
  printf '\n[sandbox_workspace_write]\nwritable_roots = ["/srv/dev/state"]\n' >> "$X"
elif ! grep -q '"/srv/dev/state"' "$X"; then
  echo "AVISO: $X ja tem [sandbox_workspace_write]; inclua /srv/dev/state em writable_roots a mao"
fi

# superpowers e obrigatorio nos dois agentes: os installs acima engolem erro, aqui nao
falta=()
claude plugin list 2>/dev/null | grep -A3 'superpowers@superpowers-marketplace' | grep -q enabled || falta+=(claude)
codex plugin list 2>/dev/null | grep -qE '^superpowers@superpowers-marketplace +installed, enabled' || falta+=(codex)
(( ${#falta[@]} == 0 )) || { echo "ERRO: superpowers nao ficou ativo em: ${falta[*]}"; exit 1; }

echo "claude: $(claude --version) | plugins: $(claude plugin list 2>/dev/null | grep -c '❯')"
echo "codex:  $(codex --version)"
echo "login interativo (claude / codex) e o MCP do Composio ficam por sua conta."
