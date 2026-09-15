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
$APT install -y -qq git tmux ripgrep fd-find jq htop ncdu restic rclone curl unzip >/dev/null
ln -sf "$(command -v fdfind)" /usr/local/bin/fd

# Docker ja vem na imagem da Hostinger; so garante o dev no grupo
command -v docker >/dev/null || { echo "docker ausente nesta imagem"; exit 1; }
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
