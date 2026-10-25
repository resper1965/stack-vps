#!/usr/bin/env bash
# shellcheck source=tests/lib.sh
. "$(dirname "$0")/lib.sh"
S=$RAIZ_REPO/scripts/43-segredos-guiado.sh
SENHA=senha-bem-longa-xyz-123
JWT=jwt-de-teste-abcdef-456
CHAVE=sk-chave-api-teste-789
echo "43-segredos-guiado (valores nunca na saida; escrita atomica; 0600)"

prepara() {
  novo_tmp; stub systemctl; stub sudo
  export SEG_EUID=0 HOME=$T/home SEG_AGENTE_ENV=$T/agente.env SEG_LINEAR_DIR=$T/pmo; mkdir -p "$HOME" "$T/pmo"
  DIR=$HOME/.config/9router
}
# roda <subcomando+opcoes> com as linhas de stdin como entrada oculta
roda() { cat > "$T/entrada"; SEG_ENTRADA=$T/entrada bash "$S" "$@" > "$T/saida" 2>&1; RC=$?; }
sem_valor() { # rotulo valores...
  local r=$1 v; shift
  for v in "$@"; do
    [[ -n $v ]] || continue
    if grep -qF -- "$v" "$T/saida" "$STUB_LOG"; then falha "$r: valor vazou"; return; fi
  done; ok "$r: nenhum valor na saida/log"
}
modo() { [[ $(stat -c %a "$1") == "$2" ]]; }

# 9router: grava as duas chaves, 0600, diretorio 0700
prepara; roda 9router < <(printf '%s\n%s\n' "$SENHA" "$JWT"); afirma_rc $RC 0 "9router grava"
grep -qx "INITIAL_PASSWORD=$SENHA" "$DIR/9router.env" && grep -qx "JWT_SECRET=$JWT" "$DIR/9router.env"; afirma $? "9router.env com as chaves"
modo "$DIR/9router.env" 600; afirma $? "9router.env 0600"; modo "$DIR" 700; afirma $? "diretorio 0700"
sem_valor "9router" "$SENHA" "$JWT"
# sem --trocar nao sobrescreve; com --trocar troca e mantem outras linhas
echo "OUTRA=1" >> "$DIR/9router.env"
roda 9router < <(printf '%s\n%s\n' "outra-senha-bem-longa-1" "$JWT"); afirma_rc $RC 1 "recusa sobrescrever"
grep -qx "INITIAL_PASSWORD=$SENHA" "$DIR/9router.env"; afirma $? "arquivo intacto apos recusa"
roda 9router --trocar < <(printf '%s\n%s\n' "outra-senha-bem-longa-1" "$JWT"); afirma_rc $RC 0 "--trocar sobrescreve"
grep -qx "INITIAL_PASSWORD=outra-senha-bem-longa-1" "$DIR/9router.env" && grep -qx OUTRA=1 "$DIR/9router.env" && [[ $(grep -c '^INITIAL_PASSWORD=' "$DIR/9router.env") == 1 ]] && r=0 || r=1; afirma $r "troca sem duplicar e preserva outras linhas"
modo "$DIR/9router.env" 600; afirma $? "0600 apos trocar"
n=$(find "$DIR" -type f | wc -l); [[ $n == 1 ]] && r=0 || r=1; afirma $r "sem temporarios"

