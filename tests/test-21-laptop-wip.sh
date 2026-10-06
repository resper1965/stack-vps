#!/usr/bin/env bash
# shellcheck source=tests/lib.sh
. "$(dirname "$0")/lib.sh"
S=$RAIZ_REPO/scripts/21-laptop-wip.sh
echo "21-laptop-wip"
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
novo_tmp
R="$T/Área de Trabalho/proj"; mkdir -p "$R"; git -C "$R" init -q -b main
echo a > "$R/a.txt"; git -C "$R" add .; git -C "$R" commit -qm base
echo mudou > "$R/a.txt"; echo novo > "$R/novo.txt"; echo segredo > "$R/ignorado.log"; echo '*.log' > "$R/.gitignore"
antes=$(git -C "$R" status --porcelain | sort)
bash "$S" --simular "$R" >/dev/null 2>&1
git -C "$R" rev-parse -q --verify refs/heads/wip/laptop-2026-10-06 >/dev/null; [[ $? != 0 ]]; afirma $? "simular: nao cria branch"
WIP_DATA=2026-10-06 bash "$S" "$R" >/dev/null 2>&1; afirma_rc $? 0 "salva"
B=wip/laptop-2026-10-06
[[ $(git -C "$R" show "$B:a.txt") == mudou ]]; afirma $? "branch tem o arquivo alterado"
git -C "$R" show "$B:novo.txt" >/dev/null 2>&1; afirma $? "branch tem o arquivo novo"
git -C "$R" show "$B:ignorado.log" >/dev/null 2>&1; [[ $? != 0 ]]; afirma $? "respeita o .gitignore"
[[ $(git -C "$R" branch --show-current) == main ]]; afirma $? "branch atual intocada"
[[ $(git -C "$R" status --porcelain | sort) == "$antes" ]]; afirma $? "pasta de trabalho intocada"
[[ $(git -C "$R" rev-parse "$B^") == $(git -C "$R" rev-parse main) ]]; afirma $? "wip nasce do HEAD"
L="$T/limpo"; mkdir -p "$L"; git -C "$L" init -q -b main; echo a > "$L/a"; git -C "$L" add .; git -C "$L" commit -qm a
WIP_DATA=2026-10-06 bash "$S" "$L" >/dev/null 2>&1
git -C "$L" rev-parse -q --verify "refs/heads/$B" >/dev/null; [[ $? != 0 ]]; afirma $? "repo limpo: nada a salvar"
fim
