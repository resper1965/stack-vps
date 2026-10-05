#!/usr/bin/env bash
# Envia ao GitHub o trabalho do laptop conforme o TSV de decisao (docs/migracao-laptop.tsv).
# Roda no WSL. Nunca usa force: branch divergente, segredo ou arquivo bloqueado vira PENDENTE.
# Uso: 20-laptop-github.sh <tsv> [--simular]
# TSV (tab, com cabecalho): origem caminho dono repo arvore acao   — acao: push | criar | fica
set -uo pipefail
TSV=${1:?uso: $0 <tsv> [--simular]}
SIMULAR=0; [[ ${2:-} == --simular ]] && SIMULAR=1
RES=${TSV%.tsv}.resultado.tsv
NOVOS=${TSV%.tsv}.escopo-novos.tsv
EXT_BLOQ='\.(pst|e01|dd|zip|xlsx|csv|pdf)$'
MAX=$((50 * 1024 * 1024))

for c in git gitleaks; do command -v "$c" >/dev/null || { echo "falta $c"; exit 1; }; done
: > "$RES"; (( SIMULAR )) || : > "$NOVOS"

registra() { printf '%s\t%s\t%s/%s\t%s\n' "$1" "$2" "$3" "$4" "$5" | tee -a "$RES"; }
novo_escopo() { (( SIMULAR )) || printf '%s\t%s\t%s\t%s\n' "$1" "$2" "$3" "$2" >> "$NOVOS"; }

# Le caminhos no stdin e imprime o primeiro motivo de bloqueio. Com $2 (ref), mede o tamanho no git.
bloqueio() {
  local base=$1 ref=${2:-} f s
  while IFS= read -r f; do
    [[ -z $f ]] && continue
    if [[ ${f,,} =~ $EXT_BLOQ ]]; then echo "extensao: $f"; return 0; fi
    if [[ -n $ref ]]; then s=$(git -C "$base" cat-file -s "$ref:$f" 2>/dev/null || echo 0)
    else s=$(stat -c %s "$base/$f" 2>/dev/null || echo 0); fi
    if (( s > MAX )); then echo "acima de 50MB: $f"; return 0; fi
  done
  return 0
}

sujo() { if [[ -n $(git -C "$1" status --porcelain 2>/dev/null) ]]; then echo " (ha alteracoes nao commitadas, ficaram no laptop)"; fi; }

faz_push() {
  local d=$1 dono=$2 repo=$3 arvore=$4 b ahead behind motivo enviou=0
  local -a range
  git -C "$d" rev-parse --git-dir >/dev/null 2>&1 || { registra PENDENTE push "$dono" "$repo" "nao e repositorio git"; return; }
  git -C "$d" fetch -q origin </dev/null 2>/dev/null || { registra PENDENTE push "$dono" "$repo" "fetch falhou"; return; }
  while IFS= read -r -u 4 b; do
    if git -C "$d" rev-parse -q --verify "refs/remotes/origin/$b" >/dev/null; then
      behind=$(git -C "$d" rev-list --count "$b..origin/$b")
      ahead=$(git -C "$d" rev-list --count "origin/$b..$b")
      (( ahead == 0 )) && continue
      if (( behind > 0 )); then registra PENDENTE push "$dono" "$repo" "$b divergiu ($ahead a frente, $behind atras)"; continue; fi
      range=("origin/$b..$b")
    else
      range=("$b" --not --remotes=origin)
      ahead=$(git -C "$d" rev-list --count "${range[@]}")
      (( ahead == 0 )) && continue
    fi
    motivo=$(git -C "$d" log --name-only --format= "${range[@]}" | sort -u | bloqueio "$d" "$b")
    if [[ -n $motivo ]]; then registra PENDENTE push "$dono" "$repo" "$b $motivo"; continue; fi
    if ! gitleaks detect --source "$d" --no-banner --redact --log-opts="${range[*]}" >/dev/null 2>&1 </dev/null; then
      registra PENDENTE push "$dono" "$repo" "$b segredo apontado pelo gitleaks"; continue; fi
    if (( SIMULAR )); then registra SIMULA push "$dono" "$repo" "$b: $ahead commit(s)$(sujo "$d")"; continue; fi
    if git -C "$d" push -q origin "refs/heads/$b:refs/heads/$b" </dev/null 2>/dev/null; then
      registra OK push "$dono" "$repo" "$b: $ahead commit(s)$(sujo "$d")"; enviou=1
    else registra PENDENTE push "$dono" "$repo" "$b push recusado"; fi
  done 4< <(git -C "$d" for-each-ref --format='%(refname:short)' refs/heads)
  if (( enviou )); then novo_escopo "$dono" "$repo" "$arvore"; fi
  return 0
}

faz_criar() {
  local d=$1 dono=$2 repo=$3 arvore=$4 motivo eh_git=0
  [[ -d $d ]] || { registra PENDENTE criar "$dono" "$repo" "pasta nao existe"; return; }
  git -C "$d" rev-parse --git-dir >/dev/null 2>&1 && eh_git=1
  if (( eh_git )) && git -C "$d" remote get-url origin >/dev/null 2>&1; then
    registra PENDENTE criar "$dono" "$repo" "ja tem remoto: use push"; return; fi
  if (( eh_git )); then motivo=$(git -C "$d" ls-files -co --exclude-standard | bloqueio "$d")
  else motivo=$(cd "$d" && find . \( -name .git -o -name node_modules \) -prune -o -type f -print | sed 's|^\./||' | bloqueio "$d"); fi
  if [[ -n $motivo ]]; then registra PENDENTE criar "$dono" "$repo" "$motivo"; return; fi
  local -a gl=(detect --source "$d" --no-banner --redact); (( eh_git )) || gl+=(--no-git)
  gitleaks "${gl[@]}" >/dev/null 2>&1 </dev/null || { registra PENDENTE criar "$dono" "$repo" "segredo apontado pelo gitleaks"; return; }
  if (( SIMULAR )); then registra SIMULA criar "$dono" "$repo" "repo privado novo"; return; fi
  command -v gh >/dev/null || { registra PENDENTE criar "$dono" "$repo" "falta gh"; return; }
  (( eh_git )) || git -C "$d" init -q -b main
  if ! git -C "$d" rev-parse -q --verify HEAD >/dev/null; then
    git -C "$d" add -A && git -C "$d" commit -q -m "chore: importacao inicial do laptop"
  fi
  if gh repo create "$dono/$repo" --private --source "$d" --remote origin --push >/dev/null 2>&1 </dev/null; then
    registra OK criar "$dono" "$repo" "repo privado criado$(sujo "$d")"; novo_escopo "$dono" "$repo" "$arvore"
  else registra PENDENTE criar "$dono" "$repo" "gh repo create falhou"; fi
}

while IFS=$'\t' read -r -u 3 origem caminho dono repo arvore acao; do
  acao=${acao%$'\r'}
  [[ -z $origem || $origem == origem ]] && continue
  case $acao in
    push)  faz_push  "$caminho" "$dono" "$repo" "$arvore" ;;
    criar) faz_criar "$caminho" "$dono" "$repo" "$arvore" ;;
    fica)  ;;
    *) registra PENDENTE "$acao" "$dono" "$repo" "acao desconhecida" ;;
  esac
done 3< "$TSV"

echo
echo "OK: $(grep -c '^OK' "$RES") | PENDENTE: $(grep -c '^PENDENTE' "$RES") | SIMULA: $(grep -c '^SIMULA' "$RES")"
echo "resultado: $RES"
