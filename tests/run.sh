#!/usr/bin/env bash
# Roda o shellcheck e todos os tests/test-*.sh. Sai com 1 se algo falhar.
cd "$(dirname "$0")/.." || exit 1
shopt -s nullglob   # scripts/lib/ so passa a existir na Task 8
rc=0
echo "shellcheck"
if shellcheck -x -S warning scripts/*.sh scripts/lib/*.sh bin/*.sh bin/ia tests/*.sh >/dev/null 2>&1; then echo "  ok"; else
  shellcheck -x -S warning scripts/*.sh scripts/lib/*.sh bin/*.sh bin/ia tests/*.sh; rc=1; fi
if [[ -d pmo/tests ]]; then
  echo "pmo (python)"
  if python3 -m unittest discover -s pmo/tests -t . -q 2>"$HOME/.pmo-testes.log"; then echo "  ok"; else cat "$HOME/.pmo-testes.log"; rc=1; fi
fi
for t in tests/test-*.sh; do [[ -e $t ]] || continue; echo "$t"; bash "$t" || rc=1; done
exit $rc
