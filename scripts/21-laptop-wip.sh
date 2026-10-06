#!/usr/bin/env bash
# Salva o trabalho nao commitado de cada repositorio numa branch wip/laptop-<data>, sem tocar na
# pasta nem na branch atual: o commit e montado num indice temporario (respeita o .gitignore).
# Depois o 20-laptop-github.sh envia essa branch com as mesmas travas (segredo, documento, tamanho).
# Uso: 21-laptop-wip.sh [--simular] <repo> [<repo> ...]
set -uo pipefail
SIMULAR=0; [[ ${1:-} == --simular ]] && { SIMULAR=1; shift; }
(( $# )) || { echo "uso: $0 [--simular] <repo> [<repo> ...]"; exit 1; }
B="${WIP_BRANCH:-wip/laptop-${WIP_DATA:-$(date +%F)}}"
rc=0
for d in "$@"; do
  if ! git -C "$d" rev-parse -q --verify HEAD >/dev/null 2>&1; then echo "PULADO (sem commit): $d"; continue; fi
  if [[ -z $(git -C "$d" status --porcelain 2>/dev/null) ]]; then echo "LIMPO: $d"; continue; fi
  n=$(git -C "$d" status --porcelain | wc -l)
  if (( SIMULAR )); then echo "SIMULA: $d -> $B ($n arquivo(s))"; continue; fi
  idx=$(mktemp -u); orig="$(git -C "$d" rev-parse --absolute-git-dir)/index"
  if [[ -f $orig ]]; then cp "$orig" "$idx"; fi
  if GIT_INDEX_FILE=$idx git -C "$d" add -A && tree=$(GIT_INDEX_FILE=$idx git -C "$d" write-tree) \
     && c=$(git -C "$d" commit-tree "$tree" -p HEAD -m "chore: trabalho em andamento salvo do laptop ($n arquivos)") \
     && git -C "$d" update-ref "refs/heads/$B" "$c"; then
    echo "SALVO: $d -> $B ($n arquivo(s))"
  else echo "FALHOU: $d"; rc=1; fi
  rm -f "$idx"
done
exit $rc
