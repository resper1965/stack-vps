#!/usr/bin/env bash
# Envia um alerta a todos os canais configurados: ntfy, e-mail (Resend) e Telegram.
# Canal sem configuracao e pulado; falha de um nao impede os outros. rc 1 se nenhum entregou.
# Uso: alertar.sh <titulo> <mensagem>
# Topico, chave e token vao ao curl pelo stdin (-K -): na linha de comando ficariam visiveis em ps
# para qualquer usuario da maquina, inclusive o agente.
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
envia() { # envia <canal> <config-curl> [args...]: config pelo stdin, o resto (sem segredo) por argumento
  local canal=$1 cfg=$2; shift 2
  if printf '%s\n' "$cfg" | curl -fsS -m 15 -K - "$@" >/dev/null; then entregues=$((entregues+1))
  else echo "alerta: $canal falhou"; fi
}

if [[ -n ${NTFY_TOPIC:-} ]]; then
  envia ntfy "url = \"https://ntfy.sh/$NTFY_TOPIC\"" -H "Title: $TITULO" -d "$MSG"
fi
if [[ -n ${RESEND_API_KEY:-} ]]; then
  corpo="{\"from\":$(json "${ALERTA_DE:-stack <onboarding@resend.dev>}"),\"to\":[\"resper@bekaa.eu\"],\"subject\":$(json "$TITULO"),\"text\":$(json "$MSG")}"
  envia e-mail "url = \"https://api.resend.com/emails\"
header = \"Authorization: Bearer $RESEND_API_KEY\"" -X POST -H 'Content-Type: application/json' -d "$corpo"
fi
if [[ -n ${TELEGRAM_BOT_TOKEN:-} && -n ${TELEGRAM_CHAT_ID:-} ]]; then
  envia telegram "url = \"https://api.telegram.org/bot$TELEGRAM_BOT_TOKEN/sendMessage\"" \
    --data-urlencode "chat_id=$TELEGRAM_CHAT_ID" --data-urlencode "text=$TITULO
$MSG"
fi
(( entregues > 0 ))
