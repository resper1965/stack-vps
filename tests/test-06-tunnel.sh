#!/usr/bin/env bash
# shellcheck source=tests/lib.sh
. "$(dirname "$0")/lib.sh"
S=$RAIZ_REPO/scripts/06-tunnel.sh
echo "06-tunnel"

novo_tmp
printf 'CLOUDFLARE_API_TOKEN=x\nCLOUDFLARE_ACCOUNT_ID=acc\n' > "$T/env"
export STACK_ENV=$T/env STACK_CF_DIR=$T/cloudflared
stub curl 0 '{"success":true,"result":[{"id":"tid-123"}]}'
stub systemctl; stub cloudflared
bash "$S" dono@exemplo.com > "$T/out" 2>&1; afirma_rc $? 1 "tunnel existe sem credencial: recusa"
grep -q "rode 15-restore.sh antes" "$T/out"; afirma $? "mensagem aponta o restore"
nega_log "-X POST" "nao cria segundo tunnel"
[[ ! -e $T/cloudflared/config.yml ]]; afirma $? "nao escreve config.yml"

# tunnel e credencial presentes: host de emergencia preparado (DNS + Access), sem rota
cat > "$STUBS/curl" <<'EOF2'
#!/usr/bin/env bash
echo "curl $*" >> "$STUB_LOG"
case "$*" in
  *"-X POST"*access/apps" "*) echo '{"success":true,"result":{"id":"app-1"}}' ;;
  *access/apps*) echo '{"success":true,"result":[]}' ;;
  *dns_records*) echo '{"success":true,"result":[]}' ;;
  *) echo '{"success":true,"result":[{"id":"tid-123"}]}' ;;
esac
EOF2
chmod +x "$STUBS/curl"
install -d "$T/cloudflared"; echo '{}' > "$T/cloudflared/credentials.json"
printf 'ingress:\n  - hostname: emergencia.esper.ws\n    service: http://localhost:4096\n' > "$T/cloudflared/config.yml"
: > "$STUB_LOG"
bash "$S" dono@exemplo.com > "$T/out" 2>&1; afirma_rc $? 0 "tunnel existente com credencial: ok"
afirma_log '"domain":"emergencia.esper.ws"' "cria app de Access da emergencia"
afirma_log '"session_duration":"1h"' "sessao de 1h na emergencia"
afirma_log '"session_duration":"24h"' "SSH segue com 24h"
afirma_log '"name":"emergencia.esper.ws"' "cria CNAME da emergencia"
! grep -q emergencia.esper.ws "$T/cloudflared/config.yml"; afirma $? "config.yml sem rota de emergencia"
grep -q "AVISO: a web de emergência estava ligada e foi desligada ao reescrever o config.yml" "$T/out"; afirma $? "avisa que a emergencia foi desligada"
bash "$S" dono@exemplo.com > "$T/out" 2>&1
! grep -q AVISO "$T/out"; afirma $? "sem aviso quando a emergencia ja estava desligada"
fim
