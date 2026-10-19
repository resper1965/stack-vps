#!/usr/bin/env bash
# Painel do PMO: pacote em /opt/pmo (dono root), painel.json em /srv/dev/state/pmo (agente, pela coleta),
# fila/log/ajustes em /var/lib/pmo e arquivo em /srv/dev/arquivo (usuario pmo, 700), servidor so na
# tailnet via tailscale serve -> socket Unix /run/pmo/pmo.sock (grupo pmo, 0660). Servidor e executor rodam
# como pmo, sem privilegio; pastas do agente so sao mexidas COMO agente pelo pmo-pasta.
# Idempotente. Uso: sudo ./34-pmo.sh   (depois do 16 e do 07)
# shellcheck disable=SC1090  # admin.env e lido da VPS, nao do repositorio
set -euo pipefail
[[ $EUID -eq 0 || ${STACK_TESTE:-} == 1 ]] || { echo "rode como root"; exit 1; }
# o socket nao autentica (quem o abre forja Tailscale-User-Login): se o agente entrar no grupo pmo, a acao
# deixa de depender do login da tailnet. Antes de qualquer escrita.
if id -nG agente | tr ' ' '
' | grep -qx pmo; then
  echo "agente esta no grupo pmo: remova (gpasswd -d agente pmo) antes de continuar"; exit 1
fi
REPO=$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)
ADMIN_ENV=${ADMIN_ENV:-/srv/dev/secrets/admin.env}

# pre-requisitos conferidos TODOS antes da primeira escrita (abortar no meio deixaria /opt/pmo trocado)
faltam=$( [[ -r $ADMIN_ENV ]] || { echo "$ADMIN_ENV(ilegivel)"; exit 0; }
  set +u; set -a; . "$ADMIN_ENV"
  for k in PMO_HOSTS PMO_LOGINS GITHUB_TOKEN; do [[ -n ${!k:-} ]] || printf '%s ' "$k"; done )
IP4=$(tailscale ip -4 2>/dev/null | head -1 || true)
IP6=$(tailscale ip -6 2>/dev/null | head -1 || true)
[[ -n $IP4 ]] || faltam+="tailscale-ip-4(tailscale sem IP: rode o 01b-tailscale.sh) "
[[ -z $faltam ]] || { echo "faltam pre-requisitos, nada foi alterado: $faltam"; exit 1; }
# IPs do proprio no: o servidor recusa acao cuja origem (X-Forwarded-For) seja um deles
PMO_IPS_PROPRIOS=$IP4${IP6:+,$IP6}

id pmo >/dev/null 2>&1 || useradd --system --home-dir /var/lib/pmo --shell /usr/sbin/nologin pmo
install -d -m 755 /opt/pmo
cp -r "$REPO"/pmo/. /opt/pmo/; chown -R root:root /opt/pmo; chmod -R a+rX,go-w /opt/pmo
install -d -o agente -g agente -m 755 /srv/dev/state/pmo
install -d -o pmo -g pmo -m 700 /var/lib/pmo /var/lib/pmo/fila /srv/dev/arquivo /srv/dev/arquivo/excluidos
chown -R pmo:pmo /srv/dev/arquivo

# token do GitHub so do pmo (arquivar/excluir); sai do admin.env sem passar por argumento nem log
install -d -o root -g pmo -m 750 /etc/pmo
( umask 027; set -a; . "$ADMIN_ENV"; printf '%s' "$GITHUB_TOKEN" ) > /etc/pmo/token
chown root:pmo /etc/pmo/token; chmod 640 /etc/pmo/token

# hosts aceitos, logins da tailnet que podem agir, IPs do proprio no e URL do painel (resumo semanal);
# o servidor le por EnvironmentFile (sem segredo)
( umask 027; set -a; . "$ADMIN_ENV"
  printf 'PMO_HOSTS=%s\nPMO_LOGINS=%s\nPMO_IPS_PROPRIOS=%s\nPMO_URL=https://%s/\n' \
    "$PMO_HOSTS" "$PMO_LOGINS" "$PMO_IPS_PROPRIOS" "${PMO_HOSTS%%,*}"
  # opcional: URL https do atalho "Abrir OpenCode" no painel
  [[ -z ${PMO_ATALHO_OPENCODE:-} ]] || printf 'PMO_ATALHO_OPENCODE=%s\n' "$PMO_ATALHO_OPENCODE" ) > /etc/pmo/servidor.env
chown root:pmo /etc/pmo/servidor.env; chmod 640 /etc/pmo/servidor.env
usermod -aG pmo dev

# espelho do Linear (opcional): chave e time so do pmo; unidades instaladas SEM habilitar o timer
# (a primeira carga e manual, depois da previa: pmo.linear --previa)
if ( set -a; . "$ADMIN_ENV"; [[ -n ${LINEAR_API_KEY:-} && -n ${LINEAR_TEAM_KEY:-} ]] ); then
  ( umask 027; set -a; . "$ADMIN_ENV"; printf '%s' "$LINEAR_API_KEY" ) > /etc/pmo/linear-token
  ( umask 027; set -a; . "$ADMIN_ENV"; printf '%s' "$LINEAR_TEAM_KEY" ) > /etc/pmo/linear-team
  chown root:pmo /etc/pmo/linear-token /etc/pmo/linear-team; chmod 640 /etc/pmo/linear-token /etc/pmo/linear-team
  for u in pmo-linear.service pmo-linear.timer; do install -m 644 "$REPO/systemd/$u" /etc/systemd/system/; done
else
  echo "espelho do Linear pulado: faltam LINEAR_API_KEY e LINEAR_TEAM_KEY no admin.env"
fi

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
PRIMEIRO_HOST=$(sed -n 's/^PMO_HOSTS=//p' /etc/pmo/servidor.env | cut -d, -f1)
echo "painel: $(curl -s --unix-socket /run/pmo/pmo.sock -H "Host: $PRIMEIRO_HOST" -o /dev/null -w '%{http_code}' http://localhost/) no socket /run/pmo/pmo.sock"
