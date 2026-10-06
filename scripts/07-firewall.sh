#!/usr/bin/env bash
# UFW: entrada negada; a 22 so pela tailnet. O loopback, por onde chega o Cloudflare Tunnel,
# ja e liberado pelas regras-base do UFW. Uso: sudo ./07-firewall.sh
# Recusa rodar sem o Tailscale de pe: fechar a 22 publica sem a tailnet tranca a VPS.
# Saida de emergencia: console do hPanel -> ufw allow 22/tcp
set -euo pipefail
[[ $EUID -eq 0 || ${STACK_TESTE:-} == 1 ]] || { echo "rode como root"; exit 1; }

TSIP=$(tailscale ip -4 2>/dev/null | head -1 || true)
[[ $TSIP == 100.* ]] || { echo "tailscale sem IP 100.x: rode 01b-tailscale.sh antes; UFW nao foi alterado"; exit 1; }

ufw --force reset >/dev/null
ufw default deny incoming >/dev/null
ufw default allow outgoing >/dev/null
ufw allow in on tailscale0 to any port 22 proto tcp comment 'ssh pela tailnet' >/dev/null
# porta do proprio Tailscale (WireGuard): sem ela o caminho direto depende de furo no NAT que expira
# na ociosidade, e o SSH da timeout enquanto o caminho se refaz. So responde a quem tem chave da tailnet.
ufw allow 41641/udp comment 'tailscale direto' >/dev/null
ufw allow in on tailscale0 to any port 8080 proto tcp comment 'painel do PMO' >/dev/null
ufw --force enable >/dev/null
ufw status verbose | head -12
