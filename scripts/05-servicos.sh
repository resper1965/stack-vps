#!/usr/bin/env bash
# Servicos de host: tmux persistente, scripts em /srv/dev/bin, rotina semanal e backup diario.
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
REPO=$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)

# scripts de rotina do dev
install -d -m 755 -o dev -g dev /srv/dev/bin
install -m 755 -o dev -g dev "$REPO"/bin/health.sh   "$REPO"/scripts/{08-clonar-repos,09-clonar-escopo,10-inventario,11-state,12-push-state}.sh /srv/dev/bin/
install -m 755 -o dev -g dev "$REPO"/scripts/13-weekly-review.sh /srv/dev/bin/weekly-review.sh
install -m 644 -o dev -g dev "$REPO"/compose/playwright.yml /srv/dev/bin/

# rotina semanal (segunda 07:00 UTC), no crontab do dev
CRON='0 7 * * 1 /srv/dev/bin/weekly-review.sh >> /srv/dev/state/weekly.log 2>&1'
{ crontab -u dev -l 2>/dev/null | grep -v 'weekly-review.sh' || true; echo "$CRON"; } | crontab -u dev -

# backup e restore fora do /srv/dev/repos: o timer nao pode depender de um clone
install -d -m 755 /usr/local/lib/stack-vps/lib
install -m 755 "$REPO"/scripts/14-backup.sh "$REPO"/scripts/15-restore.sh /usr/local/lib/stack-vps/
install -m 644 "$REPO"/scripts/lib/restic-env.sh /usr/local/lib/stack-vps/lib/
install -m 644 "$REPO"/systemd/stack-backup.service "$REPO"/systemd/stack-backup.timer /etc/systemd/system/
systemctl daemon-reload
systemctl enable --now stack-backup.timer
echo "backup: $(systemctl list-timers stack-backup.timer --no-legend | awk '{print $1, $2, $3}')"
echo "tmux-dev: $(systemctl is-active tmux-dev)"
