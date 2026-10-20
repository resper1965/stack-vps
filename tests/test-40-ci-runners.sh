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
  export CI_DIR=$T/srv/ci CI_CFG=$T/etc/stack-ci CI_OPT=$T/opt/ci CI_UNIT=$T/unit CI_ADMIN_ENV=$T/admin.env CI_RUN_USER=$T/run
  export CI_REDE_SCRIPT=$T/39.sh CI_PULAR_PULL=0
  mkdir -p "$CI_DIR" "$CI_UNIT" "$T/opt" "$T/etc"; echo 4242 > "$T/uid"; echo ativa > "$T/rede"
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
  *"is-active --quiet stack-ci-runners.service"*) [[ -e $T/runners-ativo ]] ;;
  "is-active stack-ci-runners.service") echo active ;;
esac
EOS
  cat > "$STUBS/sudo" <<'EOS'
#!/usr/bin/env bash
T=$(dirname "$STUB_LOG"); echo "sudo $*" >> "$STUB_LOG"
case "$*" in
  *is-active*) [[ ! -e $T/docker-off ]] ;;
  *"docker pull"*) [[ -f $CI_CFG/config.json && ! -e $T/pull-falha ]] ;;
  *"sh -c"*) eval "${@: -1}" ;;
esac
EOS
  cat > "$STUBS/docker" <<'EOS'
#!/usr/bin/env bash
T=$(dirname "$STUB_LOG"); echo "docker $*" >> "$STUB_LOG"
case $1 in ps) cat "$T/ociosos" 2>/dev/null ;; esac
EOS
  cat > "$STUBS/install" <<'EOS'
