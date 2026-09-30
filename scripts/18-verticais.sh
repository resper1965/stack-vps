#!/usr/bin/env bash
# Visao por vertical de negocio: /srv/dev/verticais/<vertical>/<divisao>/<projeto> como
# atalho para o clone real, mais um <vertical>.code-workspace para abrir no VS Code.
# Os clones nao mudam de lugar: inventario, painel, OpenRig e scripts 08-15 seguem iguais.
# Mapa em docs/verticais.tsv (decisao do Ricardo; linha A DEFINIR fica de fora).
# Roda COMO dev. Idempotente: refaz os atalhos do zero a cada execucao.
set -euo pipefail
[[ $(id -un) == dev ]] || { echo "rode como dev"; exit 1; }
R=$(cd "$(dirname "$0")/.." && pwd)
MAPA=$R/docs/verticais.tsv
ESCOPO=/srv/dev/state/escopo-auditoria.tsv
V=/srv/dev/verticais

declare -A OK=(
  [pessoal]="app agents knowledge orm"
  [ness]="app agents knowledge compliance"
  [ionic]="app agents knowledge compliance"
  [bekaa]="app agents knowledge orm"
  [forense]="app agents knowledge compliance"
)

# pasta do clone de cada dono/repo, pelo escopo (dir desambigua repo com mesmo nome)
declare -A PASTA
while IFS=$'\t' read -r dono repo arvore dir; do
  [[ $dono == dono ]] || PASTA[$dono/$repo]=/srv/dev/repos/$arvore/$dir
done < "$ESCOPO"

# valida tudo antes de mexer em qualquer atalho
erros=0
while IFS=$'\t' read -r dono repo vert div; do
  [[ $dono == dono || $vert == "A DEFINIR" || -z $vert ]] && continue
  [[ -n ${OK[$vert]:-} ]] || { echo "vertical invalida '$vert': $dono/$repo"; erros=1; continue; }
  [[ " ${OK[$vert]} " == *" $div "* ]] || { echo "$vert nao tem '$div': $dono/$repo"; erros=1; }
  [[ -n ${PASTA[$dono/$repo]:-} ]] || { echo "fora do escopo: $dono/$repo"; erros=1; }
done < "$MAPA"
(( erros == 0 )) || { echo "corrija docs/verticais.tsv; nada foi alterado"; exit 1; }

mkdir -p "$V"
find "$V" -type l -delete; find "$V" -mindepth 1 -type d -empty -delete; rm -f "$V"/*.code-workspace
feitos=0; semclone=0; pendentes=0
declare -A PASTAS_WS
while IFS=$'\t' read -r dono repo vert div; do
  [[ $dono == dono ]] && continue
  [[ $vert == "A DEFINIR" || -z $vert ]] && { pendentes=$((pendentes+1)); continue; }
  alvo=${PASTA[$dono/$repo]}; nome=$(basename "$alvo")
  [[ -d $alvo/.git ]] || { echo "sem clone: $alvo"; semclone=$((semclone+1)); continue; }
  mkdir -p "$V/$vert/$div"; ln -sfn "$alvo" "$V/$vert/$div/$nome"
  PASTAS_WS[$vert]+="$div/$nome"$'\n'; feitos=$((feitos+1))
done < "$MAPA"

for vert in "${!PASTAS_WS[@]}"; do
  printf '%s' "${PASTAS_WS[$vert]}" | sort -f | python3 -c '
import json,sys
v,base=sys.argv[1],sys.argv[2]
pastas=[{"name":l.replace("/"," · "),"path":f"{base}/{v}/{l}"} for l in sys.stdin.read().split() if l]
json.dump({"folders":pastas,"settings":{}},open(f"{base}/{v}.code-workspace","w"),ensure_ascii=False,indent=2)
' "$vert" "$V"
done

echo "atalhos: $feitos | sem clone: $semclone | A DEFINIR: $pendentes"
ls "$V"/*.code-workspace 2>/dev/null | sed 's#^#workspace: #'
