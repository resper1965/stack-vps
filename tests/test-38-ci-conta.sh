#!/usr/bin/env bash
# shellcheck source=tests/lib.sh
. "$(dirname "$0")/lib.sh"
S=$RAIZ_REPO/scripts/38-ci-conta.sh
echo "38-ci-conta"

# Mundo falso: estado em arquivos de $T. Nada toca o sistema real.
# existe = usuario ci criado; grupos = saida de "id -nG ci"; ativo = docker rootless ativo.
mundo() {
  novo_tmp
  export CI_HOME=$T/srv/ci CI_SUBUID_FILE=$T/subuid CI_SUBGID_FILE=$T/subgid
  export CI_APPARMOR=$T/rootlesskit CI_RUN_USER=$T/run CI_VERIFICA=0
  mkdir -p "$CI_RUN_USER/1001"
  printf 'dev:100000:65536\nagente:165536:65536\n' > "$CI_SUBUID_FILE"
  cp "$CI_SUBUID_FILE" "$CI_SUBGID_FILE"
  echo ci > "$T/grupos"; : > "$CI_APPARMOR"
  stub usermod; stub loginctl; stub systemctl; stub install; stub chown
  cat > "$STUBS/useradd" <<'EOS'
#!/usr/bin/env bash
echo "useradd $*" >> "$STUB_LOG"; : > "$(dirname "$STUB_LOG")/existe"
EOS
  cat > "$STUBS/id" <<'EOS'
#!/usr/bin/env bash
T=$(dirname "$STUB_LOG")
case "$1" in
  -nG) cat "$T/grupos" ;;
  -u) echo 1001 ;;
  *) [[ -e $T/existe ]] ;;
esac
EOS
  cat > "$STUBS/sudo" <<'EOS'
#!/usr/bin/env bash
T=$(dirname "$STUB_LOG"); echo "sudo $*" >> "$STUB_LOG"
case "$*" in
  *setuptool*) : > "$T/ativo" ;;
  *is-active*) [[ -e $T/ativo ]] ;;
  *"test ! -r"*) [[ ! -e $T/legivel ]] ;;
esac
EOS
  chmod +x "$STUBS/useradd" "$STUBS/id" "$STUBS/sudo"
}

mundo
env -u STACK_TESTE bash "$S" >/dev/null 2>&1; rc=$?
if [[ $EUID -ne 0 ]]; then
  afirma_rc $rc 1 "sem root: recusa"; nega_log "useradd" "sem root: nao cria usuario"
else ok "rodando como root: caso nao-root pulado"; fi

mundo
bash "$S" >/dev/null 2>&1; afirma_rc $? 0 "cria a conta"
afirma_log "useradd -m -U -s /bin/bash -d $CI_HOME ci" "usuario comum, grupo proprio, home em CI_HOME"
nega_log " -G" "sem grupos extras"; nega_log "--system" "nao e conta de sistema"
afirma_log "install -d -m 700 -o ci -g ci $CI_HOME" "home 0700 de ci:ci"
afirma_log "loginctl enable-linger ci" "linger ligado"
afirma_log "dockerd-rootless-setuptool.sh install" "instala o Docker rootless"

for g in sudo docker users agente pmo dev; do
  mundo; : > "$T/existe"; echo "ci $g" > "$T/grupos"
  out=$(bash "$S" 2>&1); afirma_rc $? 1 "ci em '$g': recusa"
  if [[ $out == *"$g"* ]]; then ok "$g: mensagem cita o grupo"; else falha "$g: mensagem cita o grupo"; fi
  nega_log "useradd" "$g: nada criado"; nega_log "loginctl" "$g: linger intocado"
done

mundo
bash "$S" >/dev/null 2>&1
if [[ $(grep -c '^ci:' "$CI_SUBUID_FILE") == 1 && $(grep '^ci:' "$CI_SUBUID_FILE") == "ci:231072:65536" ]]; then ok "subuid: primeiro bloco livre depois do agente"; else falha "subuid: $(grep '^ci:' "$CI_SUBUID_FILE")"; fi
if grep -qx 'ci:231072:65536' "$CI_SUBGID_FILE"; then ok "subgid igual"; else falha "subgid"; fi
mundo; echo 'ci:400000:65536' >> "$CI_SUBUID_FILE"
bash "$S" >/dev/null 2>&1
if [[ $(grep -c '^ci:' "$CI_SUBUID_FILE") == 1 && -n $(grep -x 'ci:400000:65536' "$CI_SUBUID_FILE") ]]; then ok "subuid existente de ci e mantido"; else falha "subuid existente"; fi

mundo; : > "$T/existe"; : > "$T/ativo"
bash "$S" >/dev/null 2>&1; afirma_rc $? 0 "segunda execucao"
nega_log "useradd" "idempotente: nao recria o usuario"
nega_log "setuptool" "idempotente: nao reinstala o Docker rootless"

mundo; echo marca > "$CI_APPARMOR"
bash "$S" >/dev/null 2>&1
if [[ $(cat "$CI_APPARMOR") == marca ]]; then ok "perfil AppArmor existente nao e reescrito"; else falha "perfil reescrito"; fi
nega_log "reload apparmor" "nao recarrega o apparmor"; nega_log "apparmor_parser" "nao chama apparmor_parser"
mundo; rm -f "$CI_APPARMOR"
out=$(bash "$S" 2>&1); afirma_rc $? 0 "perfil ausente: so avisa"
if [[ $out == *rootlesskit* && ! -e $CI_APPARMOR ]]; then ok "aviso sem criar o perfil"; else falha "aviso sem criar o perfil"; fi

mundo; export CI_VERIFICA=1; : > "$T/legivel"
out=$(bash "$S" 2>&1); afirma_rc $? 1 "segredo legivel: falha fechado"
if [[ $out == *agente.env* ]]; then ok "diz qual segredo vazou"; else falha "diz qual segredo vazou"; fi
mundo; export CI_VERIFICA=1
bash "$S" >/dev/null 2>&1; afirma_rc $? 0 "segredos ilegiveis: passa"
afirma_log "test ! -r /srv/dev/secrets/admin.env" "confere o admin.env"
fim
