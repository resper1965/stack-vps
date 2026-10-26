#!/usr/bin/env bash
# shellcheck source=tests/lib.sh
. "$(dirname "$0")/lib.sh"
J=$RAIZ_REPO/bin/stack-job
SENT=SENTINELA-segredo-que-nunca-pode-vazar-987
REAL_PY=$(command -v python3)
echo "stack-job (executor de jobs agendados)"

# Mundo falso em $T: jobs, estado, clone, segredos e alertar sao stubs/pastas temporarias.
mundo() {
  novo_tmp
  export JOBS_DIR=$T/jobs STATE_DIR=$T/state WORK_DIR=$T/work SECRETS_DIR=$T/secrets ALERTAR=$STUBS/alertar
  JOB_SECRETS_DONO=$(id -un)
  export JOB_TIMEOUT_UNIT=s JOB_SECRETS_DONO CLONE_CMD=$STUBS/clona
  mkdir -p "$JOBS_DIR/bin" "$SECRETS_DIR"
  stub alertar
  printf '#!/usr/bin/env bash
echo "alertar $*" >> "$STUB_LOG"
echo "alertar_env=${ALERTA_ENV:-}" >> "$STUB_LOG"
exit 0
' > "$STUBS/alertar"; chmod +x "$STUBS/alertar"
  export AVISO_ENV=$T/aviso.env
  # clone falso: cria o destino com um arquivo marcador (a falha liga por CLONE_FALHA)
  printf '#!/usr/bin/env bash\necho "clona $*" >> "$STUB_LOG"\n[[ -n ${CLONE_FALHA:-} ]] && exit 1\nmkdir -p "$2" && echo x > "$2/marcador"\n' > "$STUBS/clona"
  # python3 que registra o argv (prova de que nenhum segredo passa por argumento) e delega ao real
  printf '#!/usr/bin/env bash\necho "python3 $*" >> "$STUB_LOG"\nexec %s "$@"\n' "$REAL_PY" > "$STUBS/python3"
  chmod +x "$STUBS/clona" "$STUBS/python3"
}
# job <nome> <script-do-comando> [linhas extras do .job]: cria jobs/bin/<nome>.sh e jobs/<nome>.job
job() {
  local n=$1; printf '#!/usr/bin/env bash\n%s\n' "$2" > "$JOBS_DIR/bin/$n.sh"; chmod +x "$JOBS_DIR/bin/$n.sh"
  printf 'DESCRICAO=Teste %s\nAGENDA=daily\nCOMANDO=jobs/bin/%s.sh\nTIMEOUT_MIN=1\n%s\n' "$n" "$n" "${3:-}" > "$JOBS_DIR/$n.job"
}
roda() { saida=$("$J" "$@" 2>&1); rc=$?; }
campo() { "$REAL_PY" -I -c 'import json,sys; print(json.load(open(sys.argv[1]))[sys.argv[2]])' "$STATE_DIR/$1.json" "$2"; }
nada_vazou() { # <rotulo>: o sentinela nao esta na saida, no log, no json nem nos argv dos stubs
  ! grep -qF -- "$SENT" <<<"$saida"; afirma "$?" "$1: fora da saida"
  ! grep -rqF -- "$SENT" "$STATE_DIR"; afirma "$?" "$1: fora do log e do json"
  nega_log "$SENT" "$1: fora do argv (alertar, python3)"
}

# --- nome e parse estrito ---
mundo; job a 'echo oi'
for n in "A" "a/b" ".." "a b" "a;b" "a_b"; do
  roda "$n"; afirma_rc "$rc" 2 "nome invalido '$n': recusa"; done
roda; afirma_rc "$rc" 2 "sem nome: recusa"
if [[ ! -e $STATE_DIR/a.json ]]; then ok "recusa nao grava estado"; else falha "recusa nao grava estado"; fi

recusa() { # <descricao> <conteudo do .job>: o comando nao pode ter rodado
  mundo; job a "touch '$T/rodou'"; printf '%b' "$2" > "$JOBS_DIR/a.job"; roda a
  afirma_rc "$rc" 2 "parse: $1"; if [[ ! -e $T/rodou ]]; then ok "parse: $1: nada executado"; else falha "parse: $1: nada executado"; fi; }