# --gerar: tamanhos e nada na saida
prepara; roda 9router --gerar </dev/null; afirma_rc $RC 0 "--gerar"
s=$(grep '^INITIAL_PASSWORD=' "$DIR/9router.env" | cut -d= -f2-); j=$(grep '^JWT_SECRET=' "$DIR/9router.env" | cut -d= -f2-)
[[ ${#s} -ge 24 && ${#j} -ge 48 && $s != "$j" ]] && r=0 || r=1; afirma $r "gerado: senha>=24, JWT>=48"
sem_valor "--gerar" "$s" "$j"
prepara; roda cliente --gerar </dev/null; afirma_rc $RC 2 "--gerar so no 9router"

# entradas invalidas: nada escrito, valor fora da saida
invalida() { # rotulo senha jwt
  prepara; roda 9router < <(printf '%s\n%s\n' "$2" "$3"); afirma_rc $RC 1 "$1 recusado"
  [[ ! -e $DIR/9router.env ]] && r=0 || r=1; afirma $r "$1: nada escrito"
  sem_valor "$1" "$2" "$3"
}
invalida "senha curta" 123456789012345 "$JWT"
invalida "senha vazia" "" "$JWT"
invalida "jwt vazio" "$SENHA" ""
invalida "senha com aspas" "\"$SENHA" "$JWT"
invalida "jwt com aspa simples" "$SENHA" "'$JWT"
invalida "senha com CR" "$SENHA"$'\r' "$JWT"
invalida "senha com barra" "senha-com-barra\-longa-123" "$JWT"

# cliente
prepara; roda cliente < <(printf '%s\n' "$CHAVE"); afirma_rc $RC 0 "cliente grava"
[[ $(cat "$DIR/client.env") == "NINE_ROUTER_API_KEY=$CHAVE" ]] && r=0 || r=1; afirma $r "client.env correto"; modo "$DIR/client.env" 600; afirma $? "client.env 0600"
sem_valor cliente "$CHAVE"
roda cliente < <(printf '%s\n' "outra-chave-123456"); afirma_rc $RC 1 "cliente recusa sem --trocar"
prepara; roda cliente < <(printf '%s\n' ""); afirma_rc $RC 1 "chave vazia"; [[ ! -e $DIR/client.env ]] && r=0 || r=1; afirma $r "chave vazia: nada escrito"

# agente.env: dono/modo preservados, sem duplicar
prepara; printf 'GITHUB_TOKEN=abc\n' > "$SEG_AGENTE_ENV"; chmod 640 "$SEG_AGENTE_ENV"
roda agente < <(printf '%s\n' "$CHAVE"); afirma_rc $RC 0 "agente grava"
modo "$SEG_AGENTE_ENV" 640; afirma $? "agente.env mantem 0640"
[[ $(stat -c %U:%G "$SEG_AGENTE_ENV") == "$(id -un):$(id -gn)" ]] && r=0 || r=1; afirma $r "dono preservado"
grep -qx GITHUB_TOKEN=abc "$SEG_AGENTE_ENV"; afirma $? "outras linhas preservadas"
roda agente < <(printf '%s\n' "$CHAVE"); afirma_rc $RC 1 "segunda vez sem --trocar recusa"
roda agente --trocar < <(printf '%s\n' "nova-chave-9876543"); afirma_rc $RC 0 "agente --trocar"
[[ $(grep -c '^NINE_ROUTER_API_KEY=' "$SEG_AGENTE_ENV") == 1 ]] && r=0 || r=1; afirma $r "linha nao duplicada"
sem_valor agente "$CHAVE" nova-chave-9876543
prepara; roda agente < <(printf '%s\n' "$CHAVE"); afirma_rc $RC 1 "agente.env ausente recusa"

# linear
prepara; roda linear < <(printf '%s\n%s\n' "lin_api_teste_123456" "ABC"); afirma_rc $RC 0 "linear grava"
[[ $(cat "$SEG_LINEAR_DIR/linear-token") == lin_api_teste_123456 && $(cat "$SEG_LINEAR_DIR/linear-team") == ABC ]] && r=0 || r=1; afirma $r "token e time corretos"
modo "$SEG_LINEAR_DIR/linear-token" 640; afirma $? "linear-token 0640"
sem_valor linear lin_api_teste_123456
roda linear < <(printf '%s\n%s\n' "outro_token_123456" "ABC"); afirma_rc $RC 1 "linear recusa sem --trocar"
prepara; SEG_EUID=1000 roda linear < <(printf '%s\n%s\n' "lin_api_teste_123456" "ABC"); afirma_rc $RC 1 "linear sem root"
grep -q sudo "$T/saida"; afirma $? "linear sem root diz sudo"; [[ ! -e $SEG_LINEAR_DIR/linear-token ]] && r=0 || r=1; afirma $r "nada escrito sem root"
prepara; roda linear < <(printf '%s\n%s\n' "lin_api_teste_123456" ""); afirma_rc $RC 1 "linear time vazio"; [[ ! -e $SEG_LINEAR_DIR/linear-token ]] && r=0 || r=1; afirma $r "time vazio: nada escrito"
# agente.env real: chown/chgrp proibidos (dev fora do grupo agente); mesmo inode, dono, grupo e modo; export reconhecido
prepara; stub chown 1; stub chgrp 1; printf 'GITHUB_TOKEN=abc\nexport NINE_ROUTER_API_KEY=velha-chave-123\n' > "$SEG_AGENTE_ENV"; chmod 640 "$SEG_AGENTE_ENV"
antes=$(stat -c '%i %U:%G %a' "$SEG_AGENTE_ENV")
roda agente < <(printf '%s\n' "$CHAVE"); afirma_rc $RC 1 "export existente recusa sem --trocar"
roda agente --trocar < <(printf '%s\n' "$CHAVE"); afirma_rc $RC 0 "agente --trocar com chown proibido"
[[ $(stat -c '%i %U:%G %a' "$SEG_AGENTE_ENV") == "$antes" ]] && r=0 || r=1; afirma $r "mesmo inode, dono, grupo e modo"
nega_log chown "chown nao chamado"; nega_log chgrp "chgrp nao chamado"
[[ $(grep -c 'NINE_ROUTER_API_KEY=' "$SEG_AGENTE_ENV") == 1 ]] && grep -qx "NINE_ROUTER_API_KEY=$CHAVE" "$SEG_AGENTE_ENV" && grep -qx GITHUB_TOKEN=abc "$SEG_AGENTE_ENV" && r=0 || r=1; afirma $r "chave entrou, export antigo saiu"
n=$(find "$T" -maxdepth 1 -name 'agente.env.*' | wc -l); [[ $n == 0 ]] && r=0 || r=1; afirma $r "temporarios removidos"
sem_valor "agente real" "$CHAVE" velha-chave-123

# cliente indica a segunda etapa; tab recusado
prepara; roda cliente < <(printf '%s\n' "$CHAVE"); grep -qF "como dev: /opt/stack-vps/scripts/43-segredos-guiado.sh agente" "$T/saida" && r=0 || r=1; afirma $r "cliente imprime a proxima etapa"
invalida "senha com tab" "senha-com-tab"$'\t'"-longa-123" "$JWT"

# sem terminal e sem entrada de teste: mensagem clara, nada escrito
prepara; setsid -w bash "$S" cliente < /dev/null > "$T/saida" 2>&1; RC=$?; afirma_rc $RC 1 "sem terminal"
grep -qF "sem terminal para ler o valor" "$T/saida" && r=0 || r=1; afirma $r "mensagem de sem terminal"; [[ ! -e $DIR/client.env ]] && r=0 || r=1; afirma $r "sem terminal: nada escrito"
fim
