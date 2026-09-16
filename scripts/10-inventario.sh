#!/usr/bin/env bash
# Inventario profundo dos repositorios clonados. Escreve /srv/dev/state/inventario.md.
# Le apenas metadado e presenca de arquivo — nao abre conteudo de codigo.
set -uo pipefail
OUT=/srv/dev/state/inventario.md
HOJE=$(date +%Y-%m-%d)

stack(){ local d=$1; local s=()
  [[ -f $d/package.json ]] && { grep -q '"next"' "$d/package.json" 2>/dev/null && s+=(Next.js) || s+=(Node); }
  [[ -f $d/tsconfig.json ]] && s+=(TS)
  { [[ -f $d/pyproject.toml ]] || [[ -f $d/requirements.txt ]]; } && s+=(Python)
  [[ -f $d/go.mod ]] && s+=(Go)
  compgen -G "$d/*.csproj" >/dev/null 2>&1 && s+=(.NET)
  [[ -f $d/composer.json ]] && s+=(PHP)
  [[ -f $d/Cargo.toml ]] && s+=(Rust)
  { [[ -f $d/docker-compose.yml ]] || [[ -f $d/compose.yml ]] || [[ -f $d/Dockerfile ]]; } && s+=(Docker)
  [[ ${#s[@]} -eq 0 ]] && echo "-" || { IFS=+; echo "${s[*]}"; }
}
tem_teste(){ local d=$1
  git -C "$d" ls-files 2>/dev/null | grep -qEi '(^|/)(tests?|__tests__|spec)/|\.(test|spec)\.[jt]sx?$|_test\.go$|test_.*\.py$' && echo sim || echo nao; }
loc(){ git -C "$1" ls-files 2>/dev/null | grep -Ei '\.(py|js|jsx|ts|tsx|go|cs|php|rs|rb|java|sql|sh)$' | tr '\n' '\0' | xargs -0 -r wc -l 2>/dev/null | tail -1 | awk '{print $1+0}'; }

{
echo "# Inventario — $HOJE"
echo
echo "Escopo: repositorios ativos (push nos ultimos 90 dias) dos seis donos."
echo "Dormentes de resper1965 e o restante de nessenergy ficaram fora por decisao do Ricardo."
echo
echo "| Projeto | Arvore | Stack | Ultimo commit | LOC | Testes | CI | README | STATE | Classificacao |"
echo "|---|---|---|---|---|---|---|---|---|---|"
} > "$OUT"

for d in /srv/dev/repos/*/*/; do
  [[ -d $d/.git ]] || continue
  nome=$(basename "$d"); arv=$(basename "$(dirname "$d")")
  ult=$(git -C "$d" log -1 --format=%cs 2>/dev/null || echo '-')
  dias=$(( ( $(date +%s) - $(git -C "$d" log -1 --format=%ct 2>/dev/null || echo 0) ) / 86400 ))
  cls=ativo; (( dias > 90 )) && cls=dormente; (( dias > 365 )) && cls='morto?'
  ci=nao; compgen -G "$d/.github/workflows/*.y*ml" >/dev/null 2>&1 && ci=sim
  rd=nao; compgen -G "$d/README*" >/dev/null 2>&1 && rd=sim
  st=nao; [[ -f $d/STATE.md ]] && st=sim
  echo "| $nome | $arv | $(stack "$d") | $ult | $(loc "$d") | $(tem_teste "$d") | $ci | $rd | $st | $cls |" >> "$OUT"
done

{
echo
echo "## Sem README"
grep '^|' "$OUT" | awk -F'|' '$9 ~ /nao/ {print "- "$2}' | sed 's/ *$//'
echo
echo "## Sem teste"
grep '^|' "$OUT" | awk -F'|' '$7 ~ /nao/ {print "- "$2}' | sed 's/ *$//'
echo
echo "## Sem CI"
grep '^|' "$OUT" | awk -F'|' '$8 ~ /nao/ {print "- "$2}' | sed 's/ *$//'
} >> "$OUT"

echo "escrito: $OUT ($(grep -c '^| ' "$OUT") linhas)"
