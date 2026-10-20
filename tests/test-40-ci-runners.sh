#!/usr/bin/env bash
# shellcheck source=tests/lib.sh
. "$(dirname "$0")/lib.sh"
S=$RAIZ_REPO/scripts/40-ci-runners.sh
echo "40-ci-runners"

TOKEN=ghp_FAKEtoken0123456789abcdefXYZ
ORGS_OK=bekaa-trusted-advisors:Default:3,forense-io:Default:2

# Mundo falso em $T: nada toca o sistema real. O install de teste repete a chamada no log e executa o
# install real sem -o/-g (nao ha usuario ci aqui); o sudo/systemctl/docker so registram.
mundo() {
  novo_tmp
  export CI_DIR=$T/srv/ci CI_OPT=$T/opt/ci CI_UNIT=$T/unit CI_ADMIN_ENV=$T/admin.env CI_RUN_USER=$T/run
  export CI_REDE_SCRIPT=$T/39.sh CI_PULAR_PULL=0
  mkdir -p "$CI_DIR" "$CI_UNIT" "$T/opt"; echo 4242 > "$T/uid"; echo ativa > "$T/rede"
  printf 'RUNNER_TOKEN=%s\nCI_ORGS=%s\n' "$TOKEN" "$ORGS_OK" > "$CI_ADMIN_ENV"
  printf '#!/usr/bin/env bash\ncat "%s/rede"\n' "$T" > "$CI_REDE_SCRIPT"; chmod +x "$CI_REDE_SCRIPT"
  cat > "$STUBS/id" <<'EOS'
#!/usr/bin/env bash
T=$(dirname "$STUB_LOG"); [[ -e $T/sem-ci ]] && exit 1; cat "$T/uid"
EOS
  cat > "$STUBS/systemctl" <<'EOS'
#!/usr/bin/env bash
T=$(dirname "$STUB_LOG"); echo "systemctl $*" >> "$STUB_LOG"
case "$*" in
  *"is-active --quiet stack-ci-rede.service"*) [[ ! -e $T/rede-parada ]] ;;
  "is-active stack-ci-runners.service") echo active ;;
esac
EOS
  cat > "$STUBS/sudo" <<'EOS'
#!/usr/bin/env bash
T=$(dirname "$STUB_LOG"); echo "sudo $*" >> "$STUB_LOG"
case "$*" in
  *is-active*) [[ ! -e $T/docker-off ]] ;;
  *"docker pull"*) [[ -f $CI_DIR/config.json && ! -e $T/pull-falha ]] ;;
esac
EOS
  cat > "$STUBS/install" <<'EOS'
