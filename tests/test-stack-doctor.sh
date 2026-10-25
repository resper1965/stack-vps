#!/usr/bin/env bash
# shellcheck source=tests/lib.sh
. "$(dirname "$0")/lib.sh"
D=$RAIZ_REPO/bin/stack-doctor
SENT=SENTINELA-chave-que-nunca-pode-vazar-123
echo "stack-doctor (verificador de instalação completa)"

# Tudo ok por padrao; cada caso muda um fator por variavel de ambiente dos stubs ou por arquivo.
prepara() {
  DOCTOR_AGENTE=$(id -un)
  export DOCTOR_REPO=$T/repo DOCTOR_AGENTE DOCTOR_AGENTE_HOME=$T/ah DOCTOR_DEV_HOME=$T/dev DOCTOR_SRV=$T/srv
  export DOCTOR_SEGREDOS=$T/agente.env DOCTOR_CURL_BASE=http://127.0.0.1 DOCTOR_CI_DIR=$T/ci DOCTOR_UNIT_DIR=$T/units
  export DOCTOR_CODER=$T/coder DOCTOR_RUNNERS=$T/runners DOCTOR_JQ=jq
  unset STUB_BRANCH STUB_DIRTY STUB_SERVE STUB_INATIVAS STUB_SUDO_AG STUB_SUDO_ROOT STUB_PMO_GROUPS STUB_CI STUB_SYSBOX STUB_UFW STUB_SS STUB_MODELS_CODE STUB_BODY STUB_NODNS STUB_IMAGENS STUB_IPT STUB_OC STUB_GIT_FAIL STUB_UFW_RC STUB_IPT_RC STUB_KCODE DOCTOR_SS
  mkdir -p "$T/repo/scripts" "$T/repo/opencode/command" "$T/units" "$T/dev" "$T/ci"
  touch "$T/repo/scripts/41-9router.sh" "$T/repo/scripts/42-novo-projeto.py" "$T/repo/opencode/command/novo-projeto.md"
  mkdir -p "$T/srv/projetos" "$T/srv/state" "$T/srv/pareceres"; chmod 751 "$T/srv"; chmod 750 "$T/srv/projetos" "$T/srv/state" "$T/srv/pareceres"
  A=$T/ah; mkdir -p "$A/.config/9router" "$A/.config/opencode/command" "$A/.local/lib/node_modules/9router" "$A/.local/bin" "$A/.claude" "$A/.codex" "$A/.gemini/antigravity-cli"
  printf 'INITIAL_PASSWORD=x\n' > "$A/.config/9router/9router.env"; printf 'NINE_ROUTER_API_KEY=%s\n' "$SENT" > "$A/.config/9router/client.env"
  chmod 600 "$A/.config/9router/9router.env" "$A/.config/9router/client.env"
  printf '{"provider":{"9router":{"options":{"baseURL":"http://127.0.0.1:20128/v1"}}}}\n' > "$A/.config/opencode/opencode.json"
  printf -- '---\n---\n<!-- stack-vps -->\n' > "$A/.config/opencode/command/novo-projeto.md"
  printf '{\n  "version": "0.5.104"\n}\n' > "$A/.local/lib/node_modules/9router/package.json"
  for c in claude codex agy; do printf '#!/bin/sh\n' > "$A/.local/bin/$c"; chmod +x "$A/.local/bin/$c"; done
  printf 'OUTRA=1\nNINE_ROUTER_API_KEY=%s\n' "$SENT" > "$T/agente.env"
  stubs
}
stubs() {
  cat > "$STUBS/sudo" <<'S'
#!/usr/bin/env bash
echo "sudo $*" >> "$STUB_LOG"
[[ $1 == -n ]] && shift
if [[ $1 == -u ]]; then shift 2; rc=${STUB_SUDO_AG:-0}; else rc=${STUB_SUDO_ROOT:-0}; fi
[[ $rc == 0 ]] || exit "$rc"
exec "$@"
S
  cat > "$STUBS/systemctl" <<'S'
#!/usr/bin/env bash
echo "systemctl $*" >> "$STUB_LOG"
case " $* " in *" is-active "*) ;; *) exit 4 ;; esac   # so is-active e usado; outros subcomandos falham
for u in ${STUB_INATIVAS:-}; do [[ "${*: -1}" == "$u" ]] && exit 3; done
exit 0
S
  cat > "$STUBS/curl" <<'S'
