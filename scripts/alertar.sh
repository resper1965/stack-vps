#!/usr/bin/env bash
# Envia um alerta a todos os canais configurados: ntfy, e-mail (Resend) e Telegram.
# Canal sem configuracao e pulado; falha de um nao impede os outros. rc 1 se nenhum entregou.
# Uso: alertar.sh <titulo> <mensagem>
set -uo pipefail
TITULO=${1:?uso: $0 <titulo> <mensagem>}; MSG=${2:-}
ENVF=${ALERTA_ENV:-/srv/dev/secrets/admin.env}
if [[ -s $ENVF ]]; then
  set -a
  # shellcheck source=/dev/null
  . "$ENVF"
  set +a
fi
entregues=0
json() { python3 -c 'import json,sys; print(json.dumps(sys.argv[1]))' "$1"; }

if [[ -n ${NTFY_TOPIC:-} ]]; then
  if curl -fsS -m 15 -H "Title: $TITULO" -d "$MSG" "https://ntfy.sh/$NTFY_TOPIC" >/dev/null; then
    entregues=$((entregues+1)); else echo "alerta: ntfy falhou"; fi
fi
if [[ -n ${RESEND_API_KEY:-} ]]; then
  corpo="{\"from\":$(json "${ALERTA_DE:-stack <onboarding@resend.dev>}"),\"to\":[\"resper@bekaa.eu\"],\"subject\":$(json "$TITULO"),\"text\":$(json "$MSG")}"
  if curl -fsS -m 15 -X POST https://api.resend.com/emails -H "Authorization: Bearer $RESEND_API_KEY" \
       -H 'Content-Type: application/json' -d "$corpo" >/dev/null; then
    entregues=$((entregues+1)); else echo "alerta: e-mail falhou"; fi
fi
if [[ -n ${TELEGRAM_BOT_TOKEN:-} && -n ${TELEGRAM_CHAT_ID:-} ]]; then
  if curl -fsS -m 15 "https://api.telegram.org/bot$TELEGRAM_BOT_TOKEN/sendMessage" \
       --data-urlencode "chat_id=$TELEGRAM_CHAT_ID" --data-urlencode "text=$TITULO
$MSG" >/dev/null; then
    entregues=$((entregues+1)); else echo "alerta: telegram falhou"; fi
fi
(( entregues > 0 ))
