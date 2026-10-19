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
fim
