#!/usr/bin/env bash
# Envia a branch de inventario de cada repo. NUNCA toca em main/master.
set -uo pipefail
ESCOPO=/srv/dev/state/escopo-auditoria.tsv
BRANCH="chore/inventario-$(date +%Y-%m-%d)"
set -a; . /srv/dev/secrets/.env; set +a
ok=0; falha=0; pulado=0
while IFS=$'\t' read -r dono repo arvore dir; do
  [[ $dono == dono ]] && continue
  d="/srv/dev/repos/$arvore/$dir"
  [[ -f $d/STATE.md ]] || { pulado=$((pulado+1)); continue; }
  atual=$(git -C "$d" rev-parse --abbrev-ref HEAD 2>/dev/null)
  [[ $atual == "$BRANCH" ]] || { echo "PULADO (branch errada: $atual): $dono/$repo"; pulado=$((pulado+1)); continue; }
  if git -C "$d" push -q "https://x-access-token:${GITHUB_TOKEN}@github.com/$dono/$repo.git" "$BRANCH" 2>/dev/null; then ok=$((ok+1))
  else echo "FALHOU: $dono/$repo"; falha=$((falha+1)); fi
done < "$ESCOPO"
echo "branches enviadas: $ok | falhas: $falha | pulados: $pulado"