#!/usr/bin/env bash
echo "curl $*" >> "$STUB_LOG"
if [[ "$*" == *"-K -"* ]]; then   # configuracao por stdin: a chave nunca esta em argv
  cfg=$(cat); out=
  while (( $# )); do [[ $1 == -o ]] && out=$2; shift; done
  if [[ $cfg == *"Bearer "* ]]; then
    if [[ -n ${STUB_BODY+x} ]]; then printf '%s' "$STUB_BODY" > "$out"; else printf '%s' '{"data":[{"id":"m1"}]}' > "$out"; fi
    printf '%s' "${STUB_KCODE:-200}"
  else printf '%s' 401; fi
  exit 0
fi
case "$*" in
  *POST*/v1/chat/completions*) printf '%s' "${STUB_MODELS_CODE:-401}" ;;
  */v1/models*) printf '%s' 200 ;;  # GET publico
  */api/health*) printf '%s' "${STUB_HEALTH:-200}" ;;
  *4096*) printf '%s' "${STUB_OC:-200}" ;;
esac
S
  cat > "$STUBS/tailscale" <<'S'
#!/usr/bin/env bash
case "$*" in
  "serve status")
    if [[ -n ${STUB_SERVE+x} ]]; then printf '%s\n' "$STUB_SERVE"; else
      printf '%s\n' 'https://vps.tail1.ts.net (tailnet only)' '|-- / proxy http://127.0.0.1:4096' '' \
        'https://vps.tail1.ts.net:8443 (tailnet only)' '|-- / proxy unix:/run/pmo/pmo.sock' '' \
        'https://vps.tail1.ts.net:20128 (tailnet only)' '|-- / proxy http://127.0.0.1:20128'
    fi ;;
  "status --json") echo '{"Self":{"DNSName":"vps.tail1.ts.net."}}' ;;
esac
S
  cat > "$STUBS/getent" <<'S'
#!/usr/bin/env bash
[[ -n ${STUB_NODNS:-} ]] && exit 2; echo "100.1.2.3 $2"
S
  cat > "$STUBS/id" <<'S'
#!/usr/bin/env bash
case "$*" in
  "-nG pmo") echo "${STUB_PMO_GROUPS:-pmo $DOCTOR_AGENTE}" ;;
  "ci") exit "${STUB_CI:-1}" ;;
  "-nG ci") echo ci ;;
  *) exec /usr/bin/id "$@" ;;
esac
S
  cat > "$STUBS/git" <<'S'
#!/usr/bin/env bash
case "$*" in
  *rev-parse*) echo "${STUB_BRANCH:-main}" ;;
  *status*) [[ -n ${STUB_GIT_FAIL:-} ]] && exit 128; printf '%s' "${STUB_DIRTY:-}" ;;
esac
S
  cat > "$STUBS/dpkg" <<'S'
#!/usr/bin/env bash
exit "${STUB_SYSBOX:-1}"
S
  cat > "$STUBS/ufw" <<'S'
#!/usr/bin/env bash
[[ -n ${STUB_UFW_RC:-} ]] && exit "$STUB_UFW_RC"
printf '%s\n' "${STUB_UFW:-Status: active
22/tcp ALLOW Anywhere}"
S
  cat > "$STUBS/docker" <<'S'
#!/usr/bin/env bash
printf '%s' "${STUB_IMAGENS:-}"
S
  cat > "$STUBS/iptables" <<'S'
#!/usr/bin/env bash
[[ -n ${STUB_IPT_RC:-} ]] && exit "$STUB_IPT_RC"
printf '%s\n' "${STUB_IPT:--A OUTPUT -j STACK-CI}"
S
  cat > "$STUBS/ss" <<'S'
