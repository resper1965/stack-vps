#!/usr/bin/env bash
# shellcheck source=tests/lib.sh
. "$(dirname "$0")/lib.sh"
S=$RAIZ_REPO/scripts/vigia-health.sh
echo "vigia-health"
prepara() { export VIGIA_ESTADO=$T/estado VIGIA_ALERTAR=$STUBS/alertar VIGIA_HEALTH=$STUBS/health; stub alertar; }
novo_tmp; prepara; stub health 1 "FALHA disco"
bash "$S" >/dev/null 2>&1; afirma_log "alertar stack: FALHA" "primeira falha: alerta"
: > "$STUB_LOG"; bash "$S" >/dev/null 2>&1; nega_log "alertar" "falha repetida: silencio"
stub health 0 "ok"; bash "$S" >/dev/null 2>&1; afirma_log "alertar stack: recuperado" "volta ao ok: alerta"
: > "$STUB_LOG"; bash "$S" >/dev/null 2>&1; nega_log "alertar" "ok repetido: silencio"
novo_tmp; prepara; stub health 0 "ok"
bash "$S" >/dev/null 2>&1; nega_log "alertar" "primeiro ok: silencio"
fim