#!/usr/bin/env bash
echo "install $*" >> "$STUB_LOG"
a=(); while (( $# )); do case $1 in -o|-g) shift 2 ;; *) a+=("$1"); shift ;; esac; done
exec /usr/bin/install "${a[@]}"
EOS
  chmod +x "$STUBS/id" "$STUBS/systemctl" "$STUBS/sudo" "$STUBS/install" "$STUBS/docker"
}
igual() { if [[ $1 == "$2" ]]; then ok "$3"; else falha "$3 ($1)"; fi; }
# falha fechada: rc 1 e nenhuma escrita (arquivos, pacote, unidade, install, daemon-reload)
nada() {
  local n; n=$(find "$CI_DIR" -mindepth 1 2>/dev/null | wc -l)
  if [[ $n == 0 && ! -e $CI_CFG && ! -e $CI_OPT && -z $(ls -A "$CI_UNIT") ]]; then ok "$1: nada escrito"; else falha "$1: escreveu algo"; fi
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
if [[ $(cat "$CI_CFG/token") == "$TOKEN" ]]; then ok "token gravado"; else falha "conteudo do token"; fi
igual "$(stat -c %a "$CI_CFG/token")" 400 "token 0400"
afirma_log "install -T -m 0400 -o ci -g ci" "token instalado como ci:ci 0400, sem seguir link"
afirma_log "install -d -m 0750 -o root -g ci $CI_CFG" "diretorio da config root:ci 0750"
igual "$(stat -c %a "$CI_CFG/config.json")" 640 "config 0640"
afirma_log "install -T -m 0640 -o root -g ci" "config do root (a conta ci so le)"
nega_log "-m 0640 -o ci" "config nunca pertence a ci"
if [[ -z $(ls -A "$CI_DIR") ]]; then ok "/srv/ci sem token nem config"; else falha "/srv/ci: $(ls -A "$CI_DIR")"; fi
if grep -qF "$TOKEN" "$STUB_LOG"; then falha "token no argv de algum comando"; else ok "token fora do STUB_LOG"; fi
if python3 - "$CI_CFG/config.json" <<'EOF'
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
carregar_config(sys.argv[1])" "$CI_CFG/config.json"; then ok "carregar_config aceita a config"; else falha "carregar_config recusou"; fi
if [[ $(ls -A "$CI_OPT" | tr '
' ' ') == "__init__.py runners.py " ]]; then
  ok "/opt/ci: so runners.py e __init__.py"; else falha "/opt/ci: conteudo ($(ls -A "$CI_OPT" | tr '\n' ' '))"; fi
afirma_log "install -m 644 -o root -g root $RAIZ_REPO/ci/__init__.py $RAIZ_REPO/ci/runners.py $CI_OPT/" "pacote do root 0644"
afirma_log "install -d -m 755 -o root -g root $CI_OPT" "diretorio do pacote 0755 root"
igual "$(stat -c %a "$CI_UNIT/stack-ci-runners.service")" 644 "unidade 0644"
afirma_log "systemctl daemon-reload" "daemon-reload"
afirma_log "docker pull ghcr.io/actions/actions-runner:latest" "pull da imagem"
afirma_log "XDG_RUNTIME_DIR=$T/run/4242 DOCKER_HOST=unix://$T/run/4242/docker.sock timeout 900 docker pull" "pull como ci com socket e runtime dir"
afirma_log "sudo -u ci env XDG_RUNTIME_DIR=$T/run/4242 systemctl --user is-active --quiet docker" "confere o docker rootless do ci"
nega_log "enable" "sem --habilitar: nao habilita"; nega_log "start" "sem --habilitar: nao inicia"
nega_log "stack-ci-rede" "sem --habilitar: nao exige a rede"
if [[ -z $(find "$CI_DIR" "$CI_CFG" -name '*.novo') ]]; then ok "sem arquivo temporario sobrando"; else falha "arquivo .novo sobrando"; fi

# idempotencia
antes=$(cd "$CI_CFG" && sha256sum token config.json; stat -c '%a' token config.json)
: > "$STUB_LOG"
bash "$S" >/dev/null 2>&1; afirma_rc $? 0 "segunda execucao"
depois=$(cd "$CI_CFG" && sha256sum token config.json; stat -c '%a' token config.json)
igual "$depois" "$antes" "arquivos identicos"
nega_log "enable" "idempotente: nada habilitado"
igual "$(ls -A "$CI_CFG" | tr '\n' ' ')" "config.json token " "idempotente: so os dois arquivos"
# mudar o token no admin.env troca o arquivo (rotacao)
NOVO=ghp_ROTATEDtoken0123456789abcdefZ
printf 'RUNNER_TOKEN=%s\nCI_ORGS=%s\n' "$NOVO" "$ORGS_OK" > "$CI_ADMIN_ENV"
bash "$S" >/dev/null 2>&1; igual "$(cat "$CI_CFG/token")" "$NOVO" "rotacao: token novo gravado"

# formatos tolerados do admin.env: export, aspas, CRLF; o ultimo valor vence
mundo; printf 'X=1\r\nexport RUNNER_TOKEN="%s"\r\nCI_ORGS='"'"'%s'"'"'\r\nRUNNER_TOKEN=%s\n' "$TOKEN" "$ORGS_OK" "$TOKEN" > "$CI_ADMIN_ENV"
bash "$S" >/dev/null 2>&1; afirma_rc $? 0 "admin.env com export/aspas/CRLF"
igual "$(cat "$CI_CFG/token")" "$TOKEN" "valor limpo"
# 0 runners numa organizacao e valido
mundo; printf 'RUNNER_TOKEN=%s\nCI_ORGS=%s\n' "$TOKEN" "forense-io:Default:0,org2:Meu grupo.1:10" > "$CI_ADMIN_ENV"
bash "$S" >/dev/null 2>&1; afirma_rc $? 0 "quantidade 0 e 10 e grupo com espaco"
igual "$(python3 -c "import json,sys; print(json.load(open(sys.argv[1]))['orgs']['org2'])" "$CI_CFG/config.json")" "{'grupo': 'Meu grupo.1', 'quantidade': 10}" "grupo com espaco preservado"

# C1: root grava em area da conta ci? Nao: token/config ficam em CI_CFG (root); alvo plantado e recusado sem escrever fora
for alvo in token token.novo config.json config.json.novo; do
  mundo; mkdir -p "$CI_CFG"; echo ORIGINAL > "$T/fora"; ln -s "$T/fora" "$CI_CFG/$alvo"
  out=$(bash "$S" 2>&1); afirma_rc $? 1 "link simbolico em $alvo: recusa"
  igual "$(cat "$T/fora")" ORIGINAL "link em $alvo: alvo intacto"
  nega_log "install -T" "link em $alvo: nada instalado"; nega_log "daemon-reload" "link em $alvo: sem daemon-reload"
done
for alvo in token token.novo config.json; do
  mundo; mkdir -p "$CI_CFG/$alvo"
  bash "$S" >/dev/null 2>&1; afirma_rc $? 1 "diretorio em $alvo: recusa"
  if [[ -z $(ls -A "$CI_CFG/$alvo") ]]; then ok "diretorio em $alvo: nada gravado dentro"; else falha "diretorio em $alvo: gravou dentro"; fi
  nega_log "daemon-reload" "diretorio em $alvo: sem daemon-reload"
done
mundo; mkdir -p "$T/outro"; ln -s "$T/outro" "$CI_CFG"
bash "$S" >/dev/null 2>&1; afirma_rc $? 1 "CI_CFG link simbolico: recusa"
if [[ -z $(ls -A "$T/outro") ]]; then ok "CI_CFG link: nada gravado no destino"; else falha "CI_CFG link: gravou no destino"; fi

# I1: --parar tambem para os containers ociosos (como ci); falha em parar nao impede o disable
mundo; printf 'abc123
def456
' > "$T/ociosos"
bash "$S" --parar >/dev/null 2>&1; afirma_rc $? 0 "--parar com containers"
afirma_log "XDG_RUNTIME_DIR=$T/run/4242 DOCKER_HOST=unix://$T/run/4242/docker.sock sh -c" "--parar: docker como ci"
afirma_log "docker ps -q --filter label=stack-ci" "--parar: lista pelo rotulo"
afirma_log "docker stop abc123 def456" "--parar: para os ociosos"
mundo
bash "$S" --parar >/dev/null 2>&1
if grep -q '^docker stop' "$STUB_LOG"; then falha "--parar sem containers: docker stop chamado"; else ok "--parar sem containers: nada a parar"; fi

# pull falha: rc 1, unidade nao habilitada (mesmo com --habilitar)
mundo; : > "$T/pull-falha"
out=$(bash "$S" --habilitar 2>&1); afirma_rc $? 1 "pull falha: rc 1"
if [[ $out == *"pull"* ]]; then ok "pull falha: mensagem"; else falha "pull falha: mensagem ($out)"; fi
nega_log "enable" "pull falha: nao habilita"
nega_log "restart" "pull falha: unidade inativa nao reinicia"
if [[ $out != *"segue com"* ]]; then ok "pull falha, unidade inativa: sem aviso de credencial antiga"; else falha "aviso indevido ($out)"; fi
mundo; : > "$T/pull-falha"; : > "$T/runners-ativo"
out=$(bash "$S" 2>&1); afirma_rc $? 1 "pull falha com unidade ativa: rc 1"
if [[ $out == *"segue com o token e a config antigos"* ]]; then ok "pull falha: avisa que a unidade ativa segue com a credencial antiga"; else falha "pull falha: sem aviso ($out)"; fi
nega_log "restart" "pull falha: nao reinicia"
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
# a unidade INSTALADA (com o UID numerico no lugar do molde)
mundo; bash "$S" >/dev/null 2>&1; U=$CI_UNIT/stack-ci-runners.service
for l in "Description=Runners efêmeros do GitHub Actions (conta ci)" "After=network-online.target stack-ci-rede.service user@4242.service" \
         "Requires=stack-ci-rede.service" "Wants=network-online.target" "Type=simple" "User=ci" "Group=ci" "WorkingDirectory=/" \
         "Environment=PYTHONPATH=/opt" "Environment=XDG_RUNTIME_DIR=/run/user/4242" "Environment=DOCKER_HOST=unix:///run/user/4242/docker.sock" \
         "ExecStart=/usr/bin/python3 -P -m ci.runners --config /etc/stack-ci/config.json --token-file /etc/stack-ci/token --status /srv/ci/status.json" \
         "Restart=on-failure" "RestartSec=30" "NoNewPrivileges=yes" "ProtectSystem=strict" "ReadWritePaths=/srv/ci" "PrivateTmp=yes" \
         "WantedBy=multi-user.target"; do
  if grep -qxF "$l" "$U"; then ok "unidade: $l"; else falha "unidade: $l"; fi
done
if grep -iE '^Environment=.*(proxy|token)' "$U" >/dev/null; then falha "unidade: Environment com proxy/TOKEN"; else ok "unidade: sem proxy nem TOKEN no ambiente"; fi
if grep -E '^ProtectHome=' "$U" >/dev/null; then falha "unidade: ProtectHome esconderia /run/user"; else ok "unidade: sem ProtectHome"; fi
if command -v systemd-analyze >/dev/null 2>&1; then
  v=$(systemd-analyze verify "$U" 2>&1 | grep -v -e 'stack-ci-rede' -e '/usr/bin/python3' -e 'User=ci' -e 'Unit .* not found' || true)
  if [[ -z $v ]]; then ok "systemd-analyze verify"; else falha "systemd-analyze verify ($v)"; fi
fi

if grep -qE '%U|%u|@CI_UID@' "$U"; then falha "unidade instalada ainda tem %U ou @CI_UID@"; else ok "unidade instalada sem %U nem @CI_UID@"; fi
mundo; echo 1777 > "$T/uid"; bash "$S" >/dev/null 2>&1
if grep -qxF "Environment=DOCKER_HOST=unix:///run/user/1777/docker.sock" "$CI_UNIT/stack-ci-runners.service"; then ok "unidade segue o uid do ci"; else falha "unidade nao seguiu o uid 1777"; fi
if grep -qE '%U|@CI_UID@' "$RAIZ_REPO/systemd/stack-ci-runners.service" && grep -q '@CI_UID@' "$RAIZ_REPO/systemd/stack-ci-runners.service"; then ok "molde do repositorio usa @CI_UID@"; else falha "molde do repositorio"; fi

# rotacao: unidade ativa reinicia; inativa nao mexe
mundo; : > "$T/runners-ativo"
bash "$S" >/dev/null 2>&1; afirma_rc $? 0 "unidade ativa: instala"
afirma_log "systemctl restart stack-ci-runners.service" "unidade ativa: reinicia"
mundo
bash "$S" >/dev/null 2>&1
nega_log "restart" "unidade inativa: sem restart"; nega_log "start" "unidade inativa: sem start"; nega_log "enable" "unidade inativa: sem enable"

# --status: FIFO e link nao vazam nem travam (leitura sem seguir link, nao bloqueante)
mundo; mkfifo "$CI_DIR/status.json"
out=$(timeout 20 bash "$S" --status 2>&1); afirma_rc $? 0 "--status com FIFO: nao trava"
if [[ $out == *indisponivel* ]]; then ok "status: FIFO recusado"; else falha "status: FIFO ($out)"; fi
mundo; head -c 70000 /dev/zero | tr ' ' 'a' > "$CI_DIR/status.json"
out=$(bash "$S" --status 2>&1)
if [[ $out == *indisponivel* ]]; then ok "status: arquivo grande demais recusado"; else falha "status: grande ($out)"; fi

# --status como root nao segue link plantado pela conta ci
mundo; echo MARCADOR-SEGREDO > "$T/alvo"; ln -s "$T/alvo" "$CI_DIR/status.json"
out=$(bash "$S" --status 2>&1); afirma_rc $? 0 "--status com link simbolico"
if [[ $out != *MARCADOR-SEGREDO* && $out == *indisponivel* ]]; then ok "status: link nao seguido"; else falha "status: link seguido ($out)"; fi

# producao: override de ambiente e ignorado (guard extraido do script, como no teste do 38/39)
guard=$(sed -n '/^# >>> normaliza/,/^# <<< normaliza/p' "$S")
if [[ -n $guard ]]; then ok "guard encontrado"; else falha "guard encontrado"; fi
vars='$CI_ADMIN_ENV $CI_DIR $CI_CFG $CI_OPT $CI_REDE_SCRIPT $CI_UNIT $CI_PULAR_PULL $CI_RUN_USER'
r=$(env -u STACK_TESTE CI_ADMIN_ENV=/x CI_DIR=/x CI_CFG=/x CI_OPT=/x CI_REDE_SCRIPT=/x CI_UNIT=/x CI_PULAR_PULL=1 CI_RUN_USER=/x \
  bash -c "$guard"$'\necho "'"$vars"'"')
igual "$r" "/srv/dev/secrets/admin.env /srv/ci /etc/stack-ci /opt/ci /usr/local/lib/stack-vps/39-ci-rede.sh /etc/systemd/system 0 /run/user" "sem STACK_TESTE: overrides ignorados"
r=$(STACK_TESTE=1 CI_ADMIN_ENV=/a CI_DIR=/b CI_CFG=/g CI_OPT=/c CI_REDE_SCRIPT=/d CI_UNIT=/e CI_PULAR_PULL=1 CI_RUN_USER=/f \
  bash -c "$guard"$'\necho "'"$vars"'"')
igual "$r" "/a /b /g /c /d /e 1 /f" "com STACK_TESTE=1: overrides valem"
fim
