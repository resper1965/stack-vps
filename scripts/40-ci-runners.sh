#!/usr/bin/env bash
# Instala o supervisor dos runners efemeros do GitHub (ci/runners.py) para a conta "ci".
# Entradas (admin.env, lido com sed, nunca com source): RUNNER_TOKEN e CI_ORGS no formato
# org:grupo:quantidade[,org2:grupo2:quantidade2]. Grava /srv/ci/token (0400 ci:ci, nunca em argv),
# /srv/ci/config.json (0640), o pacote em /opt/ci (root, a conta ci nao altera o proprio codigo) e a
# unidade systemd. So habilita com --habilitar, e so com o isolamento de rede (39) ativo.
# Uso: sudo ./40-ci-runners.sh [--habilitar | --parar | --status]   (depois do 38 e do 39 --instalar)
# Sobrescreviveis nos testes (so com STACK_TESTE=1): CI_ADMIN_ENV, CI_DIR, CI_OPT, CI_REDE_SCRIPT,
# CI_UNIT, CI_PULAR_PULL, CI_RUN_USER.
set -euo pipefail
[[ $EUID -eq 0 || ${STACK_TESTE:-} == 1 ]] || { echo "rode como root"; exit 1; }

# Em producao o ambiente herdado (sudo -E, export vazado) e ignorado: atribui sem ler.
# >>> normaliza
if [[ ${STACK_TESTE:-} != 1 ]]; then
  CI_ADMIN_ENV=/srv/dev/secrets/admin.env; CI_DIR=/srv/ci; CI_OPT=/opt/ci
  CI_REDE_SCRIPT=/usr/local/lib/stack-vps/39-ci-rede.sh; CI_UNIT=/etc/systemd/system
  CI_PULAR_PULL=0; CI_RUN_USER=/run/user
fi
# <<< normaliza

CI_ADMIN_ENV=${CI_ADMIN_ENV:-/srv/dev/secrets/admin.env}
CI_DIR=${CI_DIR:-/srv/ci}
CI_OPT=${CI_OPT:-/opt/ci}
CI_REDE_SCRIPT=${CI_REDE_SCRIPT:-/usr/local/lib/stack-vps/39-ci-rede.sh}
CI_UNIT=${CI_UNIT:-/etc/systemd/system}
CI_PULAR_PULL=${CI_PULAR_PULL:-0}
CI_RUN_USER=${CI_RUN_USER:-/run/user}
REPO=$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)

UNIDADE=stack-ci-runners.service
IMAGEM=ghcr.io/actions/actions-runner:latest
# nivel de organizacao recusado por decisao (spec 2026-10-19-ci-sem-creditos-design.md); editar o script e o override
BLOQUEADAS=" nessenergy "

modo=${1:-}
case $modo in
  ""|--habilitar|--parar|--status) ;;
  *) echo "uso: $0 [--habilitar | --parar | --status]"; exit 2 ;;
esac

if [[ $modo == --parar ]]; then
  systemctl disable --now "$UNIDADE"
  echo "ci-runners: parado e desabilitado (arquivos mantidos)"; exit 0
fi

if [[ $modo == --status ]]; then
  est=$(systemctl is-active "$UNIDADE" 2>/dev/null || true)
  echo "unidade: ${est:-desconhecido}"
  if [[ -f $CI_DIR/status.json ]]; then
    # so contagens (o supervisor nunca grava segredo); o arquivo e da conta ci, entao sem caracteres de controle
    head -c 4096 "$CI_DIR/status.json" | tr -d '\000-\010\013-\037\177'; echo
  else
    echo "status.json ausente (o supervisor ainda nao rodou)"
  fi
  exit 0
fi

# --- pre-requisitos: tudo conferido ANTES da primeira escrita ---
if ! uid=$(id -u ci 2>/dev/null) || [[ ! $uid =~ ^[1-9][0-9]*$ ]] || (( uid < 1000 )); then
  echo "a conta ci nao existe ou tem UID invalido ('${uid:-}', esperado >= 1000); rode o 38-ci-conta.sh antes"; exit 1
fi
[[ -d $CI_DIR ]] || { echo "$CI_DIR nao existe; rode o 38-ci-conta.sh antes"; exit 1; }
[[ -r $CI_ADMIN_ENV ]] || { echo "$CI_ADMIN_ENV ilegivel ou ausente"; exit 1; }

