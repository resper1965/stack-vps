#!/usr/bin/env bash
# shellcheck source=tests/lib.sh
. "$(dirname "$0")/lib.sh"
S=$RAIZ_REPO/scripts/alertar.sh
echo "alertar"
novo_tmp; export ALERTA_ENV=$T/env
printf 'NTFY_TOPIC=t1\nRESEND_API_KEY=r1\nALERTA_DE=a@x\nTELEGRAM_BOT_TOKEN=b1\nTELEGRAM_CHAT_ID=9\n' > "$ALERTA_ENV"
stub curl 0
bash "$S" "stack: falha" "disco cheio" >/dev/null 2>&1; afirma_rc $? 0 "tres canais: ok"
afirma_log "https://ntfy.sh/t1" "ntfy"
afirma_log "https://api.resend.com/emails" "resend"
afirma_log "https://api.telegram.org/botb1/sendMessage" "telegram"

novo_tmp; export ALERTA_ENV=$T/env; printf 'NTFY_TOPIC=t1\n' > "$ALERTA_ENV"; stub curl 0
bash "$S" t m >/dev/null 2>&1; afirma_rc $? 0 "so ntfy configurado: ok"
nega_log "resend" "sem chave: resend pulado"

novo_tmp; export ALERTA_ENV=$T/env
printf 'NTFY_TOPIC=t1\nTELEGRAM_BOT_TOKEN=b1\nTELEGRAM_CHAT_ID=9\n' > "$ALERTA_ENV"
cat > "$STUBS/curl" <<'EOS'
#!/usr/bin/env bash
echo "curl $*" >> "$STUB_LOG"; [[ "$*" == *ntfy.sh* ]] && exit 7; exit 0
EOS
chmod +x "$STUBS/curl"
bash "$S" t m >/dev/null 2>&1; afirma_rc $? 0 "ntfy falha: telegram ainda vai"
afirma_log "api.telegram.org" "telegram tentado depois da falha"

novo_tmp; export ALERTA_ENV=$T/env; : > "$ALERTA_ENV"; stub curl 0
bash "$S" t m >/dev/null 2>&1; afirma_rc $? 1 "nenhum canal: rc 1"
fim
