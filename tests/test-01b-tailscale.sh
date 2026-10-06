#!/usr/bin/env bash
# shellcheck source=tests/lib.sh
. "$(dirname "$0")/lib.sh"
S=$RAIZ_REPO/scripts/01b-tailscale.sh
echo "01b-tailscale"

ts_stub() { # tailscale com status de saida configuravel
  cat > "$STUBS/tailscale" <<EOS
#!/usr/bin/env bash
echo "tailscale \$*" >> "\$STUB_LOG"
case \$1 in status) exit $1;; ip) echo 100.101.102.103;; esac
exit 0
EOS
  chmod +x "$STUBS/tailscale"; }

novo_tmp; ts_stub 1; stub systemctl; stub curl
env -u TS_AUTHKEY bash "$S" >/dev/null 2>&1; afirma_rc $? 1 "fora da tailnet e sem chave: recusa"
nega_log "tailscale up" "sem chave: nao chama up"

novo_tmp; ts_stub 1; stub systemctl; stub curl
TS_AUTHKEY=tskey-auth-teste bash "$S" >/dev/null 2>&1; afirma_rc $? 0 "com chave: entra"
afirma_log "tailscale up --authkey=tskey-auth-teste --hostname=stack" "entra como stack"

novo_tmp; ts_stub 0; stub systemctl; stub curl
env -u TS_AUTHKEY bash "$S" >/dev/null 2>&1; afirma_rc $? 0 "ja na tailnet: nada a fazer"
nega_log "tailscale up" "ja na tailnet: nao chama up"
nega_log "curl" "binario presente: nao reinstala"
fim
