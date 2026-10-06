#!/usr/bin/env bash
# Tailscale: instala e entra na tailnet como "stack". Idempotente.
# Uso: sudo TS_AUTHKEY=tskey-auth-... ./01b-tailscale.sh
# A chave e de uso unico, gerada no painel do Tailscale na hora; nunca vai para arquivo.
set -euo pipefail
[[ $EUID -eq 0 || ${STACK_TESTE:-} == 1 ]] || { echo "rode como root"; exit 1; }

command -v tailscale >/dev/null || curl -fsSL https://tailscale.com/install.sh | sh
systemctl enable --now tailscaled

if tailscale status >/dev/null 2>&1; then
  echo "tailscale: ja na tailnet"
else
  [[ -n ${TS_AUTHKEY:-} ]] || { echo "informe TS_AUTHKEY (uso unico, gerada no painel do Tailscale)"; exit 1; }
  tailscale up --authkey="$TS_AUTHKEY" --hostname=stack
fi
echo "tailscale: $(tailscale ip -4 | head -1) — desative a expiracao de chave do no 'stack' no painel"
