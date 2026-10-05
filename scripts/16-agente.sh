#!/usr/bin/env bash
# Usuario "agente" para Claude/Codex: sem sudo, sem docker do sistema, Docker rootless proprio,
# grupo "devs" com dev para repos/ e state/. data/ e forense/ ficam so com dev. Idempotente.
# Uso: sudo ./16-agente.sh   (depois de 02, 03 e 05)
set -euo pipefail
[[ $EUID -eq 0 ]] || { echo "rode como root"; exit 1; }
REPO=$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)

getent group devs >/dev/null || groupadd devs
getent group agente >/dev/null || groupadd agente
id agente &>/dev/null || adduser --disabled-password --gecos "" --ingroup agente agente
usermod -aG devs dev; usermod -aG devs agente
gpasswd -d agente sudo 2>/dev/null || true; gpasswd -d agente docker 2>/dev/null || true
grep -q '^agente:' /etc/subuid || usermod --add-subuids 200000-265535 --add-subgids 200000-265535 agente

# repos e state compartilhados (grupo devs, setgid); data e forense so do dev
for d in /srv/dev/repos /srv/dev/state; do
  chgrp -R devs "$d"; chmod -R g+rwX "$d"; find "$d" -type d -exec chmod g+s {} +
done
chmod 750 /srv/dev/data; install -d -m 750 -o dev -g dev /srv/forense
git config --system core.sharedRepository group
git config --system --get-all safe.directory 2>/dev/null | grep -qx '\*' || git config --system --add safe.directory '*'
for u in dev agente; do grep -q 'umask 002' "/home/$u/.profile" || echo 'umask 002' >> "/home/$u/.profile"; done

# dev chama o agente sem senha; o agente nao tem sudo nenhum
echo 'dev ALL=(agente) NOPASSWD: ALL' > /etc/sudoers.d/91-dev-agente
chmod 440 /etc/sudoers.d/91-dev-agente; visudo -c -q
install -m 755 "$REPO/bin/ia" /usr/local/bin/ia; ln -sf /usr/local/bin/ia /usr/local/bin/iax

# Docker rootless: o AppArmor do Ubuntu 24.04 bloqueia namespace de usuario sem este perfil
cat > /etc/apparmor.d/usr.bin.rootlesskit <<'AA'
abi <abi/4.0>,
include <tunables/global>
"/usr/bin/rootlesskit" flags=(unconfined) {
  userns,
  include if exists <local/usr.bin.rootlesskit>
}
AA
systemctl reload apparmor
loginctl enable-linger agente
U=$(id -u agente)
for _ in $(seq 1 20); do [[ -S /run/user/$U/bus ]] && break; sleep 0.5; done
# shellcheck disable=SC2016
sudo -u agente XDG_RUNTIME_DIR="/run/user/$U" DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$U/bus" \
  bash -c 'systemctl --user is-active --quiet docker || dockerd-rootless-setuptool.sh install >/dev/null'

# Node do proprio agente (o do dev mora em /home/dev, 750)
# shellcheck disable=SC2016
sudo -u agente -H bash -c '
  command -v ~/.local/bin/mise >/dev/null || curl -fsSL https://mise.run | sh >/dev/null 2>&1
  grep -q "mise activate" ~/.bashrc || echo "eval \"\$(~/.local/bin/mise activate bash)\"" >> ~/.bashrc
  ~/.local/bin/mise use -g node@lts >/dev/null 2>&1'
echo "agente: $(id agente)"
echo "docker rootless: $(sudo -u agente XDG_RUNTIME_DIR="/run/user/$U" systemctl --user is-active docker)"
