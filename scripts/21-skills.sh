#!/usr/bin/env bash
# Skills de plataforma (Cloudflare, Supabase, Vercel, GitHub) para Claude Code, Codex e
# Antigravity CLI (agy), e ponytail + caveman ligados por padrao nos tres.
# Decisao do Ricardo em 30/09/2026. Roda COMO dev, depois do 04 e do 20. Idempotente.
#
#   Claude    ~/.claude/skills (a conta ionic enxerga pelo link do 20); ponytail e caveman
#             sao plugins com hooks, ligam sozinhos.
#   Codex     le ~/.agents/skills; os dois modos entram pelo ~/.codex/AGENTS.md, porque os
#             hooks de plugin no Codex so rodam depois de aprovados a mao em /hooks.
#   agy       raiz global ~/.gemini/config: skills em skills/, modos em rules/ (trigger always_on);
#             ponytail ja vem como plugin do 04.
set -euo pipefail
[[ $(id -un) == dev ]] || { echo "rode como dev"; exit 1; }
export PATH="$HOME/.local/bin:$HOME/.local/share/mise/shims:$PATH" DO_NOT_TRACK=1
SK="npx -y skills@1.7.0"
AGENTES=(-a claude-code -a codex)
mkdir -p ~/.codex ~/.claude ~/.gemini/config/skills ~/.gemini/config/rules

add() { $SK add "$@" -g -y >/dev/null 2>&1 || { echo "ERRO: skills add $*"; exit 1; }; }
add cloudflare/skills          --skill '*' "${AGENTES[@]}"
add supabase/agent-skills      --skill '*' "${AGENTES[@]}"
add vercel-labs/agent-skills   --skill '*' "${AGENTES[@]}"
add github/awesome-copilot     --skill github-issues --skill github-release \
                               --skill github-actions-hardening --skill github-actions-efficiency "${AGENTES[@]}"
# caveman no Claude vem como plugin (abaixo); aqui so para quem nao tem plugin com hook
add JuliusBrussee/caveman      --skill '*' -a codex

# agy le a propria raiz global; o skills cli nao conhece esse caminho, entao link a link
for s in ~/.agents/skills/*/; do ln -sfn "${s%/}" ~/.gemini/config/skills/"$(basename "$s")"; done

# Claude: caveman como plugin (ponytail ja vem do 04)
claude plugin marketplace add JuliusBrussee/caveman >/dev/null 2>&1 || true
claude plugin install caveman@caveman >/dev/null 2>&1 || true

# modo padrao dos dois, lido pelos hooks do Claude
mkdir -p ~/.config/ponytail ~/.config/caveman
echo '{ "defaultMode": "full" }' > ~/.config/ponytail/config.json
echo '{ "defaultMode": "full" }' > ~/.config/caveman/config.json

# Codex e Antigravity: mesma instrucao, em bloco marcado que se reescreve a cada execucao
bloco() { cat <<'EOF'
# >>> modos padrao (21-skills.sh)
Ative desde a primeira resposta, sem esperar comando:
- ponytail (modo full): antes de escrever codigo, siga a skill `ponytail`.
- caveman (modo full): respostas curtas segundo a skill `caveman`, no idioma do usuario.
  Nao vale para relatorio, documento de cliente, parecer ou mensagem de commit: esses em prosa completa.
Desligar so nesta sessao: "/ponytail off", "/caveman off".
# <<< modos padrao
EOF
}
for f in ~/.codex/AGENTS.md; do
  touch "$f"
  python3 - "$f" "$(bloco)" <<'PY'
import re,sys
f,b=sys.argv[1],sys.argv[2]
t=open(f).read()
t=re.sub(r'# >>> modos padrao \(21-skills\.sh\).*?# <<< modos padrao\n?','',t,flags=re.S).rstrip('\n')
open(f,'w').write((t+'\n\n' if t else '')+b+'\n')
PY
done
{ printf -- '---\ntrigger: always_on\n---\n'; bloco; } > ~/.gemini/config/rules/modos-padrao.md

# conferencia: nada do que foi pedido pode ter ficado de fora
falta=()
for s in cloudflare supabase deploy-to-vercel github-issues github-actions-hardening caveman; do
  [[ -e ~/.agents/skills/$s/SKILL.md ]] || falta+=("skill:$s")
done
for s in cloudflare supabase github-issues; do [[ -e ~/.claude/skills/$s/SKILL.md ]] || falta+=("claude:$s"); done
for p in ponytail@ponytail caveman@caveman; do
  claude plugin list 2>/dev/null | grep -A3 "$p" | grep -q enabled || falta+=("plugin:$p")
done
for s in cloudflare github-issues caveman; do [[ -e ~/.gemini/config/skills/$s/SKILL.md ]] || falta+=("agy:$s"); done
agy plugin list 2>/dev/null | grep -q '"name": "ponytail"' || falta+=("agy-plugin:ponytail")
(( ${#falta[@]} == 0 )) || { echo "ERRO: faltou ${falta[*]}"; exit 1; }
echo "skills em ~/.agents/skills: $(ls ~/.agents/skills | wc -l) | ponytail e caveman: full por padrao"
