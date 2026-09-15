#!/usr/bin/env bash
# Baseline do host: usuario dev, chave ed25519, sshd sem root/senha, fail2ban, unattended-upgrades.
# Idempotente. Uso: sudo ./01-baseline.sh "ssh-ed25519 AAAA... comentario"
set -euo pipefail

[[ $EUID -eq 0 ]] || { echo "rode como root"; exit 1; }
PUBKEY="${1:-}"
[[ -n "$PUBKEY" ]] || { echo "uso: $0 \"<chave-publica-ed25519>\""; exit 1; }
[[ "$PUBKEY" == ssh-ed25519* ]] || { echo "chave precisa ser ed25519"; exit 1; }

id dev &>/dev/null || adduser --disabled-password --gecos "" dev
usermod -aG sudo dev
getent group docker >/dev/null && usermod -aG docker dev

install -d -m 700 -o dev -g dev /home/dev/.ssh
touch /home/dev/.ssh/authorized_keys
grep -qxF "$PUBKEY" /home/dev/.ssh/authorized_keys || echo "$PUBKEY" >> /home/dev/.ssh/authorized_keys
chown dev:dev /home/dev/.ssh/authorized_keys
chmod 600 /home/dev/.ssh/authorized_keys

# trava anti-lockout: so endurece o sshd se a chave do dev estiver de fato instalada
[[ -s /home/dev/.ssh/authorized_keys ]] || { echo "authorized_keys vazio, abortando antes de fechar o root"; exit 1; }

cat > /etc/ssh/sshd_config.d/99-hardening.conf <<'EOF'
PermitRootLogin no
PasswordAuthentication no
KbdInteractiveAuthentication no
PubkeyAuthentication yes
AuthenticationMethods publickey
EOF
sshd -t
systemctl reload ssh 2>/dev/null || systemctl reload sshd

export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y -qq fail2ban unattended-upgrades

cat > /etc/fail2ban/jail.d/sshd.local <<'EOF'
[sshd]
enabled = true
backend = systemd
maxretry = 3
bantime  = 1h
EOF
systemctl enable --now fail2ban
systemctl restart fail2ban

cat > /etc/apt/apt.conf.d/20auto-upgrades <<'EOF'
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
EOF
systemctl enable --now unattended-upgrades

echo "baseline ok. Valide 'ssh dev@<host>' em OUTRA sessao antes de fechar esta."
