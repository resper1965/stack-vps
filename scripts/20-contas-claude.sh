#!/usr/bin/env bash
# Duas contas Claude: bekaa (padrao, ~/.claude) e ionic (~/.claude-ionic).
# Decisao do Ricardo em 30/09/2026: vertical ionic usa a conta ionic; todas as outras, a bekaa.
# `claude` dentro de projeto da vertical ionic (pelos atalhos do 18-verticais.sh) usa a conta
# ionic sozinho. Forcar: claude-bekaa / claude-ionic. CLAUDE_CONFIG_DIR ja definido e respeitado.
# Plugins, skills e settings sao os mesmos nas duas: o ~/.claude-ionic aponta para o ~/.claude.
# So o CLI respeita CLAUDE_CONFIG_DIR; a extensao do VS Code usa sempre a conta padrao.
# Roda COMO dev, depois do 04-agents.sh. Idempotente.
set -euo pipefail
[[ $(id -un) == dev ]] || { echo "rode como dev"; exit 1; }
export PATH="$HOME/.local/bin:$HOME/.local/share/mise/shims:$PATH"
B=~/.claude; I=~/.claude-ionic
mkdir -p "$B" "$I"; chmod 700 "$I"

# curadoria unica: login, historico e .claude.json ficam separados; o resto e link
for x in settings.json CLAUDE.md skills plugins agents commands hooks; do
  [[ -e $B/$x ]] || continue
  [[ -L $I/$x ]] && continue
  [[ -e $I/$x ]] && { echo "AVISO: $I/$x existe e nao e link; deixei como esta"; continue; }
  ln -s "$B/$x" "$I/$x"
done
# MCP de usuario mora no .claude.json de cada conta
CLAUDE_CONFIG_DIR=$I claude mcp add --scope user --transport http cloudflare-docs https://docs.mcp.cloudflare.com/mcp >/dev/null 2>&1 || true

if ! grep -q '^# >>> contas-claude' ~/.bashrc; then cat >> ~/.bashrc <<'EOF'
# >>> contas-claude (20-contas-claude.sh)
_claude_ionic() {
  local f l; f=$(pwd -P)
  [[ $PWD == /srv/dev/verticais/ionic/* ]] && return 0
  for l in /srv/dev/verticais/ionic/*/*; do
    [[ -L $l ]] || continue; l=$(readlink -f "$l")
    [[ $f == "$l" || $f == "$l"/* ]] && return 0
  done
  return 1
}
claude() {
  if [[ -z ${CLAUDE_CONFIG_DIR:-} ]] && _claude_ionic; then
    CLAUDE_CONFIG_DIR=$HOME/.claude-ionic command claude "$@"
  else command claude "$@"; fi
}
claude-bekaa() { env -u CLAUDE_CONFIG_DIR claude "$@"; }
claude-ionic() { CLAUDE_CONFIG_DIR=$HOME/.claude-ionic command claude "$@"; }
# <<< contas-claude
EOF
fi

CLAUDE_CONFIG_DIR=$I claude plugin list 2>/dev/null | grep -A3 'superpowers@superpowers-marketplace' | grep -q enabled \
  || { echo "ERRO: superpowers nao aparece na conta ionic; confira os links em $I"; exit 1; }

echo "conta bekaa: $B (padrao) | conta ionic: $I"
echo "login, uma vez em cada: claude-bekaa  -> /login  |  claude-ionic  -> /login"
