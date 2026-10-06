#!/usr/bin/env bash
# shellcheck source=tests/lib.sh
. "$(dirname "$0")/lib.sh"
S=$RAIZ_REPO/scripts/vigia-health.sh
echo "vigia-health"
prepara() { export VIGIA_ESTADO=$T/estado VIGIA_ALERTAR=$STUBS/alertar VIGIA_HEALTH=$STUBS/health VIGIA_TIMEOUT=3; stub alertar; }
health() { # health <rc> <linhas...>
  local rc=$1; shift
  { echo '#!/usr/bin/env bash'; for l in "$@"; do printf 'echo %q\n' "$l"; done; echo "exit $rc"; } > "$STUBS/health"
  chmod +x "$STUBS/health"; }

novo_tmp; prepara; health 1 "  FALHA reboot pendente"
bash "$S" >/dev/null 2>&1; afirma_log "alertar stack: FALHA" "primeira falha: alerta"
: > "$STUB_LOG"; bash "$S" >/dev/null 2>&1; nega_log "alertar" "falha repetida: silencio"
health 1 "  FALHA reboot pendente" "  FALHA cloudflared parado"
bash "$S" >/dev/null 2>&1; afirma_log "cloudflared parado" "falha nova sobre falha cronica: alerta (I-B)"
health 0 "ok"; : > "$STUB_LOG"; bash "$S" >/dev/null 2>&1; afirma_log "alertar stack: recuperado" "volta ao ok: alerta"
: > "$STUB_LOG"; bash "$S" >/dev/null 2>&1; nega_log "alertar" "ok repetido: silencio"

novo_tmp; prepara; health 0 "ok"
bash "$S" >/dev/null 2>&1; nega_log "alertar" "primeiro ok: silencio"

novo_tmp; prepara; stub alertar 1; health 1 "  FALHA disco"
bash "$S" >/dev/null 2>&1; : > "$STUB_LOG"; stub alertar 0
bash "$S" >/dev/null 2>&1; afirma_log "alertar stack: FALHA" "entrega falhou: tenta de novo na rodada seguinte (I-C)"

novo_tmp; prepara; printf '#!/usr/bin/env bash\nsleep 30\n' > "$STUBS/health"; chmod +x "$STUBS/health"
bash "$S" >/dev/null 2>&1; afirma_log "health travou" "health travado: vira falha (I-D)"
fim