B='DESCRICAO=x\nAGENDA=daily\nCOMANDO=jobs/bin/a.sh\nTIMEOUT_MIN=1\n'
recusa "chave desconhecida" "${B}FOO=bar\n"
recusa "chave repetida" "${B}TIMEOUT_MIN=2\n"
recusa "linha malformada" "${B}isto nao e par\n"
recusa "substituicao de comando" "${B}REPO=a\$(id)/b\n"
recusa "crase na descricao" 'DESCRICAO=`id`\nAGENDA=daily\nCOMANDO=jobs/bin/a.sh\nTIMEOUT_MIN=1\n'
recusa "comando fora de jobs/bin" 'DESCRICAO=x\nAGENDA=daily\nCOMANDO=/bin/true\nTIMEOUT_MIN=1\n'
recusa "comando em outra pasta" 'DESCRICAO=x\nAGENDA=daily\nCOMANDO=scripts/45-jobs.sh\nTIMEOUT_MIN=1\n'
recusa "comando com .." 'DESCRICAO=x\nAGENDA=daily\nCOMANDO=jobs/bin/../../bin/stack-job\nTIMEOUT_MIN=1\n'
recusa "argumento com .." 'DESCRICAO=x\nAGENDA=daily\nCOMANDO=jobs/bin/a.sh ../x\nTIMEOUT_MIN=1\n'
recusa "comando com ;" 'DESCRICAO=x\nAGENDA=daily\nCOMANDO=jobs/bin/a.sh; id\nTIMEOUT_MIN=1\n'
recusa "sem TIMEOUT_MIN" 'DESCRICAO=x\nAGENDA=daily\nCOMANDO=jobs/bin/a.sh\n'
recusa "TIMEOUT_MIN zero" "${B/TIMEOUT_MIN=1/TIMEOUT_MIN=0}"
recusa "HABILITADO invalido" "${B}HABILITADO=talvez\n"
recusa "REPO com .." "${B}REPO=a/..\n"
recusa "SEGREDOS com caminho" "${B}SEGREDOS=../x\n"
mundo; job a 'echo oi'; rm "$JOBS_DIR/bin/a.sh"; roda a; afirma_rc "$rc" 2 "parse: comando inexistente"
mundo; job a 'echo oi'; chmod -x "$JOBS_DIR/bin/a.sh"; roda a; afirma_rc "$rc" 2 "parse: comando sem permissao de execucao"

# --- caminho feliz ---
mundo; job a 'echo oi; echo ate-logo; pwd > "'"$T"'/cwd"'; roda a
afirma_rc "$rc" 0 "ok: rc 0"
if [[ $(campo a rc) == 0 ]]; then ok "ok: json com rc 0"; else falha "ok: json com rc 0"; fi
(( $(campo a fim) >= $(campo a inicio) )); afirma "$?" "ok: json com inicio e fim"
grep -qF "ate-logo" "$STATE_DIR/a.log" && grep -qF "ate-logo" <<<"$(campo a resumo)"; afirma "$?" "ok: log e resumo com a saida"
if [[ $(cat "$T/cwd") == "$WORK_DIR/a" ]]; then ok "ok: o comando roda no diretorio de trabalho"; else falha "ok: o comando roda no diretorio de trabalho"; fi
if [[ ! -e $WORK_DIR/a ]]; then ok "ok: diretorio de trabalho apagado"; else falha "ok: diretorio de trabalho apagado"; fi
nega_log "alertar" "ok: sem alerta"
# resumo: so as 3 ultimas linhas
mundo; job a 'printf "l1\nl2\nl3\nl4\n"'; roda a
r=$(campo a resumo); if [[ $r == "l2 | l3 | l4" ]]; then ok "resumo: 3 ultimas linhas"; else falha "resumo: 3 ultimas linhas"; fi

