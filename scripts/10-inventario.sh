#!/usr/bin/env bash
# Inventario profundo dos repositorios clonados. Escreve /srv/dev/state/inventario.md.
# Le apenas metadado e presenca de arquivo — nao abre conteudo de codigo.
set -uo pipefail
OUT=/srv/dev/state/inventario.md
OUT_BEKAA=/srv/dev/state/inventario-bekaa.md
BEKAA_RE="bekaa|fixfacilities|OP-Gabi|portalbekaa|b.ctem|TWYN-ISO27001|lit-isms|twyn-isms|^team$|proporsal-ness|rfp-alupar|ORM-BARRADOPAR"
HOJE=$(date +%Y-%m-%d)

stack(){ local d=$1; local s=()
  # profundidade 2: monorepo com api/ e web/ nao tem manifesto na raiz
  local pkg; pkg=$(find "$d" -maxdepth 2 -name package.json -not -path '*/node_modules/*' | head -1)
  [[ -n $pkg ]] && { grep -q '"next"' "$pkg" 2>/dev/null && s+=(Next.js) || s+=(Node); }
  find "$d" -maxdepth 2 -name tsconfig.json | grep -q . && s+=(TS)
  find "$d" -maxdepth 2 \( -name pyproject.toml -o -name requirements.txt \) | grep -q . && s+=(Python)
  find "$d" -maxdepth 2 -name go.mod | grep -q . && s+=(Go)
  find "$d" -maxdepth 2 -name '*.csproj' | grep -q . && s+=(.NET)
  find "$d" -maxdepth 2 -name composer.json | grep -q . && s+=(PHP)
  find "$d" -maxdepth 2 -name Cargo.toml | grep -q . && s+=(Rust)
  find "$d" -maxdepth 2 \( -name 'docker-compose*.yml' -o -name Dockerfile \) | grep -q . && s+=(Docker)
  [[ ${#s[@]} -eq 0 ]] && echo "-" || { IFS=+; echo "${s[*]}"; }
}
tem_teste(){ local d=$1
  git -C "$d" ls-files 2>/dev/null | grep -qEi '(^|/)(tests?|__tests__|spec)/|\.(test|spec)\.[jt]sx?$|_test\.go$|test_.*\.py$' && echo sim || echo nao; }
loc(){ # wc precisa rodar DENTRO do repo: git ls-files devolve caminho relativo
  ( cd "$1" 2>/dev/null || exit 0
    git ls-files -z 2>/dev/null | grep -zEi '\.(py|js|jsx|ts|tsx|go|cs|php|rs|rb|java|sql|sh|vue|svelte)$'       | xargs -0 -r wc -l 2>/dev/null | tail -1 | awk '{print $1+0}' )
}
cabecalho(){
cat <<CAB
# $1 — $HOJE

$2

| Projeto | Arvore | Stack | Ultimo commit | LOC | Testes | CI | README | STATE | Classificacao |
|---|---|---|---|---|---|---|---|---|---|
CAB
}
cabecalho "Inventario (trilha geral)" "Escopo: ativos dos ultimos 90 dias, exceto a trilha bekaa. Ausencia de CI nao entra como recomendacao: e caso a parte, ainda nao classificado." > "$OUT"
cabecalho "Inventario (trilha bekaa)" "Repositorios da bekaa-trusted-advisors e correlatos, auditados em trilha propria." > "$OUT_BEKAA"
: <<'ANTIGO'
{
echo "# Inventario — $HOJE"
echo
echo "Escopo: repositorios ativos (push nos ultimos 90 dias) dos seis donos."
echo "Dormentes de resper1965 e o restante de nessenergy ficaram fora por decisao do Ricardo."
echo
echo "| Projeto | Arvore | Stack | Ultimo commit | LOC | Testes | CI | README | STATE | Classificacao |"
echo "|---|---|---|---|---|---|---|---|---|---|"
} > /dev/null
ANTIGO

# So o escopo: os dormentes de resper1965 estao clonados em disco mas ficam de fora
ESCOPO=/srv/dev/state/escopo-auditoria.tsv
for d in /srv/dev/repos/*/*/; do
  [[ -d $d/.git ]] || continue
  nome=$(basename "$d"); arv=$(basename "$(dirname "$d")")
  cut -f4 "$ESCOPO" | grep -qxF "$nome" || continue
  ult=$(git -C "$d" log -1 --format=%cs 2>/dev/null || echo '-')
  dias=$(( ( $(date +%s) - $(git -C "$d" log -1 --format=%ct 2>/dev/null || echo 0) ) / 86400 ))
  cls=ativo; (( dias > 90 )) && cls=dormente; (( dias > 365 )) && cls='morto?'
  ci=nao; compgen -G "$d/.github/workflows/*.y*ml" >/dev/null 2>&1 && ci=sim
  rd=nao; compgen -G "$d/README*" >/dev/null 2>&1 && rd=sim
  st=nao; [[ -f $d/STATE.md ]] && st=sim
  linha="| $nome | $arv | $(stack "$d") | $ult | $(loc "$d") | $(tem_teste "$d") | $ci | $rd | $st | $cls |"
  if echo "$nome" | grep -qiE "$BEKAA_RE"; then echo "$linha" >> "$OUT_BEKAA"; else echo "$linha" >> "$OUT"; fi
done

for f in "$OUT" "$OUT_BEKAA"; do
{
echo
echo "## Sem README"
grep '^| ' "$f" | awk -F'|' '$9 ~ /nao/ {print "- "$2}' | sed 's/ *$//'
echo
echo "## Sem teste"
grep '^| ' "$f" | awk -F'|' '$7 ~ /nao/ {print "- "$2}' | sed 's/ *$//'
echo
echo "## Sem CI — caso a parte"
echo "Registrado, nao recomendado: decisao do Ricardo de tratar isso separadamente."
grep '^| ' "$f" | awk -F'|' '$8 ~ /nao/ {print "- "$2}' | sed 's/ *$//'
} >> "$f"
done
echo "geral: $(grep -c '^| ' "$OUT") | bekaa: $(grep -c '^| ' "$OUT_BEKAA")"
