#!/usr/bin/env bash
# shellcheck source=tests/lib.sh
. "$(dirname "$0")/lib.sh"
S=$RAIZ_REPO/bin/hostinger.sh
echo "hostinger"
# curl_stub <modo>: responde por URL no formato "corpo\ncodigo"; modo ok | erro | semcampos
curl_stub() {
  cat > "$STUBS/curl" <<EOS
#!/usr/bin/env bash
echo "curl \$*" >> "\$STUB_LOG"; cat >> "\$STUB_LOG.stdin"
modo=$1
case "\$*" in
  *"/metrics?"*)
    if [[ \$modo == erro ]]; then printf '{"message":"boom"}\n500'
    elif [[ \$modo == semcampos ]]; then printf '{"cpu_usage":null}\n200'
    else printf '{"cpu_usage":{"unit":"%%","usage":{"100":10,"200":42.6}},"ram_usage":{"unit":"bytes","usage":{"200":1073741824}},"disk_space":{"unit":"bytes","usage":{"200":5368709120}}}\n200'; fi ;;
  */snapshot) if [[ "\$*" == *"-X POST"* ]]; then printf '{"id":9,"name":"snapshot","state":"sent"}\n200'
              else printf '{"id":1,"created_at":"2026-10-01T10:00:00Z","expires_at":"2026-10-08T10:00:00Z"}\n200'; fi ;;
  */virtual-machines/123) printf '{"id":123,"memory":4096,"disk":102400}\n200' ;;
  *) printf '{"id":7,"state":"sent"}\n200' ;;
esac
EOS
  chmod +x "$STUBS/curl"; : > "$STUB_LOG.stdin"; }
prep() { novo_tmp; export HOSTINGER_ENV=$T/env; printf 'HOSTINGER_API_TOKEN=tok-secreto\nHOSTINGER_VM_ID=123\n' > "$HOSTINGER_ENV"; curl_stub "$1"; }
roda() { saida=$(bash "$S" "$@" 2>&1); rc=$?; }
nega_texto() { if grep -qF -- "$1" <<< "$saida"; then falha "$2 (achei '$1' na saida)"; else ok "$2"; fi; }

prep ok; roda snapshot
afirma_rc $rc 3 "snapshot sem --sim: rc 3"
grep -qE 'POST|PUT|DELETE' "$STUB_LOG"; [[ $? != 0 ]]; afirma $? "snapshot sem --sim: nenhuma chamada de escrita"
grep -q "snapshot" <<< "$saida"; afirma $? "snapshot sem --sim: mostra o plano"
nega_texto "tok-secreto" "plano sem token"

prep ok; roda snapshot --sim
afirma_rc $rc 0 "snapshot --sim: rc 0"
afirma_log "-X POST https://developers.hostinger.com/api/vps/v1/virtual-machines/123/snapshot" "snapshot --sim: POST no caminho do spike"
grep -q "UM snapshot por VM; este substitui o existente" <<< "$saida"; afirma $? "aviso de um snapshot por VM"
grep -q "2026-10-01T10:00:00Z" <<< "$saida"; afirma $? "mostra a data do snapshot atual"
nega_log "tok-secreto" "token fora da linha de comando"
grep -q "Bearer tok-secreto" "$STUB_LOG.stdin"; afirma $? "token presente no stdin"
nega_texto "tok-secreto" "saida sem token"

prep ok; roda metricas
afirma_rc $rc 0 "metricas: rc 0"
[[ $saida == "  ok    hostinger cpu 43% ram 25% disco 5%" ]]; afirma $? "metricas formata a linha ($saida)"
nega_log "tok-secreto" "metricas: token fora do argv"

prep erro; roda metricas
afirma_rc $rc 1 "metricas com erro de API: rc 1"
[[ $saida == "  FALHA hostinger indisponível" ]]; afirma $? "metricas com erro: FALHA"
prep semcampos; roda metricas
afirma_rc $rc 1 "metricas sem campos: rc 1"
[[ $saida == "  FALHA hostinger indisponível" ]]; afirma $? "metricas sem campos: FALHA"

prep ok; printf 'HOSTINGER_VM_ID=123\n' > "$HOSTINGER_ENV"; unset HOSTINGER_API_TOKEN; roda metricas
afirma_rc $rc 1 "sem token: rc 1"
[[ ! -s $STUB_LOG ]]; afirma $? "sem token: nenhuma chamada curl"
grep -q HOSTINGER_API_TOKEN <<< "$saida"; afirma $? "sem token: mensagem clara"

for c in reiniciar recuperacao; do
  prep ok; roda $c
  afirma_rc $rc 3 "$c sem --sim: rc 3"
  [[ ! -s $STUB_LOG ]]; afirma $? "$c sem --sim: nenhuma chamada"
  prep ok; roda $c --sim
  afirma_rc $rc 0 "$c --sim: rc 0"
  caminho=restart; [[ $c == recuperacao ]] && caminho=recovery
  afirma_log "-X POST https://developers.hostinger.com/api/vps/v1/virtual-machines/123/$caminho" "$c: POST $caminho"
done
nega_log "root_password" "senha de recuperacao fora do argv"
grep -q root_password "$STUB_LOG.stdin"; afirma $? "senha de recuperacao vai pelo stdin"
fim