# --- clone ---
mundo; job a 'test -f marcador && echo clone-presente; echo "$PWD" > "'"$T"'/cwd"' 'REPO=resper1965/projeto-x'; roda a
afirma_rc "$rc" 0 "clone: ok"
afirma_log "clona resper1965/projeto-x $WORK_DIR/a" "clone: repo e destino certos"
grep -qF clone-presente "$STATE_DIR/a.log"; afirma "$?" "clone: comando ve o clone"
if [[ ! -e $WORK_DIR/a ]]; then ok "clone: apagado ao final"; else falha "clone: apagado ao final"; fi
mundo; job a 'echo nao-devia-rodar > "'"$T"'/rodou"' 'REPO=resper1965/projeto-x'; export CLONE_FALHA=1; roda a
if [[ $rc != 0 && ! -e $T/rodou ]]; then ok "clone falho: nao executa o comando"; else falha "clone falho: nao executa o comando"; fi
afirma_log "alertar job falhou a rc=1" "clone falho: alerta"
unset CLONE_FALHA
mundo; job a 'exit 0' 'REPO=resper1965/projeto-x'; mkdir -p "$WORK_DIR/a"; echo velho > "$WORK_DIR/a/velho"; roda a
afirma_rc "$rc" 0 "clone: sobra de execucao anterior nao atrapalha"
if [[ ! -e $WORK_DIR/a ]]; then ok "clone: sobra apagada"; else falha "clone: sobra apagada"; fi
# o clone real usa o git-credential-stack, sem token na linha de comando
grep -q 'credential.helper=\$REPO_DIR/bin/git-credential-stack' "$J"; afirma "$?" "clone real: git-credential-stack"
! grep -qE 'x-access-token|GITHUB_TOKEN' "$J"; afirma "$?" "clone real: nenhum token no script"

# --- falha e alerta ---
mundo; job a 'echo quebrou; exit 3'; roda a
afirma_rc "$rc" 3 "falha: rc propagado"
if [[ $(campo a rc) == 3 ]]; then ok "falha: json com rc 3"; else falha "falha: json com rc 3"; fi
afirma_log "alertar job falhou a rc=3" "falha: alertar chamado com titulo e mensagem"
afirma_log "alertar_env=$AVISO_ENV" "falha: alerta usa o aviso.env (o agente nao le o admin.env)"

# --- rc 10: achados nao sao falha ---
mundo; job a 'echo achou-coisa; exit 10'; roda a
afirma_rc "$rc" 0 "achados: stack-job sai 0"
if [[ $(campo a rc) == 0 && $(campo a achados) == 1 ]]; then ok "achados: json rc 0 e achados 1"; else falha "achados: json rc 0 e achados 1"; fi
afirma_log "alertar job com achados a achados (ver /srv/dev/state/jobs/a.log)" "achados: alerta proprio"
nega_log "falhou" "achados: sem alerta de falha"
mundo; job a 'echo oi'; roda a
if [[ $(campo a achados) == 0 ]]; then ok "limpo: achados 0"; else falha "limpo: achados 0"; fi
mundo; job a 'exit 3'; roda a
if [[ $(campo a achados) == 0 && $(campo a rc) == 3 ]]; then ok "rc 3: achados 0 e rc 3"; else falha "rc 3: achados 0 e rc 3"; fi
nega_log "com achados" "rc 3: sem alerta de achados"

# --- timeout ---
mundo; job a 'exec sleep 30'; ini=$SECONDS; roda a
if [[ $(campo a rc) == 124 ]]; then ok "timeout: rc 124"; else falha "timeout: rc 124"; fi
(( SECONDS - ini < 20 )); afirma "$?" "timeout: nao esperou o comando"
afirma_log "alertar job falhou a rc=124" "timeout: alerta"

