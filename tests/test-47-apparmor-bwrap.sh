#!/usr/bin/env bash
# shellcheck source=tests/lib.sh
. "$(dirname "$0")/lib.sh"
S=$RAIZ_REPO/scripts/47-apparmor-bwrap.sh
echo "47-apparmor-bwrap"

# Mundo falso: bwrap e sysctl em $T, statoverride com estado em $T/ov, grupo agente em $T/grupo.
mundo() {
  novo_tmp
  export AB_BWRAP=$T/bwrap AB_DIR=$T/apparmor.d AB_SYSCTL=$T/sysctl
  mkdir -p "$AB_DIR"; : > "$AB_BWRAP"; echo 1 > "$AB_SYSCTL"; : > "$T/grupo"
  stub chown; stub chmod
  cat > "$STUBS/apparmor_parser" <<'EOS'
#!/usr/bin/env bash
T=$(dirname "$STUB_LOG"); echo "apparmor_parser $*" >> "$STUB_LOG"
[[ $1 == -Q && -e $T/perfil-invalido ]] && exit 1; exit 0
EOS
  cat > "$STUBS/dpkg-statoverride" <<'EOS'
#!/usr/bin/env bash
T=$(dirname "$STUB_LOG"); echo "dpkg-statoverride $*" >> "$STUB_LOG"
case $1 in
  --list) [[ -s $T/ov ]] && { cat "$T/ov"; exit 0; }; exit 1 ;;
  --update) shift; echo "$2 $3 ${4#0} $5" > "$T/ov" ;;  # --add root agente 0750 caminho
  --remove) rm -f "$T/ov" ;;
esac
EOS
  cat > "$STUBS/stat" <<'EOS'
#!/usr/bin/env bash
echo "stat $*" >> "$STUB_LOG"; echo "755 root:root"
EOS
  cat > "$STUBS/getent" <<'EOS'
