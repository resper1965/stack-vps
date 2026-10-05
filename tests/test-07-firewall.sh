#!/usr/bin/env bash
# shellcheck source=tests/lib.sh
. "$(dirname "$0")/lib.sh"
S=$RAIZ_REPO/scripts/07-firewall.sh
echo "07-firewall"

novo_tmp; stub tailscale 1; stub ufw
bash "$S" >/dev/null 2>&1; afirma_rc $? 1 "tailscale caido: recusa"
nega_log "ufw" "tailscale caido: UFW intocado"

novo_tmp; stub tailscale 0 ""; stub ufw
bash "$S" >/dev/null 2>&1; afirma_rc $? 1 "tailscale sem IP: recusa"
nega_log "ufw" "sem IP: UFW intocado"

novo_tmp; stub tailscale 0 "100.101.102.103"; stub ufw
bash "$S" >/dev/null 2>&1; afirma_rc $? 0 "tailscale ok: aplica"
afirma_log "ufw default deny incoming" "entrada negada por padrao"
afirma_log "ufw allow in on tailscale0 to any port 22 proto tcp" "22 so na tailscale0"
nega_log "ufw allow 22/tcp" "22 publica nao e liberada"
fim
