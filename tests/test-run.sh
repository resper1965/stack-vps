#!/usr/bin/env bash
# run.sh recusa fora do Linux (uname stubado), sem chegar a rodar testes.
. "$(dirname "$0")/lib.sh"
novo_tmp
stub uname 0 MINGW64_NT
out=$(bash "$RAIZ_REPO/tests/run.sh" 2>&1); rc=$?
afirma_rc "$rc" 2 "run.sh recusa fora do Linux"
[[ $out == *"rode na VPS ou no WSL"* ]]; afirma $? "mensagem orienta VPS ou WSL"
fim
