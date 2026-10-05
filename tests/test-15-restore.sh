#!/usr/bin/env bash
# shellcheck source=tests/lib.sh
. "$(dirname "$0")/lib.sh"
S=$RAIZ_REPO/scripts/15-restore.sh
echo "15-restore"

prepara() {
  unset STACK_ROOT
  export CLOUDFLARE_ACCOUNT_ID=acc R2_ACCESS_KEY_ID=k R2_SECRET_ACCESS_KEY=s RESTIC_PASSWORD=p
  D=$T/dest; mkdir -p "$D"; stub restic; stub chown; stub chmod
}

novo_tmp; prepara
mkdir -p "$D/srv/dev/state"; echo conteudo > "$D/srv/dev/state/inventario.md"
bash "$S" --destino "$D" >/dev/null 2>&1; afirma_rc $? 1 "destino com dado: recusa"
nega_log "restic restore" "destino com dado: restic nao roda"

novo_tmp; prepara
mkdir -p "$D/srv/dev/state"; echo conteudo > "$D/srv/dev/state/inventario.md"
bash "$S" --destino "$D" --forcar >/dev/null 2>&1; afirma_rc $? 0 "com --forcar: restaura"

novo_tmp; prepara   # VPS recem-formatada: o 02 criou .env vazio e state/reviews vazio
mkdir -p "$D/srv/dev/secrets" "$D/srv/dev/state/reviews"; : > "$D/srv/dev/secrets/.env"
bash "$S" --destino "$D" >/dev/null 2>&1; afirma_rc $? 0 "VPS recem-formatada: restaura"
afirma_log "restic restore latest --target $D" "restaura o ultimo snapshot no destino"
afirma_log "--include /srv/dev/secrets/.env" "inclui o .env"
afirma_log "--include /etc/cloudflared/credentials.json" "inclui a credencial do tunnel"
nega_log "chown" "destino de teste: nao mexe em dono"

novo_tmp; prepara
bash "$S" --qualquer >/dev/null 2>&1; afirma_rc $? 1 "argumento desconhecido: recusa"
fim
