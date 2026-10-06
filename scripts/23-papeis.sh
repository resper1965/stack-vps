#!/usr/bin/env bash
# Preenche Agente principal/revisor no STATE.md de cada repo do escopo.
# Decisao do Ricardo em 30/09/2026: Claude Code principal, Codex revisor, em todos.
# So troca campo que esta A DEFINIR; decisao ja escrita fica. Roda como agente.
# Uso: 23-papeis.sh [--push]   (sem --push so commita; nunca toca em main/master)
set -uo pipefail
ESCOPO=/srv/dev/state/escopo-auditoria.tsv
PRINCIPAL='Claude Code'; REVISOR='Codex'
NOVA="chore/papeis-$(date +%Y-%m-%d)"
PUSH=; [[ ${1:-} == --push ]] && { PUSH=1; set -a; . /srv/dev/secrets/agente.env; set +a; }
feitos=0; ja=0; pulados=0; enviados=0

while IFS=$'\t' read -r dono repo arvore dir; do
  [[ $dono == dono ]] && continue
  d="/srv/dev/repos/$arvore/$dir"; f="$d/STATE.md"
  [[ -f $f ]] || { pulados=$((pulados+1)); continue; }
  grep -qE '^\*\*Agente (principal|revisor):\*\* A DEFINIR' "$f" || { ja=$((ja+1)); continue; }

  # commita na branch chore/ em que o repo esta; em main/master abre branch nova
  br=$(git -C "$d" branch --show-current)
  case $br in
    chore/*) ;;
    main|master)
      [[ -z $(git -C "$d" status --porcelain) ]] || { echo "PULADO (alteracao pendente em $br): $dono/$repo"; pulados=$((pulados+1)); continue; }
      git -C "$d" switch -q -c "$NOVA" 2>/dev/null || git -C "$d" switch -q "$NOVA"; br=$NOVA;;
    *) echo "PULADO (branch de trabalho $br): $dono/$repo"; pulados=$((pulados+1)); continue;;
  esac

  # se um dos papeis ja estava decidido, o outro fica com o agente oposto: revisao independente
  p=$PRINCIPAL; r=$REVISOR
  atual_p=$(grep -m1 '^\*\*Agente principal:\*\*' "$f" | tr 'A-Z' 'a-z')
  atual_r=$(grep -m1 '^\*\*Agente revisor:\*\*' "$f" | tr 'A-Z' 'a-z')
  [[ $atual_p == *codex* ]] && r='Claude Code'
  [[ $atual_r == *claude* ]] && p='Codex'
  sed -i -e "s/^\*\*Agente principal:\*\* A DEFINIR$/**Agente principal:** $p/" \
         -e "s/^\*\*Agente revisor:\*\* A DEFINIR$/**Agente revisor:** $r/" "$f"
  git -C "$d" add STATE.md
  git -C "$d" -c user.name='Ricardo Esper' -c user.email='resper@bekaa.eu' \
    commit -qm 'docs: define agente principal e revisor no STATE.md' && feitos=$((feitos+1))

  if [[ -n $PUSH ]]; then
    git -C "$d" push -q "https://x-access-token:${GITHUB_TOKEN}@github.com/$dono/$repo.git" "$br" 2>/dev/null \
      && enviados=$((enviados+1)) || echo "FALHOU push: $dono/$repo ($br)"
  fi
done < "$ESCOPO"

echo "preenchidos: $feitos | ja definidos: $ja | pulados: $pulados${PUSH:+ | enviados: $enviados}"