# valor de uma chave (nome fixo) do admin.env, sem source e sem eco; aceita export e aspas
le() {
  sed -n -E "s/^[[:space:]]*(export[[:space:]]+)?$1=(.*)\$/\\2/p" "$CI_ADMIN_ENV" | tail -n 1 | tr -d '\r' |
    sed -E "s/^(['\"])(.*)\\1\$/\\2/"
}
TOKEN=$(le RUNNER_TOKEN); ORGS=$(le CI_ORGS)
[[ -n $TOKEN ]] || { echo "RUNNER_TOKEN ausente no admin.env"; exit 1; }
[[ -n $ORGS ]] || { echo "CI_ORGS ausente no admin.env (formato org:grupo:quantidade,...)"; exit 1; }
# mesmo alfabeto do supervisor; a mensagem nunca traz o valor
[[ $TOKEN =~ ^[A-Za-z0-9_]{20,255}$ ]] || { echo "RUNNER_TOKEN fora do formato esperado (20 a 255 caracteres de A-Z a-z 0-9 _)"; exit 1; }

declare -A visto=(); orgs_json=""
IFS=, read -ra itens <<<"$ORGS"
(( ${#itens[@]} > 0 )) || { echo "CI_ORGS vazio"; exit 1; }
for it in "${itens[@]}"; do
  sep=${it//[!:]/}
  [[ ${#sep} == 2 ]] || { echo "CI_ORGS: '$it' fora do formato org:grupo:quantidade"; exit 1; }
  IFS=: read -r org grupo qtd <<<"$it"
  [[ $org =~ ^[A-Za-z0-9][A-Za-z0-9-]{0,38}$ ]] || { echo "CI_ORGS: nome de organizacao invalido: '$org'"; exit 1; }
  [[ $grupo =~ ^[A-Za-z0-9\ _.-]{1,64}$ && -n ${grupo// /} ]] || { echo "CI_ORGS: grupo invalido em '$org'"; exit 1; }
  [[ $qtd =~ ^([0-9]|10)$ ]] || { echo "CI_ORGS: quantidade de '$org' deve ser inteiro de 0 a 10"; exit 1; }
  baixo=${org,,}
  [[ $BLOQUEADAS != *" $baixo "* ]] || {
    echo "CI_ORGS: nivel de organizacao nao e permitido para '$org' (ver docs/superpowers/specs/2026-10-19-ci-sem-creditos-design.md)"; exit 1; }
  [[ -z ${visto[$baixo]:-} ]] || { echo "CI_ORGS: organizacao repetida: '$org'"; exit 1; }
  visto[$baixo]=1
  orgs_json+="${orgs_json:+,}\"$org\":{\"grupo\":\"$grupo\",\"quantidade\":$qtd}"
done

cd /   # o cwd do chamador pode ser ilegivel para ci
ci_run() { sudo -u ci env XDG_RUNTIME_DIR="$CI_RUN_USER/$uid" "$@"; }
ci_run systemctl --user is-active --quiet docker || { echo "Docker rootless do ci nao esta ativo; rode o 38-ci-conta.sh"; exit 1; }

if [[ $modo == --habilitar ]]; then
  systemctl is-active --quiet stack-ci-rede.service && [[ $("$CI_REDE_SCRIPT" --status 2>/dev/null || true) == ativa ]] ||
    { echo "isolamento de rede não está ativo (stack-ci-rede.service); rode 39-ci-rede.sh --instalar"; exit 1; }
fi

# --- escrita ---
# area privada do root; o segredo so passa por redirecionamento e por arquivo, nunca por argv
stage=$(mktemp -d); trap 'rm -rf "$stage"' EXIT
( umask 077
  printf '%s' "$TOKEN" > "$stage/token"
  printf '{"imagem":"%s","cpus":"2","memoria":"4g","docker_socket":false,"orgs":{%s}}\n' "$IMAGEM" "$orgs_json" > "$stage/config.json" )
unset TOKEN

# instala ao lado e renomeia: quem le nunca ve arquivo pela metade
coloca() { install -m "$1" -o ci -g ci "$2" "$3.novo" && mv -f "$3.novo" "$3"; }
coloca 0400 "$stage/token" "$CI_DIR/token"
coloca 0640 "$stage/config.json" "$CI_DIR/config.json"

# codigo do root: a conta ci le e executa, mas nao altera
install -d -m 755 -o root -g root "$CI_OPT"
install -m 644 -o root -g root "$REPO/ci/__init__.py" "$REPO/ci/runners.py" "$CI_OPT/"
install -m 644 "$REPO/systemd/$UNIDADE" "$CI_UNIT/"
systemctl daemon-reload

# a imagem tem ~2 GB: o pull a frio estouraria o timeout de 120 s do supervisor
if [[ $CI_PULAR_PULL != 1 ]]; then
  ci_run DOCKER_HOST="unix://$CI_RUN_USER/$uid/docker.sock" docker pull "$IMAGEM" >/dev/null ||
    { echo "docker pull $IMAGEM falhou; arquivos instalados, unidade NAO habilitada"; exit 1; }
fi

if [[ $modo == --habilitar ]]; then
  systemctl enable --now "$UNIDADE"
  echo "ci-runners: instalado e habilitado"
else
  echo "ci-runners: instalado; habilite com --habilitar (exige o isolamento de rede ativo)"
fi
