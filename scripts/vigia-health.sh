#!/usr/bin/env bash
# Roda o health.sh e alerta so quando o estado muda (ok -> falha ou falha -> ok).
# Uso: pelo stack-health.timer, de hora em hora.
set -uo pipefail
HEALTH=${VIGIA_HEALTH:-/srv/dev/bin/health.sh}
ALERTAR=${VIGIA_ALERTAR:-/usr/local/lib/stack-vps/alertar.sh}
ESTADO=${VIGIA_ESTADO:-/var/lib/stack-vps/health.estado}
mkdir -p "$(dirname "$ESTADO")"
saida=$("$HEALTH" 2>&1); rc=$?
agora=ok; (( rc == 0 )) || agora=falha
antes=$(cat "$ESTADO" 2>/dev/null || echo ok)
echo "$agora" > "$ESTADO"
if [[ $agora != "$antes" ]]; then
  if [[ $agora == falha ]]; then "$ALERTAR" "stack: FALHA" "$(grep FALHA <<< "$saida")"
  else "$ALERTAR" "stack: recuperado" "health.sh voltou a passar"; fi
fi
echo "$saida"
