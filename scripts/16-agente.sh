#!/usr/bin/env bash
# Usuario "agente": a estacao de trabalho (Ricardo + Claude/Codex). Sem sudo, sem docker do sistema,
# Docker rootless proprio, dono de repos/ e state/. O dev fica so com administracao: data/, forense/,
# admin.env e sudo — e nunca roda git onde o agente escreve (hooks e .git/config do agente rodariam
# como dev, e dai como root). Idempotente. Uso: sudo ./16-agente.sh   (depois de 02, 03 e 05)
set -euo pipefail
[[ $EUID -eq 0 ]] || { echo "rode como root"; exit 1; }
REPO=$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)

getent group agente >/dev/null || groupadd agente
id agente &>/dev/null || adduser --disabled-password --gecos "" --ingroup agente agente
# o restore pode ter recriado /home/agente com o UID antigo antes de o usuario existir
chown -R agente:agente /home/agente
gpasswd -d agente sudo 2>/dev/null || true; gpasswd -d agente docker 2>/dev/null || true
gpasswd -d agente dev 2>/dev/null || true
grep -q '^agente:' /etc/subuid || usermod --add-subuids 200000-265535 --add-subgids 200000-265535 agente

# o Ricardo entra direto como agente (ssh stack-agente, VS Code): mesma chave do dev
install -d -m 700 -o agente -g agente /home/agente/.ssh
install -m 600 -o agente -g agente /home/dev/.ssh/authorized_keys /home/agente/.ssh/authorized_keys
# PATH e Docker rootless no TOPO do .bashrc: comandos por ssh sem terminal (VS Code, scripts)
# param no "case $- in *i*" do Ubuntu e nunca chegariam ao mise activate do fim do arquivo
if ! grep -q '# stack-vps: ambiente do agente' /home/agente/.bashrc; then
  # shellcheck disable=SC2016
  sed -i '1i # stack-vps: ambiente do agente\nexport PATH="$HOME/.local/bin:$HOME/.local/share/mise/shims:$PATH"\nexport DOCKER_HOST="unix:///run/user/$(id -u)/docker.sock"\n' /home/agente/.bashrc
fi

# repos e state sao do agente; data e forense so do dev
install -d -o agente -g agente /srv/dev/verticais   # atalhos por empresa/area, refeitos pelo painel do PMO
chown -R agente:agente /srv/dev/repos /srv/dev/state /srv/dev/verticais
chmod 750 /srv/dev/data; install -d -m 750 -o dev -g dev /srv/forense

# desfaz o modelo anterior (grupo compartilhado), se existir
git config --system --unset-all safe.directory '^\*$' 2>/dev/null || true
git config --system --unset core.sharedRepository 2>/dev/null || true
for u in dev agente; do sed -i '/^umask 002$/d' "/home/$u/.profile"; done
if getent group devs >/dev/null; then
  gpasswd -d dev devs 2>/dev/null || true; gpasswd -d agente devs 2>/dev/null || true; groupdel devs
fi

# rotina semanal (segunda 07:00 UTC) roda como agente, com o token dele
CRON='0 7 * * 1 /srv/dev/bin/weekly-review.sh >> /srv/dev/state/weekly.log 2>&1'
{ crontab -u agente -l 2>/dev/null | grep -v 'weekly-review.sh' || true; echo "$CRON"; } | crontab -u agente -
{ crontab -u dev -l 2>/dev/null | grep -v 'weekly-review.sh' || true; } | crontab -u dev -

# dev chama o agente sem senha; o agente nao tem sudo nenhum
echo 'dev ALL=(agente) NOPASSWD: ALL' > /etc/sudoers.d/91-dev-agente
chmod 440 /etc/sudoers.d/91-dev-agente; visudo -c -q
install -m 755 "$REPO/bin/ia" /usr/local/bin/ia; ln -sf /usr/local/bin/ia /usr/local/bin/iax
install -m 755 "$REPO/bin/git-credential-stack" /usr/local/bin/git-credential-stack
install -m 755 "$REPO/bin/modelo" /usr/local/bin/modelo   # catalogo OpenRouter/Featherless (docs/modelos.tsv)
install -D -m 644 "$REPO/docs/modelos.tsv" /usr/local/share/stack-vps/modelos.tsv

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

# Node, uv, Terraform, gitleaks e identidade git do proprio agente (commits saem como o Ricardo) (o do dev mora em /home/dev, 750). uv na versao do CI do
# Alupdata; Terraform na versao que gravou o estado do bootstrap (versao mais velha nao le o estado).
# shellcheck disable=SC2016
sudo -u agente -H bash -c '
  command -v ~/.local/bin/mise >/dev/null || curl -fsSL https://mise.run | sh >/dev/null 2>&1
  grep -q "mise activate" ~/.bashrc || echo "eval \"\$(~/.local/bin/mise activate bash)\"" >> ~/.bashrc
  ~/.local/bin/mise use -g node@24 uv@0.5.11 terraform@1.15.8 gitleaks@8 >/dev/null 2>&1
  git config --global user.name "Ricardo Esper"; git config --global user.email resper@bekaa.eu
  git config --global credential.https://github.com.helper stack'
echo "agente: $(id agente)"
echo "docker rootless: $(sudo -u agente XDG_RUNTIME_DIR="/run/user/$U" systemctl --user is-active docker)"
