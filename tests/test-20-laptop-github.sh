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
gh_stub() { cat > "$STUBS/gh" <<'EOS'
#!/usr/bin/env bash
echo "gh $*" >> "$STUB_LOG"
src=; nome=$3
while (($#)); do [[ $1 == --source ]] && src=$2; shift; done
git init -q --bare "$STUB_REMOTOS/${nome#*/}.git" && git -C "$src" remote add origin "$STUB_REMOTOS/${nome#*/}.git"
EOS
  chmod +x "$STUBS/gh"; export STUB_REMOTOS=$T/gh; mkdir -p "$STUB_REMOTOS"; }

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
novo_tmp; prepara; gh_stub
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
# acento no nome (C1)
novo_tmp; prepara; remoto ac ac; antes=$(cabeca ac)
echo x > "$B/ac/Relatório Técnico.pdf"; git -C "$B/ac" add .; git -C "$B/ac" commit -qm r
linha "$B/ac" forense-io ac push; bash "$S" "$TSV" >/dev/null 2>&1
[[ $(cabeca ac) == "$antes" ]]; afirma $? "acento: remoto intocado"
res | grep -q 'Relatório Técnico.pdf'; afirma $? "acento: motivo com o nome real"

# arquivo commitado e apagado continua no historico (I1)
novo_tmp; prepara; mkdir -p "$B/hist"; git -C "$B/hist" init -q -b main
echo x > "$B/hist/laudo.pdf"; git -C "$B/hist" add .; git -C "$B/hist" commit -qm a
git -C "$B/hist" rm -q laudo.pdf; git -C "$B/hist" commit -qm b
linha "$B/hist" forense-io hist criar; bash "$S" "$TSV" >/dev/null 2>&1
res | grep -q $'^PENDENTE\tcriar\tforense-io/hist\textensao: laudo.pdf'; afirma $? "historico: pdf apagado bloqueia"
nega_log "gh repo create" "historico: gh nao chamado"

# node_modules sem .gitignore (I2)
novo_tmp; prepara; mkdir -p "$B/nm/node_modules/x"; echo 1 > "$B/nm/node_modules/x/i.js"; echo 1 > "$B/nm/a.js"
linha "$B/nm" resper1965 nm criar; bash "$S" "$TSV" >/dev/null 2>&1
res | grep -q 'node_modules sem .gitignore'; afirma $? "node_modules: PENDENTE"
[[ ! -d $B/nm/.git ]]; afirma $? "node_modules: pasta intocada"

# repo aninhado (I2)
novo_tmp; prepara; mkdir -p "$B/pai/filho" "$B/pai/sub"; git -C "$B/pai/filho" init -q; echo 1 > "$B/pai/a.js"; echo 1 > "$B/pai/sub/b.js"
linha "$B/pai" resper1965 pai criar; bash "$S" "$TSV" >/dev/null 2>&1
res | grep -q 'repositorio aninhado: filho/'; afirma $? "aninhado: PENDENTE so pelo repo, nao pela subpasta comum"

# git sem commit: gitleaks no modo pasta (I3)
novo_tmp; prepara; mkdir -p "$B/sc"; git -C "$B/sc" init -q -b main; echo 1 > "$B/sc/a.js"
linha "$B/sc" resper1965 sc criar; bash "$S" "$TSV" --simular >/dev/null 2>&1
afirma_log "--no-git" "git sem commit: gitleaks --no-git"

# docx e .env (I11)
novo_tmp; prepara; mkdir -p "$B/dx"; echo x > "$B/dx/proposta.docx"
linha "$B/dx" resper1965 dx criar; bash "$S" "$TSV" >/dev/null 2>&1
res | grep -q 'extensao: proposta.docx'; afirma $? "docx: bloqueado"
novo_tmp; prepara; mkdir -p "$B/ev"; echo S=1 > "$B/ev/.env"; echo x > "$B/ev/.env.example"
linha "$B/ev" resper1965 ev criar; bash "$S" "$TSV" >/dev/null 2>&1
res | grep -q 'segredo: .env$'; afirma $? ".env: bloqueado (e .env.example nao)"
# so alteracao nao commitada (I4)
novo_tmp; prepara; remoto dt dt; echo x > "$B/dt/novo.txt"
linha "$B/dt" resper1965 dt push; bash "$S" "$TSV" >/dev/null 2>&1
res | grep -q $'^PENDENTE\tpush\tresper1965/dt\talteracoes nao commitadas'; afirma $? "sujo sem commit: PENDENTE"

# ultima linha sem quebra (I5)
novo_tmp; prepara; mkdir -p "$B/ul"; echo 1 > "$B/ul/a.js"
printf 'windows\t%s\tresper1965\tul\tapps\tcriar' "$B/ul" >> "$TSV"
bash "$S" "$TSV" --simular >/dev/null 2>&1
res | grep -q 'resper1965/ul'; afirma $? "ultima linha sem quebra: processada"

# argumento errado (I6)
novo_tmp; prepara; remoto ar ar; antes=$(cabeca ar); git -C "$B/ar" commit -q --allow-empty -m x
linha "$B/ar" resper1965 ar push; bash "$S" "$TSV" --simula >/dev/null 2>&1; afirma_rc $? 1 "--simula: recusa"
[[ $(cabeca ar) == "$antes" ]]; afirma $? "--simula: nada enviado"

# criar envia todas as branches e retoma se o remoto ja existe (I7)
novo_tmp; prepara; gh_stub; mkdir -p "$B/br"; git -C "$B/br" init -q -b main
echo 1 > "$B/br/a.js"; git -C "$B/br" add .; git -C "$B/br" commit -qm a; git -C "$B/br" branch outra
linha "$B/br" resper1965 br criar; bash "$S" "$TSV" >/dev/null 2>&1
git --git-dir="$T/gh/br.git" rev-parse -q --verify outra >/dev/null; afirma $? "criar: todas as branches sobem"
git -C "$B/br" commit -q --allow-empty -m b
bash "$S" "$TSV" >/dev/null 2>&1
[[ $(git --git-dir="$T/gh/br.git" rev-parse main) == $(git -C "$B/br" rev-parse main) ]]; afirma $? "criar de novo: retoma como push"
fim
