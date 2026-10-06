#!/usr/bin/env bash
# Containers (workspaces do Coder, runners) nao alcancam a tailnet nem o metadata da nuvem.
# O host ja esta protegido pelo UFW (entrada negada; 22 so na tailscale0). Aqui o que se fecha
# e o encaminhamento: sem isto um workspace de terceiro chegaria ao laptop e as outras maquinas
# da tailnet passando pela VPS. Idempotente; reaplicado pelo stack-rede-containers.service.
# Uso: sudo ./31-rede-containers.sh [--instalar]
set -euo pipefail
[[ $EUID -eq 0 || ${STACK_TESTE:-} == 1 ]] || { echo "rode como root"; exit 1; }
REPO=$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)

iptables -N DOCKER-USER 2>/dev/null || true
for destino in 100.64.0.0/10 169.254.169.254/32; do
  iptables -C DOCKER-USER -d "$destino" -j DROP 2>/dev/null || iptables -I DOCKER-USER 1 -d "$destino" -j DROP
done

if [[ ${1:-} == --instalar ]]; then
  install -m 755 "$0" /usr/local/lib/stack-vps/31-rede-containers.sh
  install -m 644 "$REPO/systemd/stack-rede-containers.service" /etc/systemd/system/
  systemctl daemon-reload; systemctl enable stack-rede-containers.service >/dev/null
fi
iptables -S DOCKER-USER
