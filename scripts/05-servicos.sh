#!/usr/bin/env bash
# Servicos de host: sessao tmux persistente. Tunnel e backup entram aqui quando validados.
set -euo pipefail
[[ $EUID -eq 0 ]] || { echo "rode como root"; exit 1; }

cat > /etc/systemd/system/tmux-dev.service <<'UNIT'
[Unit]
Description=Sessao tmux persistente do usuario dev
After=network-online.target

[Service]
Type=forking
User=dev
WorkingDirectory=/srv/dev
Environment=HOME=/home/dev
ExecStart=/usr/bin/tmux new-session -d -s dev -c /srv/dev
ExecStop=/usr/bin/tmux kill-session -t dev
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
UNIT
systemctl daemon-reload
systemctl enable --now tmux-dev
echo "tmux-dev: $(systemctl is-active tmux-dev)"
