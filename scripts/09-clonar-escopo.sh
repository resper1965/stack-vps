#!/usr/bin/env bash
# Clona o escopo da auditoria (TSV: dono, repo, arvore, dir). Idempotente. Roda como dev.
set -uo pipefail
TSV="${1:?informe o TSV de escopo}"
set -a; . /srv/dev/secrets/.env; set +a
novo=0; atual=0; falha=0
while IFS=$'\t' read -r dono repo arvore dir; do
  [[ $dono == dono ]] && continue
  dest="/srv/dev/repos/$arvore/$dir"
  if [[ -d $dest/.git ]]; then git -C "$dest" fetch -q --all 2>/dev/null; atual=$((atual+1)); continue; fi
  if git clone -q "https://x-access-token:${GITHUB_TOKEN}@github.com/$dono/$repo.git" "$dest" 2>/dev/null; then
    git -C "$dest" remote set-url origin "https://github.com/$dono/$repo.git"; novo=$((novo+1))
  else echo "FALHOU: $dono/$repo"; falha=$((falha+1)); fi
done < "$TSV"
echo "novos: $novo | ja existiam: $atual | falhas: $falha"
