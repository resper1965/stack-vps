#!/usr/bin/env bash
# sysbox: runtime de container que permite Docker dentro do container sem modo privilegiado.
# Base dos workspaces do Coder e dos runners: o terceiro tem root no container, nao no host.
# Idempotente. Uso: sudo ./30-sysbox.sh   (antes de existir container: o pacote reinicia o Docker)
set -euo pipefail
[[ $EUID -eq 0 ]] || { echo "rode como root"; exit 1; }
VER=0.7.1
DEB=sysbox-ce_${VER}-0.linux_amd64.deb
SHA=${SYSBOX_SHA256:-9d6d5484f980d0a17f86c492c1262015c2afb66280bdb97215b79fde6a0261c5}

if ! dpkg -s sysbox-ce 2>/dev/null | grep -q "^Version: ${VER}"; then
  t=$(mktemp -d); trap 'rm -rf "$t"' EXIT
  curl -fsSL -o "$t/$DEB" "https://downloads.nestybox.com/sysbox/releases/v${VER}/${DEB}"
  got=$(sha256sum "$t/$DEB" | cut -d' ' -f1)
  [[ $got == "$SHA" ]] || { echo "SHA-256 do sysbox nao confere: $got (esperado $SHA); nada instalado"; exit 1; }
  [[ -z $(docker ps -q) ]] || { echo "ha containers rodando: o pacote reinicia o Docker; pare-os antes"; exit 1; }
  apt-get -o DPkg::Lock::Timeout=600 install -y -qq jq "$t/$DEB" >/dev/null
fi
systemctl is-active --quiet sysbox || systemctl restart sysbox
docker run --rm --runtime=sysbox-runc alpine id >/dev/null
echo "sysbox: $(systemctl is-active sysbox) | $(dpkg -s sysbox-ce | grep ^Version)"
