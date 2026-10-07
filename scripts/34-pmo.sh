#!/usr/bin/env bash
# Painel do PMO: pacote em /opt/pmo (dono root), painel.json em /srv/dev/state/pmo (agente, pela coleta),
# fila/log/ajustes em /var/lib/pmo e arquivo em /srv/dev/arquivo (usuario pmo, 700), servidor so na
# tailnet (100.76.167.6:8080). Servidor e executor rodam como pmo, sem privilegio; pastas do agente so
# sao mexidas COMO agente pelo pmo-pasta. Idempotente. Uso: sudo ./34-pmo.sh   (depois do 16 e do 07)
set -euo pipefail
[[ $EUID -eq 0 ]] || { echo "rode como root"; exit 1; }
REPO=$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)

id pmo >/dev/null 2>&1 || useradd --system --home-dir /var/lib/pmo --shell /usr/sbin/nologin pmo
install -d -m 755 /opt/pmo
cp -r "$REPO"/pmo/. /opt/pmo/; chown -R root:root /opt/pmo; chmod -R a+rX,go-w /opt/pmo
install -d -o agente -g agente -m 755 /srv/dev/state/pmo
install -d -o pmo -g pmo -m 700 /var/lib/pmo /var/lib/pmo/fila /srv/dev/arquivo /srv/dev/arquivo/excluidos
chown -R pmo:pmo /srv/dev/arquivo

# token do GitHub so do pmo (arquivar/excluir); sai do admin.env sem passar por argumento nem log
install -d -o root -g pmo -m 750 /etc/pmo
( umask 027; set -a; . /srv/dev/secrets/admin.env; printf '%s' "${GITHUB_TOKEN:?falta GITHUB_TOKEN no admin.env}" ) > /etc/pmo/token
chown root:pmo /etc/pmo/token; chmod 640 /etc/pmo/token

# o pmo pede ao agente as operacoes de pasta; so este comando, fixo e do root
cat > /usr/local/bin/pmo-pasta <<'SH'
#!/bin/sh
cd / && exec env PYTHONPATH=/opt /usr/bin/python3 -m pmo.pasta "$@"
SH
chmod 755 /usr/local/bin/pmo-pasta
echo 'pmo ALL=(agente) NOPASSWD: /usr/local/bin/pmo-pasta' > /etc/sudoers.d/92-pmo-pasta
chmod 440 /etc/sudoers.d/92-pmo-pasta; visudo -c -q

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
