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

# scripts de rotina: dono root. Quem roda a rotina e o agente (crontab instalado pelo 16),
# e ele nao pode alterar o que executa.
install -d -m 755 -o root -g root /srv/dev/bin
install -m 755 -o root -g root "$REPO"/bin/health.sh \
  "$REPO"/scripts/{08-clonar-repos,09-clonar-escopo,10-inventario,11-state,12-push-state}.sh /srv/dev/bin/
install -m 755 -o root -g root "$REPO"/scripts/13-weekly-review.sh /srv/dev/bin/weekly-review.sh
install -m 644 -o root -g root "$REPO"/compose/playwright.yml /srv/dev/bin/

# backup e restore fora do /srv/dev/repos: o timer nao pode depender de um clone
install -d -m 755 /usr/local/lib/stack-vps/lib
install -m 755 "$REPO"/scripts/14-backup.sh "$REPO"/scripts/15-restore.sh /usr/local/lib/stack-vps/
install -m 644 "$REPO"/scripts/lib/restic-env.sh /usr/local/lib/stack-vps/lib/
install -m 755 "$REPO"/scripts/alertar.sh "$REPO"/scripts/vigia-health.sh "$REPO"/bin/health.sh /usr/local/lib/stack-vps/
install -m 644 "$REPO"/systemd/stack-backup.service "$REPO"/systemd/stack-backup.timer \
  "$REPO"/systemd/stack-health.service "$REPO"/systemd/stack-health.timer /etc/systemd/system/
systemctl daemon-reload
systemctl enable --now stack-health.timer
# backup so com as chaves do R2 no admin.env (decisao de 05/10/2026: restic depois da migracao)
if grep -q '^R2_ACCESS_KEY_ID=.' /srv/dev/secrets/admin.env 2>/dev/null; then systemctl enable --now stack-backup.timer
else systemctl disable --now stack-backup.timer 2>/dev/null || true; fi
echo "backup: $(systemctl is-enabled stack-backup.timer 2>/dev/null || echo desligado)"
echo "tmux-dev: $(systemctl is-active tmux-dev)"