# --- segredos ---
seg() { printf '%b' "$1" > "$SECRETS_DIR/s.env"; chmod "${2:-640}" "$SECRETS_DIR/s.env"; }
mundo; job a 'echo "valor=$TOKEN"; echo "$TOKEN" >&2; printf "%s" "$OUTRO" > "'"$T"'/outro"; echo "$#" > "'"$T"'/argc"; echo "${#TOKEN}" > "'"$T"'/len"; exit 5' 'SEGREDOS=s'
seg "# comentario\nTOKEN=$SENT\nexport OUTRO='com espaco'\n"; roda a
afirma_rc "$rc" 5 "segredo: comando rodou (rc proprio)"
if [[ $(cat "$T/len") == "${#SENT}" && $(cat "$T/outro") == "com espaco" ]]; then ok "segredo: comando recebe CHAVE=VALOR no ambiente"; else falha "segredo: comando recebe CHAVE=VALOR no ambiente"; fi
grep -qF '***' "$STATE_DIR/a.log"; afirma "$?" "segredo: valor trocado por *** no log"
nada_vazou "segredo impresso pelo comando"
if [[ $(campo a rc) == 5 ]]; then ok "segredo: json normal"; else falha "segredo: json normal"; fi
! (env | grep -qF -- "$SENT"); afirma "$?" "segredo: nao vaza para o ambiente do chamador"

recusa_seg() { # <descricao> <conteudo> <modo> [acao pre-roda]
  mundo; job a "touch '$T/rodou'" 'SEGREDOS=s'; seg "$2" "$3"; [[ -z ${4:-} ]] || eval "$4"; roda a
  if [[ $rc != 0 && ! -e $T/rodou ]]; then ok "segredos: $1: recusa e nao executa"; else falha "segredos: $1: recusa e nao executa"; fi
  afirma_log "alertar job falhou a rc=" "segredos: $1: alerta"
  ! grep -qF -- "$SENT" <<<"$saida"; afirma "$?" "segredos: $1: sem valor na saida"
  ! grep -rqF -- "$SENT" "$STATE_DIR"; afirma "$?" "segredos: $1: sem valor no estado"; }
recusa_seg "modo 0644" "TOKEN=$SENT\n" 644
recusa_seg "modo 0660" "TOKEN=$SENT\n" 660
recusa_seg "dono errado" "TOKEN=$SENT\n" 640 'export JOB_SECRETS_DONO=ninguem-assim'
recusa_seg "link simbolico" "TOKEN=$SENT\n" 640 'mv "$SECRETS_DIR/s.env" "$T/real.env"; ln -s "$T/real.env" "$SECRETS_DIR/s.env"'
recusa_seg "linha malformada" "TOKEN=$SENT\nisto nao e par $SENT\n" 640
recusa_seg "linha com comando" "TOKEN=\$(id)$SENT\nlixo\n" 640
recusa_seg "chave PATH" "PATH=/tmp/$SENT\n" 640
recusa_seg "arquivo ausente" "" 640 'rm "$SECRETS_DIR/s.env"'
mundo; job a 'echo "${TOKEN:-vazio}"' 'SEGREDOS=s'; seg "TOKEN=\$(id)\n"; roda a
grep -qF '$(id)' "$STATE_DIR/a.log" || grep -qF '***' "$STATE_DIR/a.log"; afirma "$?" "segredos: \$(...) no valor e texto, nunca executado"
mundo; job a 'echo "${#TOKEN}"' 'SEGREDOS=s'; seg "TOKEN=ab'cd\n"; roda a
grep -qx 5 "$STATE_DIR/a.log"; afirma "$?" "segredos: aspas no meio do valor ficam"
# aspas de contorno saem; o valor limpo e filtrado da saida
mundo; job a 'echo "x${TOKEN}y"' 'SEGREDOS=s'; seg "TOKEN=\"$SENT\"\n"; roda a
grep -qxF 'x***y' "$STATE_DIR/a.log"; afirma "$?" "segredos: aspas de contorno removidas e valor filtrado"
nada_vazou "segredo entre aspas"
# erro do proprio script (stderr) tambem e filtrado; segredo em linha longa no meio de outras
mundo; job a 'echo "antes $TOKEN depois $TOKEN fim" >&2; exit 1' 'SEGREDOS=s'; seg "TOKEN=$SENT\n"; roda a
nada_vazou "segredo repetido no stderr"
grep -qF "antes *** depois *** fim" "$STATE_DIR/a.log"; afirma "$?" "segredo repetido: todas as ocorrencias trocadas"
# segredo no resumo (ultimas linhas) e no alerta
mundo; job a 'echo "falha com $TOKEN"; exit 1' 'SEGREDOS=s'; seg "TOKEN=$SENT\n"; roda a
! grep -qF -- "$SENT" <<<"$(campo a resumo)"; afirma "$?" "segredo: fora do resumo"
nada_vazou "segredo no resumo e no alerta"

