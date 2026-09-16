#!/usr/bin/env bash
# Clona os repositorios da conta nas quatro arvores, pela classificacao em docs/repos-classificacao.tsv.
# Idempotente: repo ja clonado so faz fetch. Roda como dev.
set -uo pipefail
TSV="${1:?informe o caminho do repos-classificacao.tsv}"
set -a; . /srv/dev/secrets/.env; set +a
ok=0; fail=0
while IFS=$'\t' read -r tree repo push lang kb arq; do
  [[ $tree == arvore ]] && continue
  dest="/srv/dev/repos/$tree/$repo"
  if [[ -d $dest/.git ]]; then git -C "$dest" fetch -q --all 2>/dev/null && ok=$((ok+1)) || fail=$((fail+1)); continue; fi
  if git clone -q "https://x-access-token:${GITHUB_TOKEN}@github.com/resper1965/$repo.git" "$dest" 2>/dev/null; then
    git -C "$dest" remote set-url origin "https://github.com/resper1965/$repo.git"
    ok=$((ok+1))
  else
    echo "FALHOU: $tree/$repo"; fail=$((fail+1))
  fi
done < "$TSV"
echo "clonados/atualizados: $ok | falhas: $fail"
du -sh /srv/dev/repos
