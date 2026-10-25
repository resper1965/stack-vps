# shellcheck shell=bash disable=SC2034  # J_* sao lidas por quem faz source
# Leitura estrita de jobs/<nome>.job, compartilhada por bin/stack-job, scripts/45-jobs.sh e bin/stack-doctor.
# Sem source/eval: cada linha e vazia, comentario (#) ou CHAVE=valor com valor em alfabeto fechado.
# job_carregar <arquivo-absoluto>: define J_NOME J_DESCRICAO J_AGENDA J_COMANDO J_SEGREDOS J_REPO
# J_TIMEOUT_MIN J_HABILITADO J_CHAVES J_BASE (raiz do repo = pai da pasta jobs/). Erro: mensagem em stderr, rc 1.
LC_ALL=C   # classes de caractere por byte, igual em qualquer maquina
JOB_CHAVES=" DESCRICAO AGENDA COMANDO SEGREDOS CHAVES REPO TIMEOUT_MIN HABILITADO "

job_nome_ok() { [[ $1 =~ ^[a-z0-9-]+$ ]]; }

job_carregar() {
  local f=$1 n=0 linha k v c
  local -A vistas=() val=()
  local re_vazia='^[[:space:]]*(#.*)?$' re_par='^([A-Z_]+)=(.*)$'
  local re_valor='^[A-Za-z0-9_./:@,*~=+? -]*$' re_ctl='[[:cntrl:]]' re_desc='[$`\\%]'
  local re_cmd='^jobs/bin/[A-Za-z0-9][A-Za-z0-9._-]*$' re_repo='^[A-Za-z0-9][A-Za-z0-9._-]*/[A-Za-z0-9][A-Za-z0-9._-]*$'
  J_NOME=$(basename "$f" .job)
  J_BASE=$(dirname "$(dirname "$f")")
  job_nome_ok "$J_NOME" && [[ $f == *.job ]] || { echo "$f: nome invalido (use [a-z0-9-]+.job)" >&2; return 1; }
  [[ -f $f && ! -L $f ]] || { echo "$f: nao e arquivo regular" >&2; return 1; }
  while IFS= read -r linha || [[ -n $linha ]]; do
    n=$((n+1))
    [[ $linha =~ $re_ctl ]] && { echo "$f: linha $n com caractere de controle" >&2; return 1; }
    [[ $linha =~ $re_vazia ]] && continue
    [[ $linha =~ $re_par ]] || { echo "$f: linha $n malformada (esperado CHAVE=valor)" >&2; return 1; }
    k=${BASH_REMATCH[1]} v=${BASH_REMATCH[2]}
    [[ $JOB_CHAVES == *" $k "* ]] || { echo "$f: chave desconhecida $k (linha $n)" >&2; return 1; }
    [[ -z ${vistas[$k]:-} ]] || { echo "$f: chave $k repetida (linha $n)" >&2; return 1; }
    vistas[$k]=1
    if [[ $k == DESCRICAO ]]; then
      [[ ! $v =~ $re_desc ]] || { echo "$f: DESCRICAO com caractere proibido (\$ \` \\ %)" >&2; return 1; }
    else
      [[ $v =~ $re_valor ]] || { echo "$f: $k com caractere fora do alfabeto permitido (linha $n)" >&2; return 1; }
    fi
    [[ $v != " "* && $v != *" " ]] || { echo "$f: $k com espaco nas pontas (linha $n)" >&2; return 1; }
    val[$k]=$v
  done < "$f"

  for c in DESCRICAO AGENDA COMANDO TIMEOUT_MIN; do
    [[ -n ${val[$c]:-} ]] || { echo "$f: falta a chave $c" >&2; return 1; }
  done
  J_DESCRICAO=${val[DESCRICAO]} J_AGENDA=${val[AGENDA]} J_COMANDO=${val[COMANDO]}
  J_SEGREDOS=${val[SEGREDOS]:-} J_CHAVES=${val[CHAVES]:-} J_REPO=${val[REPO]:-} J_TIMEOUT_MIN=${val[TIMEOUT_MIN]} J_HABILITADO=${val[HABILITADO]:-nao}

  [[ $J_AGENDA != -* ]] || { echo "$f: AGENDA nao pode comecar com '-'" >&2; return 1; }
  c=${J_COMANDO%% *}
  [[ $c =~ $re_cmd && $J_COMANDO != *..* ]] || { echo "$f: COMANDO deve ser jobs/bin/<script> [args], sem '..'" >&2; return 1; }
  [[ -f $J_BASE/$c && -x $J_BASE/$c && ! -L $J_BASE/$c ]] || { echo "$f: $c ausente, nao executavel ou link" >&2; return 1; }
  [[ $J_TIMEOUT_MIN =~ ^[1-9][0-9]{0,3}$ ]] && (( J_TIMEOUT_MIN <= 1440 )) || { echo "$f: TIMEOUT_MIN deve ser de 1 a 1440" >&2; return 1; }
  [[ $J_HABILITADO == sim || $J_HABILITADO == nao ]] || { echo "$f: HABILITADO deve ser sim ou nao" >&2; return 1; }
  [[ -z $J_REPO ]] || { [[ $J_REPO =~ $re_repo && $J_REPO != *..* ]] || { echo "$f: REPO deve ser dono/nome" >&2; return 1; }; }
  # CHAVES: nomes das variaveis do arquivo de segredos (sufixo ? = opcional); so o 43-segredos-guiado.sh usa
  if [[ -n $J_CHAVES ]]; then
    [[ -n $J_SEGREDOS ]] || { echo "$f: CHAVES exige SEGREDOS" >&2; return 1; }
    local ch chs
    IFS=, read -ra chs <<<"$J_CHAVES"
    for ch in "${chs[@]}"; do
      [[ $ch =~ ^[A-Z][A-Z0-9_]*\??$ && ! $ch =~ ^(PATH|IFS|HOME|SHELL|ENV|BASH_ENV|LD_|PYTHON) ]] || { echo "$f: CHAVES com nome invalido" >&2; return 1; }
    done
  fi
  [[ -z $J_SEGREDOS ]] || { job_nome_ok "$J_SEGREDOS" || { echo "$f: SEGREDOS deve ser [a-z0-9-]+" >&2; return 1; }; }
  return 0
}
