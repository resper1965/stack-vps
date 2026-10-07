#!/usr/bin/env bash
# Skills de plataforma (Cloudflare, Supabase, Vercel, GitHub) para Claude Code, Codex e
# Antigravity CLI (agy), e ponytail ligado por padrao nos tres.
# Decisao do Ricardo em 30/09/2026. Roda COMO agente, depois do 04 e do 28. Idempotente.
#
#   Claude    ~/.claude/skills (a conta ionic enxerga pelo link do 20); ponytail e plugin com
#             hook (do 04), liga sozinho.
#   Codex     le ~/.agents/skills; o ponytail entra pelo ~/.codex/AGENTS.md, porque os
#             hooks de plugin no Codex so rodam depois de aprovados a mao em /hooks.
#   agy       raiz global ~/.gemini/config: skills em skills/, modos em rules/ (trigger always_on);
#             ponytail ja vem como plugin do 04.
set -euo pipefail
[[ $(id -un) == agente ]] || { echo "rode como agente: sudo -u agente -H $0"; exit 1; }
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

# agy le a propria raiz global; o skills cli nao conhece esse caminho, entao link a link
for s in ~/.agents/skills/*/; do ln -sfn "${s%/}" ~/.gemini/config/skills/"$(basename "$s")"; done

# modo padrao, lido pelo hook do Claude
mkdir -p ~/.config/ponytail
echo '{ "defaultMode": "full" }' > ~/.config/ponytail/config.json

# Codex e Antigravity: mesma instrucao, em bloco marcado que se reescreve a cada execucao
bloco() { cat <<'EOF'
# >>> modos padrao (29-skills.sh)
Ative desde a primeira resposta, sem esperar comando:
- ponytail (modo full): antes de escrever codigo, siga a skill `ponytail`.
Desligar so nesta sessao: "/ponytail off".
# <<< modos padrao
EOF
}
# instrucoes globais (ambiente, jeito de responder, STATE.md): docs/agente-instrucoes.md
INSTR=$(cd "$(dirname "$0")/.." && pwd)/docs/agente-instrucoes.md
instrucoes() { echo '# >>> instrucoes do agente (29-skills.sh)'; cat "$INSTR"; echo '# <<< instrucoes do agente'; }
# grava_bloco ARQUIVO MARCA CONTEUDO: troca o bloco marcado e preserva o resto do arquivo
grava_bloco() {
  touch "$1"
  python3 - "$@" <<'PY'
import re,sys
f,m,b=sys.argv[1:4]
t=open(f,encoding='utf-8').read()
ini,fim='# >>> '+m+' (29-skills.sh)','# <<< '+m
t=re.sub(re.escape(ini)+'.*?'+re.escape(fim)+'\n?','',t,flags=re.S).rstrip('\n')
open(f,'w',encoding='utf-8').write((t+'\n\n' if t else '')+b.rstrip('\n')+'\n')
PY
}
grava_bloco ~/.codex/AGENTS.md "modos padrao" "$(bloco)"
for f in ~/.codex/AGENTS.md ~/.claude/CLAUDE.md; do grava_bloco "$f" "instrucoes do agente" "$(instrucoes)"; done
# a conta ionic le o mesmo CLAUDE.md (o 28 so liga o que ja existia quando rodou)
[[ -e ~/.claude-ionic/CLAUDE.md ]] || ln -s ~/.claude/CLAUDE.md ~/.claude-ionic/CLAUDE.md
{ printf -- '---\ntrigger: always_on\n---\n'; bloco; } > ~/.gemini/config/rules/modos-padrao.md
{ printf -- '---\ntrigger: always_on\n---\n'; cat "$INSTR"; } > ~/.gemini/config/rules/instrucoes.md

# conferencia: nada do que foi pedido pode ter ficado de fora
falta=()
for s in cloudflare supabase deploy-to-vercel github-issues github-actions-hardening; do
  [[ -e ~/.agents/skills/$s/SKILL.md ]] || falta+=("skill:$s")
done
for s in cloudflare supabase github-issues; do [[ -e ~/.claude/skills/$s/SKILL.md ]] || falta+=("claude:$s"); done
# shellcheck disable=SC2043  # idem: outros plugins obrigatorios entram aqui
for p in ponytail@ponytail; do
  claude plugin list 2>/dev/null | grep -A3 "$p" | grep -q enabled || falta+=("plugin:$p")
done
for f in ~/.claude/CLAUDE.md ~/.codex/AGENTS.md; do grep -q "^# >>> instrucoes do agente" "$f" || falta+=("instrucoes:$f"); done
for s in cloudflare github-issues; do [[ -e ~/.gemini/config/skills/$s/SKILL.md ]] || falta+=("agy:$s"); done
agy plugin list 2>/dev/null | grep -q '"name": "ponytail"' || falta+=("agy-plugin:ponytail")
(( ${#falta[@]} == 0 )) || { echo "ERRO: faltou ${falta[*]}"; exit 1; }
echo "skills em ~/.agents/skills: $(ls ~/.agents/skills | wc -l) | ponytail: full por padrao"