#!/usr/bin/env bash
echo "getent $*" >> "$STUB_LOG"; [[ -e $(dirname "$STUB_LOG")/grupo ]]
EOS
  stub id
  chmod +x "$STUBS"/*
}
MUT='chown|chmod|apparmor_parser -[rR]|dpkg-statoverride --(update|add|remove)'

mundo
bash "$S" --instalar >/dev/null 2>&1; afirma_rc $? 0 "--instalar"
cmp -s "$RAIZ_REPO/apparmor/usr.bin.bwrap" "$AB_DIR/usr.bin.bwrap"; afirma $? "perfil copiado identico"
afirma_log "chown root:root $AB_DIR/usr.bin.bwrap" "perfil root:root"
afirma_log "apparmor_parser -r $AB_DIR/usr.bin.bwrap" "recarrega o perfil"
afirma_log "dpkg-statoverride --update --add root agente 0750 $AB_BWRAP" "statoverride 0750 root:agente"
if (( $(grep -n 'apparmor_parser -Q' "$STUB_LOG" | head -1 | cut -d: -f1) < $(grep -n 'apparmor_parser -r' "$STUB_LOG" | head -1 | cut -d: -f1) )); then ok "valida antes de carregar"; else falha "ordem valida/carrega"; fi
afirma_log "apparmor_parser -Q -T $RAIZ_REPO/apparmor/usr.bin.bwrap" "valida com -Q -T"
nega_log "sysctl" "nao toca no sysctl"
[[ $(cat "$AB_SYSCTL") == 1 ]] && ok "arquivo do sysctl intacto" || falha "sysctl alterado"

# idempotente
: > "$STUB_LOG"
out=$(bash "$S" --instalar 2>&1); afirma_rc $? 0 "segunda execucao"
nega_log "dpkg-statoverride --update" "idempotente: statoverride nao repetido"
nega_log "chown" "idempotente: perfil nao reescrito"
[[ $out == *"ja instalado"* ]] && ok "diz ja instalado" || falha "mensagem ($out)"

# recusas: nada muda
recusa() { # <descricao> <trecho da mensagem>
  out=$(bash "$S" --instalar 2>&1); rc=$?
  afirma_rc $rc 1 "$1: recusa"
  [[ $out == *"$2"* ]] && ok "$1: mensagem" || falha "$1: mensagem ($out)"
  if grep -qE "$MUT" "$STUB_LOG"; then falha "$1: mexeu em algo"; else ok "$1: nada alterado"; fi
  [[ ! -e $AB_DIR/usr.bin.bwrap ]] && ok "$1: sem perfil instalado" || falha "$1: perfil instalado"
}
mundo; rm "$AB_BWRAP"; recusa "sem bwrap" "nao existe"
mundo; rm "$T/grupo"; recusa "sem grupo agente" "grupo agente"
mundo; : > "$T/perfil-invalido"; recusa "perfil invalido" "invalido"
mundo; echo "root root 755 $AB_BWRAP" > "$T/ov"; recusa "statoverride divergente" "statoverride diferente"
mundo; echo "# do dono" > "$AB_DIR/usr.bin.bwrap"
out=$(bash "$S" --instalar 2>&1); afirma_rc $? 1 "perfil existente diferente: recusa"
[[ $(cat "$AB_DIR/usr.bin.bwrap") == "# do dono" ]] && ok "arquivo do dono preservado" || falha "sobrescreveu"

# remover
mundo; bash "$S" --instalar >/dev/null 2>&1; : > "$STUB_LOG"
bash "$S" --remover >/dev/null 2>&1; afirma_rc $? 0 "--remover"
afirma_log "apparmor_parser -R $AB_DIR/usr.bin.bwrap" "descarrega o perfil"
afirma_log "dpkg-statoverride --remove $AB_BWRAP" "remove o statoverride"
afirma_log "chown root:root $AB_BWRAP" "restaura dono"; afirma_log "chmod 0755 $AB_BWRAP" "restaura modo 0755"
[[ ! -e $AB_DIR/usr.bin.bwrap && ! -s $T/ov ]] && ok "estado limpo" || falha "estado depois do remover"
nega_log "sysctl" "remover nao toca no sysctl"
bash "$S" --remover >/dev/null 2>&1; afirma_rc $? 0 "--remover repetido: tolerante"

mundo; bash "$S" --instalar >/dev/null 2>&1; echo "# editado" >> "$AB_DIR/usr.bin.bwrap"; : > "$STUB_LOG"
bash "$S" --remover >/dev/null 2>&1; afirma_rc $? 1 "--remover com perfil diferente: recusa"
grep -qE "$MUT" "$STUB_LOG" && falha "recusa mexeu em algo" || ok "recusa sem alteracoes"
[[ -f $AB_DIR/usr.bin.bwrap ]] && ok "perfil do dono mantido" || falha "perfil removido"
mundo; bash "$S" --instalar >/dev/null 2>&1; echo "root root 755 $AB_BWRAP" > "$T/ov"; : > "$STUB_LOG"
bash "$S" --remover >/dev/null 2>&1; afirma_rc $? 1 "--remover com statoverride alheio: recusa"
grep -qE "$MUT" "$STUB_LOG" && falha "recusa mexeu em algo" || ok "statoverride alheio intocado"

# status: so leitura
mundo
out=$(bash "$S" --status 2>&1); afirma_rc $? 0 "status"
[[ $out == *"perfil: ausente"* ]] && ok "status: ausente" || falha "status ausente ($out)"
[[ $out == *"(apparmor_restrict_unprivileged_userns): 1"* ]] && ok "status: restricao ligada" || falha "status restricao ($out)"
[[ $out == *"755 root:root"* ]] && ok "status: quem executa" || falha "status modo ($out)"
bash "$S" --instalar >/dev/null 2>&1; : > "$STUB_LOG"
out=$(bash "$S" --status 2>&1)
[[ $out == *"perfil: instalado"* ]] && ok "status: instalado" || falha "status instalado ($out)"
if grep -qE "$MUT" "$STUB_LOG"; then falha "status chamou comando que altera"; else ok "status so le"; fi
echo "# x" >> "$AB_DIR/usr.bin.bwrap"
out=$(bash "$S" --status 2>&1); [[ $out == *"diferente do repo"* ]] && ok "status: aponta diferenca" || falha "status diferenca ($out)"

mundo; bash "$S" --bobagem >/dev/null 2>&1; afirma_rc $? 2 "argumento desconhecido: uso"

# producao: overrides ignorados
guard=$(sed -n '/^# >>> normaliza/,/^# <<< normaliza/p' "$S")
r=$(env -u STACK_TESTE AB_BWRAP=/x AB_DIR=/y AB_SYSCTL=/z bash -c "$guard"$'\necho "$AB_BWRAP $AB_DIR"')
[[ $r == "/usr/bin/bwrap /etc/apparmor.d" ]] && ok "sem STACK_TESTE: overrides ignorados" || falha "guard ($r)"
fim
