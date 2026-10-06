#!/usr/bin/env bash
# Envia ao GitHub o trabalho do laptop conforme o TSV de decisao (docs/migracao-laptop.tsv).
# Roda no WSL. Nunca usa force: branch divergente, segredo ou arquivo bloqueado vira PENDENTE.
# Uso: 20-laptop-github.sh <tsv> [--simular]
# TSV (tab, com cabecalho): origem caminho dono repo arvore acao   — acao: push | criar | fica
set -uo pipefail
TSV=${1:?uso: $0 <tsv> [--simular]}
SIMULAR=0
case ${2:-} in --simular) SIMULAR=1 ;; "") ;; *) echo "uso: $0 <tsv> [--simular]"; exit 1 ;; esac
(( $# <= 2 )) || { echo "uso: $0 <tsv> [--simular]"; exit 1; }
export GIT_TERMINAL_PROMPT=0
RES=${TSV%.tsv}.resultado.tsv
NOVOS=${TSV%.tsv}.escopo-novos.tsv
EXT_BLOQ='\.(pst|e01|dd|zip|7z|rar|xlsx|xls|csv|pdf|docx|doc|pptx|ppt|msg|eml|pem|key|pfx|p12)$'
MAX=$((50 * 1024 * 1024))

for c in git gitleaks; do command -v "$c" >/dev/null || { echo "falta $c"; exit 1; }; done
: > "$RES"; (( SIMULAR )) || : > "$NOVOS"

registra() { printf '%s\t%s\t%s/%s\t%s\n' "$1" "$2" "$3" "$4" "$5" | tee -a "$RES"; }
novo_escopo() { (( SIMULAR )) || printf '%s\t%s\t%s\t%s\n' "$1" "$2" "$3" "$2" >> "$NOVOS"; }

# eh_bloqueado <caminho>: rc 0 e motivo no stdout se o arquivo nao pode subir
eh_bloqueado() {
  local f=$1 base=${1##*/} min=${1,,}
  if [[ $min =~ $EXT_BLOQ ]]; then echo "extensao: $f"; return 0; fi
  if [[ $base == .env || $base == .envrc || ( $base == .env.* && $base != .env.example ) ]]; then echo "segredo: $f"; return 0; fi
  if [[ $base =~ ^id_(rsa|ed25519|ecdsa) && $base != *.pub ]]; then echo "segredo: $f"; return 0; fi
  return 1
}

# bloqueio_hist <dir> <rev-args...>: todo blob que o envio leva (historico inteiro do intervalo).
# rev-list --objects devolve o nome cru, sem o escape octal que o git usa em nomes com acento.
bloqueio_hist() {
  local d=$1 tipo tam nome; shift
  while read -r tipo tam nome; do
    [[ $tipo == blob ]] || continue
    if eh_bloqueado "$nome"; then return 0; fi
    if (( tam > MAX )); then echo "acima de 50MB: $nome"; return 0; fi
  done < <(git -C "$d" rev-list --objects "$@" | git -C "$d" cat-file --batch-check='%(objecttype) %(objectsize) %(rest)')
  return 0
}

# bloqueio_arvore <dir>: le caminhos separados por NUL (o que um "git add -A" levaria)
bloqueio_arvore() {
  local d=$1 f s
  while IFS= read -r -d '' f; do
    if [[ $f == */ ]]; then echo "repositorio aninhado: $f"; return 0; fi
    if [[ /$f == */node_modules/* || /$f == */.venv/* ]]; then echo "node_modules sem .gitignore: $f"; return 0; fi
    if eh_bloqueado "$f"; then return 0; fi
    s=$(stat -c %s "$d/$f" 2>/dev/null || echo 0)
    if (( s > MAX )); then echo "acima de 50MB: $f"; return 0; fi
  done
  return 0
}

# lista o que "git add -A" levaria, sem tocar na pasta (GIT_DIR temporario se nao for repo)
lista_add() {
  local d=$1 tmp
  if git -C "$d" rev-parse --git-dir >/dev/null 2>&1; then
    git -C "$d" ls-files -co --exclude-standard -z
  else
    tmp=$(mktemp -d); git init -q "$tmp"
    git --git-dir="$tmp/.git" --work-tree="$d" ls-files -co --exclude-standard -z
    rm -rf "$tmp"
  fi
}

sujo() { if [[ -n $(git -C "$1" status --porcelain 2>/dev/null) ]]; then echo " (ha alteracoes nao commitadas, ficaram no laptop)"; fi; }

faz_push() {
  local d=$1 dono=$2 repo=$3 arvore=$4 b ahead behind motivo enviou=0 registrou=0
  local -a range
  registra_b() { registra "$@"; registrou=1; }
  git -C "$d" rev-parse --git-dir >/dev/null 2>&1 || { registra PENDENTE push "$dono" "$repo" "nao e repositorio git"; return; }
  git -C "$d" fetch -q origin </dev/null 2>/dev/null || { registra PENDENTE push "$dono" "$repo" "fetch falhou"; return; }
  while IFS= read -r -u 4 b; do
    if git -C "$d" rev-parse -q --verify "refs/remotes/origin/$b" >/dev/null; then
      behind=$(git -C "$d" rev-list --count "$b..origin/$b")
      ahead=$(git -C "$d" rev-list --count "origin/$b..$b")
      (( ahead == 0 )) && continue
      if (( behind > 0 )); then registra_b PENDENTE push "$dono" "$repo" "$b divergiu ($ahead a frente, $behind atras)"; continue; fi
      range=("origin/$b..$b")
    else
      range=("$b" --not --remotes=origin)
      ahead=$(git -C "$d" rev-list --count "${range[@]}")
      (( ahead == 0 )) && continue
    fi
    motivo=$(bloqueio_hist "$d" "${range[@]}")
    if [[ -n $motivo ]]; then registra_b PENDENTE push "$dono" "$repo" "$b $motivo"; continue; fi
    if ! gitleaks detect --source "$d" --no-banner --redact --log-opts="${range[*]}" >/dev/null 2>&1 </dev/null; then
      registra_b PENDENTE push "$dono" "$repo" "$b segredo apontado pelo gitleaks"; continue; fi
    if (( SIMULAR )); then registra_b SIMULA push "$dono" "$repo" "$b: $ahead commit(s)$(sujo "$d")"; continue; fi
    if git -C "$d" push -q origin "refs/heads/$b:refs/heads/$b" </dev/null 2>/dev/null; then
      registra_b OK push "$dono" "$repo" "$b: $ahead commit(s)$(sujo "$d")"; enviou=1
    else registra_b PENDENTE push "$dono" "$repo" "$b push recusado"; fi
  done 4< <(git -C "$d" for-each-ref --format='%(refname:short)' refs/heads)
  if (( enviou )); then novo_escopo "$dono" "$repo" "$arvore"; fi
  if (( ! registrou )) && { [[ -n $(git -C "$d" status --porcelain 2>/dev/null) ]] || [[ -n $(git -C "$d" stash list 2>/dev/null) ]]; }; then
    registra PENDENTE push "$dono" "$repo" "alteracoes nao commitadas (ou stash) ficaram no laptop"
  fi
  return 0
}

faz_criar() {
  local d=$1 dono=$2 repo=$3 arvore=$4 motivo eh_git=0 tem_head=0
  [[ -d $d ]] || { registra PENDENTE criar "$dono" "$repo" "pasta nao existe"; return; }
  if git -C "$d" rev-parse --git-dir >/dev/null 2>&1; then
    # pasta dentro de outro repositorio: o git enxerga o pai, e o envio levaria o pai inteiro
    # --show-prefix vazio = a pasta e a raiz do repositorio (independe do formato do caminho no Windows)
    if [[ -n $(git -C "$d" rev-parse --show-prefix) ]]; then
      registra PENDENTE criar "$dono" "$repo" "pasta dentro de outro repositorio: $(git -C "$d" rev-parse --show-toplevel)"; return; fi
    eh_git=1
  fi
  if (( eh_git )) && git -C "$d" remote get-url origin >/dev/null 2>&1; then
    faz_push "$d" "$dono" "$repo" "$arvore"; return; fi
  if (( eh_git )) && git -C "$d" rev-parse -q --verify HEAD >/dev/null; then tem_head=1; fi
  if (( tem_head )); then motivo=$(bloqueio_hist "$d" --all)
  else motivo=$(lista_add "$d" | bloqueio_arvore "$d"); fi
  if [[ -n $motivo ]]; then registra PENDENTE criar "$dono" "$repo" "$motivo"; return; fi
  local -a gl=(detect --source "$d" --no-banner --redact); (( tem_head )) || gl+=(--no-git)
  gitleaks "${gl[@]}" >/dev/null 2>&1 </dev/null || { registra PENDENTE criar "$dono" "$repo" "segredo apontado pelo gitleaks"; return; }
  if (( SIMULAR )); then registra SIMULA criar "$dono" "$repo" "repo privado novo"; return; fi
  command -v gh >/dev/null || { registra PENDENTE criar "$dono" "$repo" "falta gh"; return; }
  (( eh_git )) || git -C "$d" init -q -b main
  if ! git -C "$d" rev-parse -q --verify HEAD >/dev/null; then
    if ! { git -C "$d" add -A && git -C "$d" commit -q -m "chore: importacao inicial do laptop"; }; then
      registra PENDENTE criar "$dono" "$repo" "commit inicial falhou (git user.email?)"; return; fi
  fi
  if ! gh repo create "$dono/$repo" --private --source "$d" --remote origin >/dev/null 2>&1 </dev/null; then
    registra PENDENTE criar "$dono" "$repo" "gh repo create falhou"; return; fi
  if git -C "$d" push -q -u origin --all </dev/null 2>/dev/null; then
    registra OK criar "$dono" "$repo" "repo privado criado$(sujo "$d")"; novo_escopo "$dono" "$repo" "$arvore"
  else registra PENDENTE criar "$dono" "$repo" "repo criado, push falhou: rode de novo"; fi
}

while IFS=$'\t' read -r -u 3 origem caminho dono repo arvore acao || [[ -n ${origem:-} ]]; do
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