# --- .job invalido em runtime: json rc 2 e alerta ---
mundo; job a 'echo oi'; printf 'DESCRICAO=x\nAGENDA=daily\nCOMANDO=jobs/bin/a.sh\nTIMEOUT_MIN=1\nFOO=1\n' > "$JOBS_DIR/a.job"; roda a
afirma_rc "$rc" 2 "runtime invalido: rc 2"
if [[ $(campo a rc) == 2 ]]; then ok "runtime invalido: json com rc 2"; else falha "runtime invalido: json com rc 2"; fi
grep -q 'chave desconhecida' "$STATE_DIR/a.log"; afirma "$?" "runtime invalido: motivo no log"
afirma_log "alertar job falhou a rc=2" "runtime invalido: alerta"

# --- clone: rc registrado, json e alerta; tempo esgotado ---
mundo; job a 'echo nao-devia' 'REPO=resper1965/projeto-x'; export CLONE_FALHA=1; roda a
if [[ $(campo a rc) == 1 ]]; then ok "clone falho: json com o rc do clone"; else falha "clone falho: json com o rc do clone"; fi
unset CLONE_FALHA
mundo; job a 'echo nao-devia' 'REPO=resper1965/projeto-x'; printf '#!/usr/bin/env bash\nexec sleep 30\n' > "$STUBS/clona"; export CLONE_TIMEOUT=1; ini=$SECONDS; roda a
if [[ $(campo a rc) == 124 ]] && (( SECONDS - ini < 20 )); then ok "clone lento: rc 124 sem esperar"; else falha "clone lento: rc 124 sem esperar"; fi
afirma_log "alertar job falhou a rc=124" "clone lento: alerta"
unset CLONE_TIMEOUT

# --- ambiente fechado ---
mundo; job a 'env | cut -d= -f1 | sort > "'"$T"'/vars"' 'SEGREDOS=s'; seg "TOKEN=x1\n"
export LEAK_DO_CHAMADOR=1; roda a; unset LEAK_DO_CHAMADOR
extras=$(grep -vxE 'PATH|HOME|LANG|PWD|OLDPWD|SHLVL|_|TOKEN' "$T/vars" | tr '\n' ' ')
if [[ -z $extras ]] && grep -qx TOKEN "$T/vars"; then ok "ambiente: so PATH, HOME, LANG e os segredos"; else falha "ambiente: sobrou '$extras'"; fi

# --- um so processo por job (flock) ---
mundo; export JOB_TIMEOUT_UNIT=m; job a 'sleep 3; echo fim-do-primeiro'
"$J" a >/dev/null 2>&1 & primeiro=$!
sleep 1; roda a
afirma_rc "$rc" 75 "lock: segunda instancia recusada (75)"
wait "$primeiro"; afirma_rc "$?" 0 "lock: a primeira termina normalmente"
grep -qF fim-do-primeiro "$STATE_DIR/a.log"; afirma "$?" "lock: o estado da primeira nao foi pisado"
export JOB_TIMEOUT_UNIT=s

# --- filho em segundo plano nao segura o job nem sobrevive ---
mundo; job a 'sleep 30 & echo $! > "'"$T"'/filho"; echo pai-saiu'; ini=$SECONDS; roda a
if (( SECONDS - ini < 15 )); then ok "filho em segundo plano: o job termina logo"; else falha "filho em segundo plano: o job termina logo"; fi
sleep 0.5
if ! kill -0 "$(cat "$T/filho")" 2>/dev/null; then ok "filho em segundo plano: morto ao fim do job"; else falha "filho em segundo plano: morto ao fim do job"; kill "$(cat "$T/filho")" 2>/dev/null; fi

fim
