#!/usr/bin/env bash
# Restaura do restic os caminhos do backup. Uso: sudo ./15-restore.sh [--destino DIR] [--forcar]
# Na VPS recem-formatada o admin.env ainda esta vazio: antes, exporte CLOUDFLARE_ACCOUNT_ID,
# R2_ACCESS_KEY_ID, R2_SECRET_ACCESS_KEY e RESTIC_PASSWORD (as tres ultimas do gerenciador de senhas)
# e rode preservando-as, porque o sudo as descarta:
#   sudo --preserve-env=CLOUDFLARE_ACCOUNT_ID,R2_ACCESS_KEY_ID,R2_SECRET_ACCESS_KEY,RESTIC_PASSWORD ./15-restore.sh
set -euo pipefail
[[ $EUID -eq 0 || ${STACK_TESTE:-} == 1 ]] || { echo "rode como root"; exit 1; }
DEST=/; FORCAR=0
while (($#)); do
  case $1 in
    --destino) DEST=${2:?informe o diretorio}; shift 2 ;;
    --forcar)  FORCAR=1; shift ;;
    *) echo "uso: $0 [--destino DIR] [--forcar]"; exit 1 ;;
  esac
done
# shellcheck source=scripts/lib/restic-env.sh
. "$(dirname "$(readlink -f "$0")")/lib/restic-env.sh"

# Ocupado = algum arquivo nao vazio onde o backup vai escrever. O .env vazio que o 02 cria nao conta.
ocupado() {
  local p
  for p in "${BACKUP_PATHS[@]}"; do
    [[ -n $(find "$DEST/${p#/}" -type f -size +0 -print -quit 2>/dev/null) ]] && return 0
  done
  return 1
}
if ocupado && (( ! FORCAR )); then
  echo "destino $DEST ja tem dados nos caminhos do backup; use --forcar para sobrescrever"; exit 1
fi

inc=(); for p in "${BACKUP_PATHS[@]}"; do inc+=(--include "$p"); done
restic restore latest --target "$DEST" "${inc[@]}"

if [[ $DEST == / ]]; then
  for d in /srv/dev/state /srv/dev/data /home/dev/.claude /home/dev/.codex; do
    if [[ -e $d ]]; then chown -R dev:dev "$d"; fi
  done
  for d in /home/agente/.claude /home/agente/.codex; do
    if [[ -e $d ]] && id agente >/dev/null 2>&1; then chown -R agente:agente "$d"; fi
  done
  if [[ -e /srv/forense ]]; then chown -R dev:dev /srv/forense; chmod 750 /srv/forense; fi
  if [[ -f /srv/dev/secrets/admin.env ]]; then chown dev:dev /srv/dev/secrets/admin.env; chmod 600 /srv/dev/secrets/admin.env; fi
  if [[ -f /srv/dev/secrets/agente.env ]]; then chown dev:agente /srv/dev/secrets/agente.env; chmod 640 /srv/dev/secrets/agente.env; fi
  if [[ -d /srv/dev/secrets/projetos ]]; then
    chown -R dev:agente /srv/dev/secrets/projetos; chmod -R u=rwX,g=rX,o= /srv/dev/secrets/projetos
  fi
  if [[ -f /etc/cloudflared/credentials.json ]]; then
    chown root:root /etc/cloudflared/credentials.json; chmod 600 /etc/cloudflared/credentials.json
  fi
fi
echo "restore ok em $DEST"
