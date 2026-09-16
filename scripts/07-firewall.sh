#!/usr/bin/env bash
# UFW: politica de entrada deny. Uso: sudo ./07-firewall.sh [--fechar-22]
# Sem --fechar-22 a porta 22 fica liberada; so feche depois de validar o acesso pelo tunnel.
set -euo pipefail
[[ $EUID -eq 0 ]] || { echo "rode como root"; exit 1; }
ufw --force reset >/dev/null
ufw default deny incoming >/dev/null
ufw default allow outgoing >/dev/null
[[ "${1:-}" == --fechar-22 ]] || ufw allow 22/tcp comment 'acesso direto - remover quando o tunnel validar' >/dev/null
ufw --force enable >/dev/null
ufw status verbose | head -10
