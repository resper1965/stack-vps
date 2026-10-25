#!/usr/bin/env bash
# Segredos guiados da VPS: pede o valor oculto (TTY) ou gera aleatorio, valida e grava com umask 077 e
# escrita atomica (mktemp no mesmo diretorio + mv). Nenhum valor vai para saida, argv, log ou erro.
# Uso: 43-segredos-guiado.sh {9router|cliente|agente|linear} [--gerar] [--trocar]
#   9router  (como agente) ~/.config/9router/9router.env: INITIAL_PASSWORD (>=16) e JWT_SECRET
#   cliente  (como agente) ~/.config/9router/client.env: NINE_ROUTER_API_KEY (chave criada no painel do 9router)
#   agente   (como dev)    /srv/dev/secrets/agente.env: linha NINE_ROUTER_API_KEY= (dono/modo preservados)
#   linear   (como root)   /etc/pmo/linear-token e linear-team (root:pmo 640, lidos por pmo/linear.py)
# --gerar: so 9router (senha e JWT aleatorios; leia-os do proprio arquivo). --trocar: permite sobrescrever.
set -euo pipefail
umask 077
TESTE=${STACK_TESTE:-}
ALVO=${1:-}; shift || true
GERAR=0; TROCAR=0
for a in "$@"; do
  case $a in --gerar) GERAR=1 ;; --trocar) TROCAR=1 ;; *) echo "opcao desconhecida: $a"; exit 2 ;; esac
done
uso() { echo "uso: ${0##*/} {9router|cliente|agente|linear} [--gerar] [--trocar]"; exit 2; }
[[ $ALVO =~ ^(9router|cliente|agente|linear)$ ]] || uso
[[ $GERAR == 0 || $ALVO == 9router ]] || { echo "--gerar so vale para 9router"; exit 2; }

DIR_9R=$HOME/.config/9router
AGENTE_ENV=/srv/dev/secrets/agente.env
LINEAR_DIR=/etc/pmo
if [[ $TESTE == 1 ]]; then AGENTE_ENV=${SEG_AGENTE_ENV:-$AGENTE_ENV}; LINEAR_DIR=${SEG_LINEAR_DIR:-$LINEAR_DIR}; fi
fim() { echo "$*"; exit 1; }

tmp=""; tmp2=""
trap 'rm -f "$tmp" "$tmp2"' EXIT
[[ $TESTE == 1 && -n ${SEG_ENTRADA:-} ]] && exec 3< "$SEG_ENTRADA"

