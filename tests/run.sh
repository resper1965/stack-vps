#!/usr/bin/env bash
# Roda o shellcheck e todos os tests/test-*.sh. Sai com 1 se algo falhar.
cd "$(dirname "$0")/.." || exit 1
shopt -s nullglob   # scripts/lib/ so passa a existir na Task 8
rc=0
echo "shellcheck"
if shellcheck -x -S warning scripts/*.sh scripts/lib/*.sh bin/*.sh tests/*.sh >/dev/null 2>&1; then echo "  ok"; else
  shellcheck -x -S warning scripts/*.sh scripts/lib/*.sh bin/*.sh tests/*.sh; rc=1; fi
for t in tests/test-*.sh; do [[ -e $t ]] || continue; echo "$t"; bash "$t" || rc=1; done
exit $rc
