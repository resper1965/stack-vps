#!/usr/bin/env bash
# shellcheck source=tests/lib.sh
. "$(dirname "$0")/lib.sh"
S=$RAIZ_REPO/scripts/34-pmo.sh
echo "34-pmo (guarda: agente fora do grupo pmo)"
novo_tmp
# o script escreve em /etc e /opt: o caso exercitado aborta ANTES de qualquer escrita; os stubs provam isso
for c in useradd install systemctl usermod curl cp chown; do stub "$c"; done
stub id 0 "agente dev pmo"
bash "$S" >/dev/null 2>&1; afirma_rc $? 1 "recusa quando agente esta no grupo pmo"
for c in useradd install usermod systemctl curl; do nega_log "$c " "nada executado ($c)"; done

echo "34-pmo (pre-requisitos conferidos antes de qualquer escrita)"
pre() { # admin.env com as chaves dadas; tailscale com o IP dado; agente fora do grupo pmo
  novo_tmp
  for c in useradd install systemctl usermod curl cp chown; do stub "$c"; done
  stub id 0 "agente dev"; stub tailscale 0 "$2"
  printf '%s\n' $1 > "$T/admin.env"; export ADMIN_ENV=$T/admin.env
  bash "$S" > "$T/saida" 2>&1; RC=$?; }
nada() { for c in useradd install usermod systemctl curl cp; do nega_log "$c " "$1: nada executado ($c)"; done; }

pre "GITHUB_TOKEN=x PMO_HOSTS=h:1" "100.1.1.1"; afirma_rc $RC 1 "sem PMO_LOGINS"
grep -q 'PMO_LOGINS' "$T/saida"; afirma $? "diz que falta PMO_LOGINS"; nada "sem PMO_LOGINS"
pre "PMO_HOSTS=h:1 PMO_LOGINS=a@b.c" ""; afirma_rc $RC 1 "sem GITHUB_TOKEN e sem IP da tailnet"
grep -q 'GITHUB_TOKEN' "$T/saida" && grep -q 'tailscale-ip-4' "$T/saida"; afirma $? "lista tudo o que falta numa mensagem so"; nada "varios faltando"
fim
