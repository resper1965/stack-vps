#!/usr/bin/env bash
# Painel do PMO: pacote em /opt/pmo (dono root), estado em /srv/dev/state/pmo (agente), arquivo em
# /srv/dev/arquivo (root), servidor so na tailnet (100.76.167.6:8080), coleta diaria, executor de
# 1 em 1 minuto, resumo de segunda. Idempotente. Uso: sudo ./34-pmo.sh   (depois do 16 e do 07)
set -euo pipefail
[[ $EUID -eq 0 ]] || { echo "rode como root"; exit 1; }
REPO=$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)

install -d -m 755 /opt/pmo
cp -r "$REPO"/pmo/. /opt/pmo/; chown -R root:root /opt/pmo; chmod -R a+rX /opt/pmo
install -d -o agente -g agente -m 755 /srv/dev/state/pmo /srv/dev/state/pmo/fila
install -d -m 700 /srv/dev/arquivo /srv/dev/arquivo/excluidos
for u in pmo-servidor.service pmo-coleta.service pmo-coleta.timer pmo-executor.service pmo-executor.timer \
         pmo-resumo.service pmo-resumo.timer; do
  install -m 644 "$REPO/systemd/$u" /etc/systemd/system/
done
systemctl daemon-reload
systemctl enable --now pmo-coleta.timer pmo-executor.timer pmo-resumo.timer >/dev/null
[[ -s /srv/dev/state/pmo/painel.json ]] || systemctl start pmo-coleta.service
systemctl enable pmo-servidor.service >/dev/null; systemctl restart pmo-servidor.service
sleep 2
echo "painel: $(curl -s -o /dev/null -w '%{http_code}' http://100.76.167.6:8080/) em http://100.76.167.6:8080"
