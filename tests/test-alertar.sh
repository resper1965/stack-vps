#!/usr/bin/env bash
# shellcheck source=tests/lib.sh
. "$(dirname "$0")/lib.sh"
S=$RAIZ_REPO/scripts/alertar.sh
echo "alertar"
curl_stub() { # registra argumentos no STUB_LOG e o stdin (config) em STUB_LOG.stdin; falha se casar $1
  cat > "$STUBS/curl" <<EOS
#!/usr/bin/env bash
echo "curl \$*" >> "\$STUB_LOG"; atual=\$(cat); echo "\$atual" >> "\$STUB_LOG.stdin"
[[ -n "$1" ]] && grep -q "$1" <<< "\$atual" && exit 7
exit 0
EOS
  chmod +x "$STUBS/curl"; : > "$STUB_LOG.stdin"; }
segredos='NTFY_TOPIC=topico-secreto\nRESEND_API_KEY=re_secreta\nALERTA_DE=a@x\nTELEGRAM_BOT_TOKEN=bot-secreto\nTELEGRAM_CHAT_ID=9\n'

novo_tmp; export ALERTA_ENV=$T/env; printf "$segredos" > "$ALERTA_ENV"; curl_stub ""
bash "$S" "stack: falha" "disco cheio" >/dev/null 2>&1; afirma_rc $? 0 "tres canais: ok"
grep -q "ntfy.sh/topico-secreto" "$STUB_LOG.stdin"; afirma $? "ntfy recebe o topico"
grep -q "api.resend.com" "$STUB_LOG.stdin"; afirma $? "resend chamado"
grep -q "bot-secreto/sendMessage" "$STUB_LOG.stdin"; afirma $? "telegram recebe o token"
nega_log "topico-secreto" "topico fora da linha de comando"
nega_log "re_secreta" "chave do resend fora da linha de comando"
nega_log "bot-secreto" "token do telegram fora da linha de comando"

novo_tmp; export ALERTA_ENV=$T/env; printf 'NTFY_TOPIC=t1\n' > "$ALERTA_ENV"; curl_stub ""
bash "$S" t m >/dev/null 2>&1; afirma_rc $? 0 "so ntfy configurado: ok"
grep -q "resend" "$STUB_LOG.stdin"; [[ $? != 0 ]]; afirma $? "sem chave: resend pulado"

novo_tmp; export ALERTA_ENV=$T/env; printf 'NTFY_TOPIC=t1\nTELEGRAM_BOT_TOKEN=b1\nTELEGRAM_CHAT_ID=9\n' > "$ALERTA_ENV"
curl_stub "ntfy.sh"
bash "$S" t m >/dev/null 2>&1; afirma_rc $? 0 "ntfy falha: telegram ainda vai"
grep -q "api.telegram.org" "$STUB_LOG.stdin"; afirma $? "telegram tentado depois da falha"

novo_tmp; export ALERTA_ENV=$T/env; : > "$ALERTA_ENV"; curl_stub ""
bash "$S" t m >/dev/null 2>&1; afirma_rc $? 1 "nenhum canal: rc 1"
fim
