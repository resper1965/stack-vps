#!/usr/bin/env bash
# Backup restic -> R2 (bucket stack-vps-backup). Roda como root, pelo timer diario.
# Grava state/.last-backup so se backup, poda e (aos domingos) verificacao passarem.
set -euo pipefail
[[ $EUID -eq 0 || ${STACK_TESTE:-} == 1 ]] || { echo "rode como root"; exit 1; }
# shellcheck source=scripts/lib/restic-env.sh
. "$(dirname "$(readlink -f "$0")")/lib/restic-env.sh"
STAMP=${STACK_ROOT:-}/srv/dev/state/.last-backup

restic cat config >/dev/null 2>&1 || restic init

for p in "${BACKUP_REQUIRED[@]}"; do [[ -e $p ]] || { echo "falta caminho essencial: $p"; exit 1; }; done
paths=(); for p in "${BACKUP_PATHS[@]}"; do [[ -e $p ]] && paths+=("$p"); done
(( ${#paths[@]} )) || { echo "nenhum caminho do backup existe"; exit 1; }
excl=(); for e in "${BACKUP_EXCLUDES[@]}"; do excl+=(--exclude "$e"); done

restic backup --one-file-system "${excl[@]}" "${paths[@]}"
restic forget --keep-daily 7 --keep-weekly 4 --keep-monthly 6 --prune
if [[ $(date +%u) == 7 ]]; then restic check --read-data-subset=5%; fi

touch "$STAMP"; chown dev:dev "$STAMP" 2>/dev/null || true
echo "backup ok: $(date -Is)"
