#!/usr/bin/env bash
# shellcheck source=tests/lib.sh
. "$(dirname "$0")/lib.sh"
S=$RAIZ_REPO/scripts/14-backup.sh
echo "14-backup"

prepara() { # raiz falsa com o que o backup espera
  export STACK_ROOT=$T/raiz; unset STACK_ENV
  mkdir -p "$STACK_ROOT"/srv/dev/{state,data,secrets} "$STACK_ROOT"/home/dev/.claude "$STACK_ROOT"/etc/cloudflared "$STACK_ROOT"/var/lib/pmo/fila
  echo '{}' > "$STACK_ROOT/etc/cloudflared/credentials.json"
  echo "X=1" > "$STACK_ROOT/srv/dev/secrets/admin.env"
  export CLOUDFLARE_ACCOUNT_ID=acc R2_ACCESS_KEY_ID=k R2_SECRET_ACCESS_KEY=s RESTIC_PASSWORD=p
  stub chown
}
restic_stub() { # restic que falha no subcomando $1 (ou em nenhum)
  cat > "$STUBS/restic" <<EOS
#!/usr/bin/env bash
echo "restic \$* repo=\$RESTIC_REPOSITORY" >> "\$STUB_LOG"
[[ \$1 == "$1" ]] && exit 1
exit 0
EOS
  chmod +x "$STUBS/restic"; }

novo_tmp; prepara; restic_stub nenhum
bash "$S" >/dev/null 2>&1; afirma_rc $? 0 "sucesso"
[[ -f $STACK_ROOT/var/lib/stack-vps/last-backup ]]; afirma $? "sucesso grava .last-backup"
afirma_log "repo=s3:https://acc.r2.cloudflarestorage.com/stack-vps-backup" "repositorio no R2 da conta"
afirma_log "restic forget --keep-daily 7 --keep-weekly 4 --keep-monthly 6 --prune" "retencao do spec"
afirma_log "/home/dev/.claude/.credentials.json" "credencial do Claude excluida"
afirma_log "/srv/dev/state" "state no backup"
afirma_log "/var/lib/pmo/fila" "fila transitoria do painel fora do backup (exclude)"

novo_tmp; prepara; restic_stub backup
bash "$S" >/dev/null 2>&1; afirma_rc $? 1 "falha no backup: sai com erro"
[[ ! -e $STACK_ROOT/var/lib/stack-vps/last-backup ]]; afirma $? "falha no backup: sem .last-backup"
nega_log "restic forget" "falha no backup: nao poda"

novo_tmp; prepara; restic_stub nenhum; unset RESTIC_PASSWORD
bash "$S" >/dev/null 2>&1; afirma_rc $? 1 "sem RESTIC_PASSWORD: recusa"
nega_log "restic" "sem senha: restic nao roda"
novo_tmp; prepara; restic_stub nenhum; rm "$STACK_ROOT/etc/cloudflared/credentials.json"
bash "$S" >/dev/null 2>&1; afirma_rc $? 1 "falta essencial: recusa"
nega_log "restic backup" "falta essencial: nao faz backup parcial"
[[ ! -e $STACK_ROOT/var/lib/stack-vps/last-backup ]]; afirma $? "falta essencial: sem .last-backup"
fim