#!/usr/bin/env bash
echo "install $*" >> "$STUB_LOG"
a=(); while (( $# )); do case $1 in -o|-g) shift 2 ;; *) a+=("$1"); shift ;; esac; done
exec /usr/bin/install "${a[@]}"
EOS
  chmod +x "$STUBS/id" "$STUBS/systemctl" "$STUBS/sudo" "$STUBS/install"
}
igual() { if [[ $1 == "$2" ]]; then ok "$3"; else falha "$3 ($1)"; fi; }
# falha fechada: rc 1 e nenhuma escrita (arquivos, pacote, unidade, install, daemon-reload)
nada() {
  local n; n=$(find "$CI_DIR" -mindepth 1 2>/dev/null | wc -l)
  if [[ $n == 0 && ! -e $CI_OPT && -z $(ls -A "$CI_UNIT") ]]; then ok "$1: nada escrito"; else falha "$1: escreveu algo"; fi
  nega_log "install " "$1: nenhum install"; nega_log "daemon-reload" "$1: sem daemon-reload"; nega_log "docker pull" "$1: sem pull"
}
recusa() { # recusa <rotulo> <trecho da mensagem>
  out=$(bash "$S" 2>&1); afirma_rc $? 1 "$1: rc 1"
  if [[ $out == *"$2"* ]]; then ok "$1: mensagem"; else falha "$1: mensagem ($out)"; fi
  if [[ $out != *"$TOKEN"* ]]; then ok "$1: token fora da saida"; else falha "$1: token na saida"; fi
  nada "$1"
}

mundo
env -u STACK_TESTE bash "$S" >/dev/null 2>&1; rc=$?
if [[ $EUID -ne 0 ]]; then
  afirma_rc $rc 1 "sem root: recusa"; nega_log "install" "sem root: nada instalado"
else ok "rodando como root: caso nao-root pulado"; fi

# entradas invalidas
mundo; printf 'CI_ORGS=%s\n' "$ORGS_OK" > "$CI_ADMIN_ENV"; recusa "sem RUNNER_TOKEN" "RUNNER_TOKEN"
mundo; printf 'RUNNER_TOKEN=%s\n' "$TOKEN" > "$CI_ADMIN_ENV"; recusa "sem CI_ORGS" "CI_ORGS"
mundo; rm "$CI_ADMIN_ENV"; recusa "admin.env ausente" "admin.env"
for ruim in "sem-formato" "a:b" "a:b:3:" "a:b:3:x" "-org:Default:1" "o_rg:Default:1" "org::1" "org:Gr/upo:1" "org:Default:11" \
            "org:Default:-1" "org:Default:abc" "org:Default:" "org:Default:03" "a:Default:1,,b:Default:1" "org:   :1" ""; do
  mundo; printf 'RUNNER_TOKEN=%s\nCI_ORGS=%s\n' "$TOKEN" "$ruim" > "$CI_ADMIN_ENV"; recusa "CI_ORGS '$ruim'" "CI_ORGS"
done
mundo; printf 'RUNNER_TOKEN=%s\nCI_ORGS=%s\n' "$TOKEN" "forense-io:Default:1,Forense-IO:Default:2" > "$CI_ADMIN_ENV"; recusa "org duplicada" "repetida"
for n in nessenergy NessEnergy; do
  mundo; printf 'RUNNER_TOKEN=%s\nCI_ORGS=%s\n' "$TOKEN" "forense-io:Default:1,$n:Default:1" > "$CI_ADMIN_ENV"; recusa "$n bloqueada" "nao e permitido"
done
for t in "curto" "tem espaco 0123456789abcdef" 'tem-hifen-0123456789abcdef' "$(printf 'a%.0s' $(seq 1 256))"; do
  mundo; printf 'RUNNER_TOKEN=%s\nCI_ORGS=%s\n' "$t" "$ORGS_OK" > "$CI_ADMIN_ENV"; recusa "token '${t:0:12}'" "RUNNER_TOKEN"
done

# pre-requisitos do ambiente
mundo; : > "$T/sem-ci"; recusa "ci inexistente" "ci nao existe"
for v in 0 999 abc ""; do mundo; echo "$v" > "$T/uid"; recusa "uid '$v'" "UID invalido"; done
mundo; rmdir "$CI_DIR"; recusa "/srv/ci ausente" "nao existe"
mundo; : > "$T/docker-off"; recusa "docker rootless inativo" "Docker rootless"
mundo; bash "$S" --bobagem >/dev/null 2>&1; afirma_rc $? 2 "argumento desconhecido: uso"; nada "argumento desconhecido"

# sucesso sem --habilitar
mundo
out=$(bash "$S" 2>&1); afirma_rc $? 0 "instala"
if [[ $out != *"$TOKEN"* ]]; then ok "token fora da saida"; else falha "token na saida"; fi
if [[ $(cat "$CI_DIR/token") == "$TOKEN" ]]; then ok "token gravado"; else falha "conteudo do token"; fi
igual "$(stat -c %a "$CI_DIR/token")" 400 "token 0400"
afirma_log "install -m 0400 -o ci -g ci" "token instalado como ci:ci 0400"
igual "$(stat -c %a "$CI_DIR/config.json")" 640 "config 0640"
afirma_log "install -m 0640 -o ci -g ci" "config instalada como ci:ci 0640"
if grep -qF "$TOKEN" "$STUB_LOG"; then falha "token no argv de algum comando"; else ok "token fora do STUB_LOG"; fi
if python3 - "$CI_DIR/config.json" <<'EOF'
import json, sys
c = json.load(open(sys.argv[1]))
assert c == {"imagem": "ghcr.io/actions/actions-runner:latest", "cpus": "2", "memoria": "4g", "docker_socket": False,
             "orgs": {"bekaa-trusted-advisors": {"grupo": "Default", "quantidade": 3},
                      "forense-io": {"grupo": "Default", "quantidade": 2}}}, c
assert c["docker_socket"] is False and "docker_socket_ciente_do_risco" not in c
EOF
then ok "config.json igual ao contrato"; else falha "config.json difere do contrato"; fi
# o supervisor aceita o que o instalador escreveu
if PYTHONPATH=$RAIZ_REPO python3 -c "
import sys; from ci.runners import carregar_config, ler_token
carregar_config(sys.argv[1])" "$CI_DIR/config.json"; then ok "carregar_config aceita a config"; else falha "carregar_config recusou"; fi
if [[ $(ls -A "$CI_OPT" | tr '
' ' ') == "__init__.py runners.py " ]]; then
  ok "/opt/ci: so runners.py e __init__.py"; else falha "/opt/ci: conteudo ($(ls -A "$CI_OPT" | tr '\n' ' '))"; fi
afirma_log "install -m 644 -o root -g root $RAIZ_REPO/ci/__init__.py $RAIZ_REPO/ci/runners.py $CI_OPT/" "pacote do root 0644"
afirma_log "install -d -m 755 -o root -g root $CI_OPT" "diretorio do pacote 0755 root"
igual "$(stat -c %a "$CI_UNIT/stack-ci-runners.service")" 644 "unidade 0644"
afirma_log "systemctl daemon-reload" "daemon-reload"
afirma_log "docker pull ghcr.io/actions/actions-runner:latest" "pull da imagem"
afirma_log "XDG_RUNTIME_DIR=$T/run/4242 DOCKER_HOST=unix://$T/run/4242/docker.sock docker pull" "pull como ci com socket e runtime dir"
afirma_log "sudo -u ci env XDG_RUNTIME_DIR=$T/run/4242 systemctl --user is-active --quiet docker" "confere o docker rootless do ci"
nega_log "enable" "sem --habilitar: nao habilita"; nega_log "start" "sem --habilitar: nao inicia"
nega_log "stack-ci-rede" "sem --habilitar: nao exige a rede"
if [[ -z $(find "$CI_DIR" -name '*.novo') ]]; then ok "sem arquivo temporario sobrando"; else falha "arquivo .novo sobrando"; fi

# idempotencia
antes=$(cd "$CI_DIR" && sha256sum token config.json; stat -c '%a' token config.json)
: > "$STUB_LOG"
bash "$S" >/dev/null 2>&1; afirma_rc $? 0 "segunda execucao"
depois=$(cd "$CI_DIR" && sha256sum token config.json; stat -c '%a' token config.json)
igual "$depois" "$antes" "arquivos identicos"
nega_log "enable" "idempotente: nada habilitado"
igual "$(ls -A "$CI_DIR" | tr '\n' ' ')" "config.json token " "idempotente: so os dois arquivos"
# mudar o token no admin.env troca o arquivo (rotacao)
NOVO=ghp_ROTATEDtoken0123456789abcdefZ
printf 'RUNNER_TOKEN=%s\nCI_ORGS=%s\n' "$NOVO" "$ORGS_OK" > "$CI_ADMIN_ENV"
bash "$S" >/dev/null 2>&1; igual "$(cat "$CI_DIR/token")" "$NOVO" "rotacao: token novo gravado"

# formatos tolerados do admin.env: export, aspas, CRLF; o ultimo valor vence
mundo; printf 'X=1\r\nexport RUNNER_TOKEN="%s"\r\nCI_ORGS='"'"'%s'"'"'\r\nRUNNER_TOKEN=%s\n' "$TOKEN" "$ORGS_OK" "$TOKEN" > "$CI_ADMIN_ENV"
bash "$S" >/dev/null 2>&1; afirma_rc $? 0 "admin.env com export/aspas/CRLF"
igual "$(cat "$CI_DIR/token")" "$TOKEN" "valor limpo"
# 0 runners numa organizacao e valido
mundo; printf 'RUNNER_TOKEN=%s\nCI_ORGS=%s\n' "$TOKEN" "forense-io:Default:0,org2:Meu grupo.1:10" > "$CI_ADMIN_ENV"
bash "$S" >/dev/null 2>&1; afirma_rc $? 0 "quantidade 0 e 10 e grupo com espaco"
igual "$(python3 -c "import json,sys; print(json.load(open(sys.argv[1]))['orgs']['org2'])" "$CI_DIR/config.json")" "{'grupo': 'Meu grupo.1', 'quantidade': 10}" "grupo com espaco preservado"

# pull falha: rc 1, unidade nao habilitada (mesmo com --habilitar)
mundo; : > "$T/pull-falha"
out=$(bash "$S" --habilitar 2>&1); afirma_rc $? 1 "pull falha: rc 1"
if [[ $out == *"pull"* ]]; then ok "pull falha: mensagem"; else falha "pull falha: mensagem ($out)"; fi
nega_log "enable" "pull falha: nao habilita"
# pular o pull (so em teste)
mundo; export CI_PULAR_PULL=1
bash "$S" >/dev/null 2>&1; afirma_rc $? 0 "CI_PULAR_PULL=1 (teste)"; nega_log "docker pull" "pull pulado"

# --habilitar
mundo
bash "$S" --habilitar >/dev/null 2>&1; afirma_rc $? 0 "--habilitar com isolamento ativo"
afirma_log "systemctl enable --now stack-ci-runners.service" "enable --now"
if (( $(grep -n 'docker pull' "$STUB_LOG" | head -1 | cut -d: -f1) < $(grep -n 'enable --now' "$STUB_LOG" | head -1 | cut -d: -f1) )); then ok "pull antes de habilitar"; else falha "ordem pull/enable"; fi
if (( $(grep -n 'daemon-reload' "$STUB_LOG" | head -1 | cut -d: -f1) < $(grep -n 'enable --now' "$STUB_LOG" | head -1 | cut -d: -f1) )); then ok "daemon-reload antes de habilitar"; else falha "ordem reload/enable"; fi
if grep -qF "$TOKEN" "$STUB_LOG"; then falha "token no STUB_LOG (habilitar)"; else ok "token fora do STUB_LOG (habilitar)"; fi
mundo; echo inativa > "$T/rede"
out=$(bash "$S" --habilitar 2>&1); afirma_rc $? 1 "--habilitar com 39 inativa: recusa"
if [[ $out == *"isolamento de rede não está ativo"* ]]; then ok "mensagem do isolamento"; else falha "mensagem do isolamento ($out)"; fi
nega_log "enable" "39 inativa: nao habilita"; nada "39 inativa"
mundo; : > "$T/rede-parada"
bash "$S" --habilitar >/dev/null 2>&1; afirma_rc $? 1 "--habilitar com stack-ci-rede.service parada: recusa"
nega_log "enable" "unidade da rede parada: nao habilita"; nada "unidade da rede parada"
mundo; printf '#!/usr/bin/env bash\necho ativa\nexit 1\n' > "$CI_REDE_SCRIPT"
bash "$S" --habilitar >/dev/null 2>&1; afirma_rc $? 0 "39 diz ativa (rc ignorado, o texto manda)"
mundo; rm "$CI_REDE_SCRIPT"
bash "$S" --habilitar >/dev/null 2>&1; afirma_rc $? 1 "script do 39 ausente: recusa"; nega_log "enable" "39 ausente: nao habilita"

# --parar e --status
mundo
bash "$S" --parar >/dev/null 2>&1; afirma_rc $? 0 "--parar"
afirma_log "systemctl disable --now stack-ci-runners.service" "disable --now"
nega_log "rm " "--parar: arquivos mantidos"
mundo
out=$(bash "$S" --status 2>&1); afirma_rc $? 0 "--status sem status.json"
if [[ $out == *"unidade: active"* && $out == *"status.json ausente"* ]]; then ok "status: unidade e ausencia"; else falha "status sem arquivo ($out)"; fi
printf '{"atualizado": 1.5, "runners": 5, "erro": null, "orgs": {"a": {"ativos": 3, "esperados": 3}}}\n' > "$CI_DIR/status.json"
bash "$S" >/dev/null 2>&1
out=$(bash "$S" --status 2>&1); afirma_rc $? 0 "--status com status.json"
if [[ $out == *'"runners": 5'* && $out == *'"ativos": 3'* ]]; then ok "status: contagens"; else falha "status: contagens ($out)"; fi
if [[ $out != *"$TOKEN"* ]]; then ok "status: sem token"; else falha "status: token na saida"; fi
printf '{"erro": "\033[31mx\033[0m"}\n' > "$CI_DIR/status.json"
out=$(bash "$S" --status 2>&1); if [[ $out != *$'\033'* ]]; then ok "status: sem caracteres de controle"; else falha "status: escape passou"; fi
mundo; : > "$T/sem-ci"; : > "$T/docker-off"
bash "$S" --status >/dev/null 2>&1; afirma_rc $? 0 "--status nao exige pre-requisitos"
bash "$S" --parar >/dev/null 2>&1; afirma_rc $? 0 "--parar nao exige pre-requisitos"

# unidade
U=$RAIZ_REPO/systemd/stack-ci-runners.service
for l in "Description=Runners efêmeros do GitHub Actions (conta ci)" "After=network-online.target stack-ci-rede.service user@%U.service" \
         "Requires=stack-ci-rede.service" "Wants=network-online.target" "Type=simple" "User=ci" "Group=ci" "WorkingDirectory=/srv/ci" \
         "Environment=PYTHONPATH=/opt" "Environment=XDG_RUNTIME_DIR=/run/user/%U" "Environment=DOCKER_HOST=unix:///run/user/%U/docker.sock" \
         "ExecStart=/usr/bin/python3 -m ci.runners --config /srv/ci/config.json --token-file /srv/ci/token --status /srv/ci/status.json" \
         "Restart=on-failure" "RestartSec=30" "NoNewPrivileges=yes" "ProtectSystem=strict" "ReadWritePaths=/srv/ci" "PrivateTmp=yes" \
         "WantedBy=multi-user.target"; do
  if grep -qxF "$l" "$U"; then ok "unidade: $l"; else falha "unidade: $l"; fi
done
if grep -iE '^Environment=.*(proxy|token)' "$U" >/dev/null; then falha "unidade: Environment com proxy/TOKEN"; else ok "unidade: sem proxy nem TOKEN no ambiente"; fi
if grep -E '^ProtectHome=' "$U" >/dev/null; then falha "unidade: ProtectHome esconderia /run/user"; else ok "unidade: sem ProtectHome"; fi
if command -v systemd-analyze >/dev/null 2>&1; then
  novo_tmp; cp "$U" "$T/stack-ci-runners.service"; chmod 644 "$T/stack-ci-runners.service"   # /mnt/c vem com permissao larga
  v=$(systemd-analyze verify "$T/stack-ci-runners.service" 2>&1 | grep -v -e 'stack-ci-rede' -e '/usr/bin/python3' -e 'User=ci' -e 'Unit .* not found' || true)
  if [[ -z $v ]]; then ok "systemd-analyze verify"; else falha "systemd-analyze verify ($v)"; fi
fi

# producao: override de ambiente e ignorado (guard extraido do script, como no teste do 38/39)
guard=$(sed -n '/^# >>> normaliza/,/^# <<< normaliza/p' "$S")
if [[ -n $guard ]]; then ok "guard encontrado"; else falha "guard encontrado"; fi
vars='$CI_ADMIN_ENV $CI_DIR $CI_OPT $CI_REDE_SCRIPT $CI_UNIT $CI_PULAR_PULL $CI_RUN_USER'
r=$(env -u STACK_TESTE CI_ADMIN_ENV=/x CI_DIR=/x CI_OPT=/x CI_REDE_SCRIPT=/x CI_UNIT=/x CI_PULAR_PULL=1 CI_RUN_USER=/x \
  bash -c "$guard"$'\necho "'"$vars"'"')
igual "$r" "/srv/dev/secrets/admin.env /srv/ci /opt/ci /usr/local/lib/stack-vps/39-ci-rede.sh /etc/systemd/system 0 /run/user" "sem STACK_TESTE: overrides ignorados"
r=$(STACK_TESTE=1 CI_ADMIN_ENV=/a CI_DIR=/b CI_OPT=/c CI_REDE_SCRIPT=/d CI_UNIT=/e CI_PULAR_PULL=1 CI_RUN_USER=/f \
  bash -c "$guard"$'\necho "'"$vars"'"')
igual "$r" "/a /b /c /d /e 1 /f" "com STACK_TESTE=1: overrides valem"
fim
