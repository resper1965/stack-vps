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
fim