#!/usr/bin/env bash
printf '%s\n' "${STUB_SS:-LISTEN 0 511 127.0.0.1:20128 0.0.0.0:*}"
S
  chmod +x "$STUBS"/*
}
roda() { saida=$(bash "$D" 2>&1 </dev/null); rc=$?; }
tem() { grep -qF -- "$1" <<<"$saida"; }
# falta_com <descricao> <trecho esperado apos FALTA> <comandos que quebram uma coisa>
falta_com() {
  novo_tmp; prepara; eval "$3"; roda
  tem "FALTA ${2//@T/$T}"; afirma "$?" "$1: FALTA"
  afirma_rc "$rc" 1 "$1: rc 1"
}

novo_tmp; prepara; roda
! tem "  FALTA "; afirma "$?" "tudo ok: zero FALTA"
afirma_rc "$rc" 0 "tudo ok: rc 0"
tem "resumo:"; afirma "$?" "rodape de resumo"
for s in código acesso permissões opencode 9router modelos clis ci restos; do
  grep -qx "$s" <<<"$saida"; afirma "$?" "secao $s"; done
! tem "$SENT"; afirma "$?" "segredo sentinela fora da saida"
nega_log "$SENT" "segredo sentinela fora de argv (log dos stubs)"

falta_com "clone fora da main" "@T/repo na branch" 'export STUB_BRANCH=feat/x'
falta_com "clone sujo" "@T/repo com alteração local" 'export STUB_DIRTY=" M x"'
falta_com "serve sem 20128" "tailscale serve sem 20128" 'export STUB_SERVE="https://vps.tail1.ts.net (tailnet only)
https://vps.tail1.ts.net:8443 (tailnet only)"'
falta_com "MagicDNS" "MagicDNS não resolve" 'export STUB_NODNS=1'
falta_com "/srv/dev 755" "@T/srv deve ser 751" 'chmod 755 "$T/srv"'
falta_com "projetos 755" "@T/srv/projetos deve ser 750" 'chmod 755 "$T/srv/projetos"'
falta_com "pareceres ausente" "@T/srv/pareceres deve ser" 'rmdir "$T/srv/pareceres"'
falta_com "pmo fora do grupo" "pmo fora do grupo" 'export STUB_PMO_GROUPS=pmo'
falta_com "unidade opencode inativa" "unidade opencode-web inativa" 'export STUB_INATIVAS=opencode-web.service'
falta_com "opencode sem resposta" "opencode não responde" 'export STUB_OC=500'
falta_com "sem jq" "jq não instalado" 'export DOCTOR_JQ=jq-que-nao-existe'
falta_com "opencode.json sem 9router" "opencode.json sem o provedor 9router" 'echo "{}" > "$T/ah/.config/opencode/opencode.json"'
falta_com "novo-projeto sem marcador" "comando /novo-projeto ausente" 'echo x > "$T/ah/.config/opencode/command/novo-projeto.md"'
falta_com "pacote 9router velho" "pacote 9router 0.5.1 " 'sed -i s/0.5.104/0.5.1/ "$T/ah/.local/lib/node_modules/9router/package.json"'
falta_com "unidade 9router inativa" "unidade 9router inativa" 'export STUB_INATIVAS=9router.service'
falta_com "9router.env 0644" "9router.env: esperado 600" 'chmod 644 "$T/ah/.config/9router/9router.env"'
falta_com "client.env ausente" "client.env:" 'rm "$T/ah/.config/9router/client.env"'
falta_com "chat sem chave 200" "POST /v1/chat/completions responde sem chave" 'export STUB_MODELS_CODE=200'
falta_com "0.0.0.0:20128" "9router escutando fora do loopback" 'export STUB_SS="LISTEN 0 511 0.0.0.0:20128 0.0.0.0:*"'
falta_com "[::]:20128" "9router escutando fora do loopback" 'export STUB_SS="LISTEN 0 511 [::]:20128 [::]:*"'
falta_com "chave ausente" "NINE_ROUTER_API_KEY ausente" 'echo OUTRA=1 > "$T/agente.env"'
falta_com "chave sem modelos" "/v1/models com a chave não lista" 'export STUB_BODY="{\"data\":[]}"'
falta_com "CLI ausente" "codex fora do PATH" 'rm "$T/ah/.local/bin/codex"'
falta_com "sysbox" "sysbox-ce ainda instalado" 'export STUB_SYSBOX=0'
falta_com ".continue" "@T/ah/.continue existe" 'mkdir "$T/ah/.continue"'
falta_com "OpenRig" "OpenRig ainda presente" 'touch "$T/ah/.local/bin/rig-dupla"'
falta_com "UFW 8080" "regra 8080 no UFW" 'export STUB_UFW="Status: active
8080/tcp ALLOW Anywhere"'
falta_com "imagem de runner" "imagem de runner" 'export STUB_IMAGENS="stack/web"'
falta_com "/srv/coder" "@T/coder existe" 'mkdir "$T/coder"'
falta_com "/srv/runners" "@T/runners existe" 'mkdir "$T/runners"'

falta_com "git status falha" "git status falhou" 'export STUB_GIT_FAIL=1'
falta_com "Funnel ligado" "tailscale serve com Funnel" 'export STUB_SERVE="https://vps.tail1.ts.net (Funnel on)
https://vps.tail1.ts.net:8443 (tailnet only)
https://vps.tail1.ts.net:20128 (tailnet only)"'
falta_com "serve sem 443" "tailscale serve sem 443" 'export STUB_SERVE="https://vps.tail1.ts.net:8443 (tailnet only)
https://vps.tail1.ts.net:20128 (tailnet only)"'
falta_com "serve sem 8443" "tailscale serve sem 8443" 'export STUB_SERVE="https://vps.tail1.ts.net (tailnet only)
https://vps.tail1.ts.net:20128 (tailnet only)"'
falta_com "pmo no grupo agente2" "pmo fora do grupo" 'export STUB_PMO_GROUPS="pmo ${DOCTOR_AGENTE}2"'
falta_com "pareceres de outro dono" "@T/srv/pareceres deve ser 750 do root" 'export DOCTOR_AGENTE=root'
falta_com "projetos de outro dono" "@T/srv/projetos deve ser 750 do root" 'export DOCTOR_AGENTE=root'
falta_com "state de outro dono" "@T/srv/state deve ser 750 do root" 'export DOCTOR_AGENTE=root'
falta_com "9router.env de outro dono" "9router.env: esperado 600 de root" 'export DOCTOR_AGENTE=root'
falta_com "9router.env e link" "9router.env: esperado" 'mv "$T/ah/.config/9router/9router.env" "$T/real.env"; ln -s "$T/real.env" "$T/ah/.config/9router/9router.env"'
falta_com "chat sem chave 000" "POST /v1/chat/completions sem chave: resposta inesperada" 'export STUB_MODELS_CODE=000'
falta_com "chat sem chave 500" "POST /v1/chat/completions sem chave: resposta inesperada" 'export STUB_MODELS_CODE=500'
falta_com "ss sem listener em 20128" "nada escutando em :20128" 'export STUB_SS="LISTEN 0 511 127.0.0.1:4096 0.0.0.0:*"'
falta_com "listener *:20128" "9router escutando fora do loopback" 'export STUB_SS="LISTEN 0 511 *:20128 *:*"'
falta_com "listener 100.x" "9router escutando fora do loopback" 'export STUB_SS="LISTEN 0 511 100.1.2.3:20128 0.0.0.0:*"'
falta_com "loopback mais 0.0.0.0" "9router escutando fora do loopback" 'export STUB_SS="LISTEN 0 511 127.0.0.1:20128 0.0.0.0:*
LISTEN 0 511 0.0.0.0:20128 0.0.0.0:*"'
falta_com "chave: 401 com a chave" "/v1/models com a chave respondeu HTTP 401" 'export STUB_KCODE=401'
falta_com "chave: 500 com a chave" "/v1/models com a chave respondeu HTTP 500" 'export STUB_KCODE=500'
falta_com "chave: 000 com a chave" "/v1/models com a chave respondeu HTTP 000" 'export STUB_KCODE=000'
falta_com "chave com export sem valor" "NINE_ROUTER_API_KEY ausente" 'echo "export NINE_ROUTER_API_KEY=" > "$T/agente.env"'
falta_com "agente.env ilegivel" "@T/agente.env ilegível" 'chmod 000 "$T/agente.env"'
# nao FALTA: ss so em [::1], export no agente.env
novo_tmp; prepara; export STUB_SS="LISTEN 0 511 [::1]:20128 [::]:*"; printf 'export NINE_ROUTER_API_KEY=%s\n' "$SENT" > "$T/agente.env"; roda
! tem "  FALTA "; afirma "$?" "so [::1] e export na chave: zero FALTA"
tem "ok    /v1/models com a chave lista modelos"; afirma "$?" "export NINE_ROUTER_API_KEY= reconhecido"
novo_tmp; prepara; export DOCTOR_SS=ss-que-nao-existe; roda
tem "pend  porta 20128: ss indisponível"; afirma "$?" "sem ss: pend"
! tem "  FALTA "; afirma "$?" "sem ss: sem FALTA"
novo_tmp; prepara; export STUB_UFW_RC=1; roda
tem "pend  UFW 8080"; afirma "$?" "ufw rc!=0: pend"
! tem "  FALTA "; afirma "$?" "ufw rc!=0: sem FALTA"
novo_tmp; prepara; export STUB_UFW="Status: inactive"; roda
tem "pend  UFW 8080"; afirma "$?" "ufw inativo: pend"
novo_tmp; prepara; export STUB_CI=0 STUB_IPT_RC=1; touch "$T/units/stack-ci-runners.service" "$T/ci/status.json"; roda
tem "pend  rede por UID: iptables"; afirma "$?" "iptables rc!=0: pend"
! tem "  FALTA "; afirma "$?" "iptables rc!=0: sem FALTA"
novo_tmp; prepara; export STUB_CI=0 STUB_IPT="-P OUTPUT ACCEPT"; touch "$T/units/stack-ci-runners.service" "$T/ci/status.json"; roda
tem "FALTA rede por UID ausente"; afirma "$?" "iptables sem STACK-CI: FALTA"
# OpenRig/rig-dupla: dev sem acesso (sem sudo) vira pend, nao ok
novo_tmp; prepara; export STUB_SUDO_AG=1; roda
tem "pend  OpenRig: rode com sudo"; afirma "$?" "OpenRig sem sudo: pend"
! tem "ok    OpenRig"; afirma "$?" "OpenRig sem sudo: nao e ok"
# segredo nunca no corpo/erro: 500 com a chave nao imprime o corpo
novo_tmp; prepara; export STUB_KCODE=500 STUB_BODY="corpo-secreto-$SENT"; roda
! tem "corpo-secreto"; afirma "$?" "HTTP 500: corpo fora da saida"

# CI: sem conta e pend; com conta, unidade inativa e FALTA, status velho e FALTA
novo_tmp; prepara; roda
tem "pend  CI ainda não instalado"; afirma "$?" "ci nao instalado: pend"
falta_com "unidade ci inativa" "stack-ci-runners instalado e inativo" 'export STUB_CI=0; touch "$T/units/stack-ci-runners.service" "$T/ci/status.json"; export STUB_INATIVAS=stack-ci-runners.service'
falta_com "status.json velho" "status.json ausente ou velho" 'export STUB_CI=0; touch "$T/units/stack-ci-runners.service"; touch -d "10 minutes ago" "$T/ci/status.json"'
falta_com "ci le projetos" "ci pode ler" 'export STUB_CI=0; chmod 755 "$T/srv/projetos"'
novo_tmp; prepara; export STUB_CI=0; touch "$T/units/stack-ci-runners.service" "$T/ci/status.json"; roda
! tem "  FALTA "; afirma "$?" "ci instalado e fresco: zero FALTA"

# sem sudo -n: o que exige agente/root vira pend, nunca FALTA nem trava
novo_tmp; prepara; export STUB_SUDO_AG=1 STUB_SUDO_ROOT=1 STUB_CI=0; touch "$T/units/stack-ci-runners.service"; roda
tem "pend  unidade opencode-web: rode com sudo"; afirma "$?" "sem sudo: opencode pend"
tem "pend  client.env: rode com sudo"; afirma "$?" "sem sudo: client.env pend"
tem "pend  UFW 8080: rode com sudo"; afirma "$?" "sem sudo: ufw pend"
tem "pend  claude, codex e agy: rode com sudo"; afirma "$?" "sem sudo: clis pend"
! tem "FALTA 9router.env"; afirma "$?" "sem sudo: sem FALTA falso por arquivo do agente"
! tem "$SENT"; afirma "$?" "sem sudo: segredo fora da saida"

# chave invalida (aspas) e recusada sem eco do valor
novo_tmp; prepara; printf 'NINE_ROUTER_API_KEY=ab"%s\n' "$SENT" > "$T/agente.env"; roda
tem "FALTA NINE_ROUTER_API_KEY com caracteres inválidos"; afirma "$?" "chave com aspas: FALTA"
! tem "$SENT"; afirma "$?" "chave invalida: valor fora da saida"

fim
