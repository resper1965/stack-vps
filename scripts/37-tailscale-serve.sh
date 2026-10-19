#!/usr/bin/env bash
# Publica na tailnet (tailscale serve, HTTPS, em segundo plano e persistente):
#   https:443  -> OpenCode  (http://127.0.0.1:4096)
#   https:8443 -> PMO       (unix:/run/pmo/pmo.sock)
# Idempotente: o serve guarda um mapeamento por porta, entao repetir o mesmo comando
# sobrescreve o da porta em vez de acrescentar outro. Uso: sudo ./37-tailscale-serve.sh
# ATENCAO: 8443 com serve nao foi confirmado na documentacao (spike 2026-10-18); confirmar
# na VPS. Portas e alvos mudam por ambiente: PORTA_OPENCODE, PORTA_PMO, ALVO_OPENCODE, SOCKET_PMO.
set -euo pipefail
[[ $EUID -eq 0 || ${STACK_TESTE:-} == 1 ]] || { echo "rode como root"; exit 1; }

PORTA_OPENCODE=${PORTA_OPENCODE:-443}
PORTA_PMO=${PORTA_PMO:-8443}
ALVO_OPENCODE=${ALVO_OPENCODE:-http://127.0.0.1:4096}
SOCKET_PMO=${SOCKET_PMO:-/run/pmo/pmo.sock}

systemctl is-active --quiet tailscaled || { echo "tailscaled nao esta ativo (rode o 01b-tailscale.sh)"; exit 1; }

tailscale serve --bg --https="$PORTA_OPENCODE" "$ALVO_OPENCODE"
tailscale serve --bg --https="$PORTA_PMO" "unix:$SOCKET_PMO"

# O nome da tailnet vem do proprio tailscale; nao se adivinha.
nome=$(tailscale status --json 2>/dev/null | python3 -c \
  'import json,sys; print(json.load(sys.stdin)["Self"]["DNSName"].rstrip("."))' 2>/dev/null) || nome=
if [[ -n $nome ]]; then
  echo "OpenCode: https://$nome$([[ $PORTA_OPENCODE == 443 ]] || echo ":$PORTA_OPENCODE")"
  echo "PMO:      https://$nome:$PORTA_PMO"
else
  echo "nome da tailnet ilegivel; estado atual:"
  tailscale serve status || true
fi