# le_segredo <rotulo>: o valor vai para REPLY, nunca para a tela
le_segredo() {
  if [[ $TESTE == 1 && -n ${SEG_ENTRADA:-} ]]; then IFS= read -r REPLY <&3 || REPLY=""
  else
    [[ -r /dev/tty ]] || fim "sem terminal para ler $1 (rode num terminal interativo)"
    printf '%s: ' "$1" > /dev/tty; IFS= read -rs REPLY < /dev/tty || REPLY=""; echo > /dev/tty
  fi
}
gera() { local s; s=$(head -c 192 /dev/urandom | base64 -w0 | tr -dc 'A-Za-z0-9' || true); REPLY=${s:0:$1}; [[ ${#REPLY} -ge $1 ]] || fim "falha ao gerar aleatorio"; }
# valida <rotulo> <valor> <minimo>: nunca imprime o valor
valida() {
  [[ -n $2 ]] || fim "$1 vazio"
  [[ ${#2} -ge $3 ]] || fim "$1 curto (minimo $3 caracteres)"
  [[ $2 != *$'\r'* && $2 != *$'\n'* ]] || fim "$1 tem CR ou quebra de linha"
  [[ $2 != [\'\"]* ]] || fim "$1 nao pode comecar com aspas"
  case $2 in *'"'*|*\\*|*' '*) fim "$1 nao pode ter aspas, barra invertida ou espaco" ;; esac
}
# grava <arquivo> <CHAVE> <valor>...: troca/acrescenta as chaves; preserva as outras linhas, dono e modo do existente
grava() {
  local f=$1; shift
  local args=("$@") i linha pula
  [[ ! -L $f ]] || fim "$f e link; recuso"
  local d; d=$(dirname "$f"); [[ -d $d && -w $d ]] || fim "diretorio $d ausente ou sem escrita para $(id -un)"
  tmp=$(mktemp "$f.XXXXXX")
  if [[ -f $f ]]; then
    while IFS= read -r linha || [[ -n $linha ]]; do
      pula=0
      for ((i=0; i<${#args[@]}; i+=2)); do [[ $linha == "${args[i]}="* ]] && pula=1; done
      [[ $pula == 1 ]] || printf '%s\n' "$linha" >> "$tmp"
    done < "$f"
    chmod --reference="$f" "$tmp"
    chown --reference="$f" "$tmp" 2>/dev/null || chgrp --reference="$f" "$tmp" 2>/dev/null || fim "nao consegui preservar o dono de $f"
  fi
  for ((i=0; i<${#args[@]}; i+=2)); do printf '%s=%s\n' "${args[i]}" "${args[i+1]}" >> "$tmp"; done
  mv "$tmp" "$f"; tmp=""
}
tem_chave() { [[ -f $1 ]] && grep -q "^$2=" "$1"; }
recusa_se_existe() { [[ $TROCAR == 1 ]] || fim "$1 ja existe; use --trocar para sobrescrever"; }

case $ALVO in
9router|cliente)
  [[ $(id -un) == agente || $TESTE == 1 ]] || fim "rode como agente: sudo -u agente -H bash -c 'cd ~ && /opt/stack-vps/scripts/43-segredos-guiado.sh $ALVO'"
  install -d -m 700 "$DIR_9R"
  if [[ $ALVO == 9router ]]; then
    f=$DIR_9R/9router.env
    if tem_chave "$f" INITIAL_PASSWORD || tem_chave "$f" JWT_SECRET; then recusa_se_existe "$f"; fi
    if [[ $GERAR == 1 ]]; then gera 24; senha=$REPLY; gera 48; jwt=$REPLY
    else le_segredo "INITIAL_PASSWORD (>=16)"; senha=$REPLY; le_segredo "JWT_SECRET"; jwt=$REPLY; fi
    valida INITIAL_PASSWORD "$senha" 16; valida JWT_SECRET "$jwt" 16
    grava "$f" INITIAL_PASSWORD "$senha" JWT_SECRET "$jwt"
    echo "gravado $f (0600). Leia as credenciais do proprio arquivo; nada foi impresso."
  else
    f=$DIR_9R/client.env
    if tem_chave "$f" NINE_ROUTER_API_KEY; then recusa_se_existe "$f"; fi
    le_segredo "NINE_ROUTER_API_KEY (do painel do 9router)"; valida NINE_ROUTER_API_KEY "$REPLY" 8
    grava "$f" NINE_ROUTER_API_KEY "$REPLY"
    echo "gravado $f (0600)."
  fi ;;
agente)
  f=$AGENTE_ENV
  [[ -f $f ]] || fim "$f nao existe (rode o 02-layout.sh)"
  if tem_chave "$f" NINE_ROUTER_API_KEY; then recusa_se_existe "$f"; fi
  le_segredo "NINE_ROUTER_API_KEY (do painel do 9router)"; valida NINE_ROUTER_API_KEY "$REPLY" 8
  grava "$f" NINE_ROUTER_API_KEY "$REPLY"
  echo "NINE_ROUTER_API_KEY gravada em $f (dono e modo preservados)." ;;
linear)
  euid=$EUID; [[ $TESTE == 1 ]] && euid=${SEG_EUID:-$EUID}
  [[ $euid -eq 0 ]] || fim "o Linear grava em /etc/pmo (root:pmo): precisa de sudo. Rode: sudo /opt/stack-vps/scripts/43-segredos-guiado.sh linear"
  [[ -d $LINEAR_DIR ]] || fim "$LINEAR_DIR nao existe (rode o 34-pmo.sh antes)"
  if [[ -e $LINEAR_DIR/linear-token || -e $LINEAR_DIR/linear-team ]]; then recusa_se_existe "$LINEAR_DIR/linear-*"; fi
  le_segredo "LINEAR_API_KEY"; chave=$REPLY
  le_segredo "LINEAR_TEAM_KEY (ex.: ABC)"; time=$REPLY
  valida LINEAR_API_KEY "$chave" 8; valida LINEAR_TEAM_KEY "$time" 1
  # valor cru, sem newline, como o 34-pmo.sh grava; pmo/linear.py faz .strip()
  for l in linear-token linear-team; do [[ ! -L $LINEAR_DIR/$l ]] || fim "$LINEAR_DIR/$l e link; recuso"; done
  tmp=$(mktemp "$LINEAR_DIR/linear-token.XXXXXX"); tmp2=$(mktemp "$LINEAR_DIR/linear-team.XXXXXX")
  printf '%s' "$chave" > "$tmp"; printf '%s' "$time" > "$tmp2"
  chmod 640 "$tmp" "$tmp2"
  [[ $TESTE == 1 ]] || chown root:pmo "$tmp" "$tmp2"
  mv "$tmp" "$LINEAR_DIR/linear-token"; tmp=""; mv "$tmp2" "$LINEAR_DIR/linear-team"; tmp2=""
  echo "gravado $LINEAR_DIR/linear-token e linear-team (root:pmo 640)."
  echo "o espelho so roda com pmo-linear.service/timer instalados (34-pmo.sh); a primeira carga e manual, apos a previa." ;;
esac
