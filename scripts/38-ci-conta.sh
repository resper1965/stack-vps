#!/usr/bin/env bash
# Conta "ci": dona dos runners do GitHub. Usuario comum (UID >= 1000, grupo proprio, sem grupo nenhum
# extra), Docker rootless proprio e home 0700 — sem sudo, sem docker do sistema e sem ler segredo do
# dev/agente. Idempotente. Uso: sudo ./38-ci-conta.sh   (depois do 16-agente.sh, que cria o perfil AppArmor)
# Sobrescreviveis nos testes: CI_HOME, CI_SUBUID_FILE, CI_SUBGID_FILE, CI_APPARMOR, CI_RUN_USER, CI_VERIFICA.
set -euo pipefail
[[ $EUID -eq 0 || ${STACK_TESTE:-} == 1 ]] || { echo "rode como root"; exit 1; }

CI_HOME=${CI_HOME:-/srv/ci}
CI_SUBUID_FILE=${CI_SUBUID_FILE:-/etc/subuid}
CI_SUBGID_FILE=${CI_SUBGID_FILE:-/etc/subgid}
CI_APPARMOR=${CI_APPARMOR:-/etc/apparmor.d/usr.bin.rootlesskit}
CI_RUN_USER=${CI_RUN_USER:-/run/user}

# a conta nao pode ter poder: se ja existe com grupo privilegiado, para antes de mexer em qualquer coisa
if id ci &>/dev/null; then
  for g in $(id -nG ci); do
    case $g in sudo|docker|agente|pmo|dev|users)
      echo "ci esta no grupo '$g'; remova (gpasswd -d ci $g) e rode de novo"; exit 1 ;;
    esac
  done
fi

if ! id ci &>/dev/null; then
  mkdir -p "$(dirname "$CI_HOME")"
  useradd -m -U -s /bin/bash -d "$CI_HOME" ci
fi
install -d -m 700 -o ci -g ci "$CI_HOME"

# faixa de 65536 ids sem intersectar nenhuma existente; o useradd pode ja ter atribuido uma
add_sub() {
  local f=$1 fim
  touch "$f"
  grep -q '^ci:' "$f" && return 0
  fim=$(awk -F: '{e=$2+$3; if (e>m) m=e} END{print m+0}' "$f")
  (( fim >= 100000 )) || fim=100000
  echo "ci:$fim:65536" >> "$f"
}
add_sub "$CI_SUBUID_FILE"; add_sub "$CI_SUBGID_FILE"

# perfil criado pelo 16-agente.sh: aqui so se confere, nunca se reescreve
[[ -e $CI_APPARMOR ]] || echo "AVISO: $CI_APPARMOR ausente; rode o 16-agente.sh (sem ele o Docker rootless falha no Ubuntu 24.04)"

loginctl enable-linger ci
U=$(id -u ci)
for _ in $(seq 1 30); do [[ -d $CI_RUN_USER/$U ]] && break; sleep 0.5; done
ci_run() { sudo -u ci env XDG_RUNTIME_DIR="/run/user/$U" DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$U/bus" "$@"; }
ci_run systemctl --user is-active --quiet docker || ci_run dockerd-rootless-setuptool.sh install >/dev/null
ci_run systemctl --user is-active --quiet docker || { echo "Docker rootless do ci nao ficou ativo"; exit 1; }

if [[ ${CI_VERIFICA:-1} != 0 ]]; then
  for f in agente admin; do
    sudo -u ci test ! -r "/srv/dev/secrets/$f.env" || { echo "ci le /srv/dev/secrets/$f.env: permissao errada"; exit 1; }
  done
fi

echo "ci: $(id ci)"
echo "home: $CI_HOME"
echo "subuid: $(grep '^ci:' "$CI_SUBUID_FILE")"
echo "docker rootless: ativo"
