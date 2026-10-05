#!/usr/bin/env bash
# shellcheck source=tests/lib.sh
. "$(dirname "$0")/lib.sh"
S=$RAIZ_REPO/scripts/20-laptop-github.sh
echo "20-laptop-github"
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t

prepara() {
  B="$T/Área de Trabalho"; mkdir -p "$B"           # espaco e acento, como no OneDrive
  TSV=$T/migracao.tsv; printf 'origem\tcaminho\tdono\trepo\tarvore\tacao\r\n' > "$TSV"
  stub gitleaks; stub gh
}
linha() { printf 'windows\t%s\t%s\t%s\tapps\t%s\r\n' "$1" "$2" "$3" "$4" >> "$TSV"; }  # CRLF de proposito
remoto() { # remoto/<nome>.git com um commit base e clone local em "$B/<pasta>"
  git init -q --bare -b main "$T/remoto/$1.git"
  git clone -q "$T/remoto/$1.git" "$B/$2" 2>/dev/null
  git -C "$B/$2" commit -q --allow-empty -m base; git -C "$B/$2" push -q origin main 2>/dev/null; }
cabeca() { git --git-dir="$T/remoto/$1.git" rev-parse main; }
res() { cat "${TSV%.tsv}.resultado.tsv"; }

# fast-forward: sobe
novo_tmp; prepara; remoto ff "proj ff"
echo a > "$B/proj ff/a.txt"; git -C "$B/proj ff" add a.txt; git -C "$B/proj ff" commit -qm a
linha "$B/proj ff" resper1965 ff push
bash "$S" "$TSV" >/dev/null 2>&1
[[ $(cabeca ff) == $(git -C "$B/proj ff" rev-parse main) ]]; afirma $? "fast-forward: remoto recebe o commit"
res | grep -q $'^OK\tpush\tresper1965/ff'; afirma $? "fast-forward: OK no resultado"
grep -q $'^resper1965\tff\tapps\tff$' "${TSV%.tsv}.escopo-novos.tsv"; afirma $? "fast-forward: entra no escopo novo"

# divergente: nao sobe
novo_tmp; prepara; remoto dv dv
git clone -q "$T/remoto/dv.git" "$T/outro" 2>/dev/null
git -C "$T/outro" commit -q --allow-empty -m remoto; git -C "$T/outro" push -q origin main 2>/dev/null
antes=$(cabeca dv)
git -C "$B/dv" commit -q --allow-empty -m local
linha "$B/dv" resper1965 dv push
bash "$S" "$TSV" >/dev/null 2>&1
[[ $(cabeca dv) == "$antes" ]]; afirma $? "divergente: remoto intocado"
res | grep -q $'^PENDENTE\tpush\tresper1965/dv\tmain divergiu'; afirma $? "divergente: PENDENTE"

# extensao bloqueada: nao sobe
novo_tmp; prepara; remoto pdf pdf
antes=$(cabeca pdf)
echo x > "$B/pdf/laudo.PDF"; git -C "$B/pdf" add .; git -C "$B/pdf" commit -qm laudo
linha "$B/pdf" forense-io pdf push
bash "$S" "$TSV" >/dev/null 2>&1
[[ $(cabeca pdf) == "$antes" ]]; afirma $? "pdf: remoto intocado"
res | grep -q 'extensao: laudo.PDF'; afirma $? "pdf: motivo no resultado"

# gitleaks aponta segredo: nao sobe
novo_tmp; prepara; remoto sg sg; stub gitleaks 1
antes=$(cabeca sg)
git -C "$B/sg" commit -q --allow-empty -m x
linha "$B/sg" resper1965 sg push
bash "$S" "$TSV" >/dev/null 2>&1
[[ $(cabeca sg) == "$antes" ]]; afirma $? "segredo: remoto intocado"
res | grep -q 'segredo apontado pelo gitleaks'; afirma $? "segredo: motivo no resultado"

# simulacao: nada sobe
novo_tmp; prepara; remoto sim sim
antes=$(cabeca sim)
git -C "$B/sim" commit -q --allow-empty -m x
linha "$B/sim" resper1965 sim push
bash "$S" "$TSV" --simular >/dev/null 2>&1
[[ $(cabeca sim) == "$antes" ]]; afirma $? "simular: remoto intocado"
res | grep -q $'^SIMULA\tpush'; afirma $? "simular: SIMULA no resultado"

# criar: pasta sem git vira repo privado
novo_tmp; prepara
mkdir -p "$B/novo proj"; echo 'print(1)' > "$B/novo proj/main.py"
linha "$B/novo proj" bekaa-trusted-advisors novo criar
bash "$S" "$TSV" >/dev/null 2>&1
afirma_log "gh repo create bekaa-trusted-advisors/novo --private --source $B/novo proj" "criar: gh com --private"
git -C "$B/novo proj" rev-parse -q --verify HEAD >/dev/null; afirma $? "criar: commit inicial feito"

# criar com planilha: nada acontece na pasta
novo_tmp; prepara
mkdir -p "$B/prop"; echo x > "$B/prop/precos.xlsx"
linha "$B/prop" resper1965 prop criar
bash "$S" "$TSV" >/dev/null 2>&1
[[ ! -d $B/prop/.git ]]; afirma $? "criar bloqueado: pasta sem .git"
nega_log "gh repo create" "criar bloqueado: gh nao chamado"

# fica: ignorado
novo_tmp; prepara
mkdir -p "$B/lixo"; linha "$B/lixo" resper1965 lixo fica
bash "$S" "$TSV" >/dev/null 2>&1
[[ ! -s ${TSV%.tsv}.resultado.tsv ]]; afirma $? "fica: nada no resultado"
fim
