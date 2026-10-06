#!/usr/bin/env bash
# Ferramentas de base + Node LTS via mise, com Node no PATH nao interativo.
# Idempotente. Uso: sudo ./03-tooling.sh
set -euo pipefail
[[ $EUID -eq 0 ]] || { echo "rode como root"; exit 1; }
id dev &>/dev/null || { echo "rode 01-baseline.sh antes"; exit 1; }

export DEBIAN_FRONTEND=noninteractive
# unattended-upgrades costuma segurar o lock logo apos o boot
APT="apt-get -o DPkg::Lock::Timeout=600"
$APT update -qq
$APT install -y -qq git tmux ripgrep fd-find jq htop ncdu restic rclone curl unzip shellcheck uidmap slirp4netns direnv >/dev/null
ln -sf "$(command -v fdfind)" /usr/local/bin/fd

# cloudflared: o tunnel de reserva depende dele e nenhuma imagem o traz
if ! command -v cloudflared >/dev/null; then
  install -d -m 755 /usr/share/keyrings
  curl -fsSL https://pkg.cloudflare.com/cloudflare-main.gpg -o /usr/share/keyrings/cloudflare-main.gpg
  echo 'deb [signed-by=/usr/share/keyrings/cloudflare-main.gpg] https://pkg.cloudflare.com/cloudflared any main' \
    > /etc/apt/sources.list.d/cloudflared.list
  $APT update -qq && $APT install -y -qq cloudflared >/dev/null
fi

# Docker: a imagem "com Docker" da Hostinger ja traz; a pura nao. Repositorio oficial, com rootless
# (usado pelo agente) e compose.
if ! command -v docker >/dev/null; then
  install -m 0755 -d /etc/apt/keyrings
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
  # shellcheck disable=SC1091
  echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "$VERSION_CODENAME") stable" \
    > /etc/apt/sources.list.d/docker.list
  $APT update -qq
  $APT install -y -qq docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin \
    docker-ce-rootless-extras >/dev/null
  systemctl enable --now docker
fi
id -nG dev | grep -qw docker || usermod -aG docker dev

sudo -u dev bash <<'DEV'
set -e
command -v ~/.local/bin/mise >/dev/null || curl -fsSL https://mise.run | sh >/dev/null 2>&1
grep -q 'mise activate' ~/.bashrc || echo 'eval "$(~/.local/bin/mise activate bash)"' >> ~/.bashrc
~/.local/bin/mise use -g node@lts >/dev/null 2>&1
DEV

# Hooks de ciclo de vida dos plugins de skill rodam em shell nao interativo,
# que nao le .bashrc: os shims precisam estar num diretorio ja no PATH padrao.
for b in node npm npx corepack; do ln -sf /home/dev/.local/share/mise/shims/$b /usr/local/bin/$b; done

echo "node: $(sudo -u dev node --version)  docker: $(docker --version)"
