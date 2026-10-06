#!/usr/bin/env bash
# Gera STATE.md em cada repo do escopo, em branch propria, SEM push.
# Preenche pelo que da para inferir; o resto fica A CONFIRMAR / A DEFINIR.
set -uo pipefail
ESCOPO=/srv/dev/state/escopo-auditoria.tsv
BRANCH="chore/inventario-$(date +%Y-%m-%d)"
feitos=0; pulados=0

while IFS=$'\t' read -r dono repo arvore dir; do
  [[ $dono == dono ]] && continue
  d="/srv/dev/repos/$arvore/$dir"
  [[ -d $d/.git ]] || { pulados=$((pulados+1)); continue; }
  git -C "$d" log -1 >/dev/null 2>&1 || { pulados=$((pulados+1)); continue; }   # repo vazio

  trilha=geral
  [[ $dono == bekaa-trusted-advisors || ${repo,,} == *bekaa* ]] && trilha=bekaa

  ult=$(git -C "$d" log -1 --format='%cs — %s' 2>/dev/null | cut -c1-120)
  stack=$(grep -m1 "^| $dir |" /srv/dev/state/inventario*.md 2>/dev/null | cut -d'|' -f4 | xargs)
  [[ -z $stack ]] && stack='A CONFIRMAR'

  # como rodar: scripts do package.json, compose ou Makefile
  rodar='A CONFIRMAR'
  pkg=$(find "$d" -maxdepth 2 -name package.json -not -path '*/node_modules/*' | head -1)
  if [[ -n $pkg ]]; then
    sc=$(python3 -c "import json,sys;d=json.load(open('$pkg'));print(', '.join(('npm run '+k) for k in list(d.get('scripts',{}))[:4]))" 2>/dev/null)
    [[ -n $sc ]] && rodar="$sc"
  fi
  find "$d" -maxdepth 2 -name 'docker-compose*.yml' | grep -q . && rodar="$rodar${rodar:+ | }docker compose up"

  # dependencias externas: servicos do compose + chaves de .env.example
  deps=$(find "$d" -maxdepth 2 -name '.env.example' -o -maxdepth 2 -name '.env.sample' | head -1)
  if [[ -n $deps ]]; then deps=$(grep -oE '^[A-Z0-9_]+' "$deps" 2>/dev/null | head -8 | tr '\n' ' ')
  else deps='A CONFIRMAR'; fi

  pend=()
  [[ -f $d/README.md ]] || pend+=("sem README")
  compgen -G "$d/.github/workflows/*.y*ml" >/dev/null 2>&1 || pend+=("sem CI (caso a parte, nao classificar ainda)")
  n=$(git -C "$d" grep -rIl -E 'TODO|FIXME' -- . 2>/dev/null | wc -l); (( n > 0 )) && pend+=("$n arquivo(s) com TODO/FIXME")
  [[ ${#pend[@]} -eq 0 ]] && pend=("nenhuma identificada automaticamente")

  cat > "$d/STATE.md" <<EOF
# $repo

**Status:** ativo
**Trilha:** $trilha
**Dono no GitHub:** $dono
**Agente principal:** A DEFINIR
**Agente revisor:** A DEFINIR
**Stack:** $stack
**Como rodar:** $rodar
**Dependências externas:** $deps
**Último trabalho relevante:** $ult
**Próximo passo sugerido:** A CONFIRMAR
**Pendências conhecidas:** $(printf '%s; ' "${pend[@]}" | sed 's/; $//')

> Gerado por inferência de código, commits e configuração em $(date +%Y-%m-%d).
> O que está como A CONFIRMAR / A DEFINIR depende de decisão do Ricardo — não preencher por inferência.
EOF

  git -C "$d" rev-parse --verify "$BRANCH" >/dev/null 2>&1 || git -C "$d" checkout -q -b "$BRANCH" 2>/dev/null
  git -C "$d" checkout -q "$BRANCH" 2>/dev/null
  git -C "$d" add STATE.md 2>/dev/null
  git -C "$d" -c user.name='Ricardo Esper' -c user.email='resper@bekaa.eu' commit -qm 'docs: adiciona STATE.md com o estado inferido do projeto' 2>/dev/null && feitos=$((feitos+1))
done < "$ESCOPO"

echo "STATE.md commitados (sem push): $feitos | pulados (vazios/sem git): $pulados"
echo "branch: $BRANCH"
