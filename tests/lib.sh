# Utilitarios dos testes: raiz temporaria, stubs no PATH e asserts. Fonte: . tests/lib.sh
# shellcheck shell=bash disable=SC2034  # variaveis usadas pelos testes que fazem source
set -uo pipefail
RAIZ_REPO=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
PATH_ORIGINAL=$PATH
falhas=0

# Cada caso comeca do zero: PATH limpo de stubs anteriores e log vazio.
novo_tmp() {
  T=$(mktemp -d); STUBS=$T/stubs; mkdir -p "$STUBS"
  export STUB_LOG=$T/stub.log; : > "$STUB_LOG"
  export PATH="$STUBS:$PATH_ORIGINAL" STACK_TESTE=1 STACK_ENV=$T/sem-env
}

# stub <nome> [codigo-de-saida] [saida]: registra "nome args" no STUB_LOG
stub() {
  local n=$1 rc=${2:-0} out=${3:-}
  { echo '#!/usr/bin/env bash'
    echo "echo \"$n \$*\" >> \"\$STUB_LOG\""
    [[ -n $out ]] && printf 'echo %q\n' "$out"
    echo "exit $rc"; } > "$STUBS/$n"
  chmod +x "$STUBS/$n"
}

ok()    { printf '  ok    %s\n' "$1"; }
falha() { printf '  FALHA %s\n' "$1"; falhas=$((falhas+1)); }
afirma_rc()  { if [[ $1 == "$2" ]]; then ok "$3"; else falha "$3 (rc esperado $2, veio $1)"; fi; }
afirma_log() { if grep -qF -- "$1" "$STUB_LOG"; then ok "$2"; else falha "$2 (sem '$1' no log)"; fi; }
nega_log()   { if grep -qF -- "$1" "$STUB_LOG"; then falha "$2 (achei '$1' no log)"; else ok "$2"; fi; }
afirma()     { if [[ $1 == 0 ]]; then ok "$2"; else falha "$2"; fi; }
fim() { exit $(( falhas > 0 )); }
