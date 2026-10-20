#!/usr/bin/env bash
# Rede da conta "ci": os runners nao alcancam a tailnet nem o metadata da nuvem. A regra e por UID
# (-m owner --uid-owner) no OUTPUT do host, porque o Docker rootless do ci sai pelo processo dele
# (slirp4netns/pasta) e nao passa por DOCKER-USER. Uma cadeia STACK-CI por familia guarda os REJECT;
# uma unica regra na posicao 1 do OUTPUT salta para ela so para o UID do ci. Nunca limpa OUTPUT
# nem cadeia que nao e nossa. Idempotente; reaplicada no boot pelo stack-ci-rede.service.
# Toda chamada ao iptables usa -w 10 (lock do xtables); falha de lock ou de listagem aborta, nunca
# e lida como "regra ausente".
# Uso: sudo ./39-ci-rede.sh [--instalar | --remover | --status]
# Sobrescreviveis nos testes (so com STACK_TESTE=1): CI_REDE_LIB, CI_REDE_UNIT, CI_RUN_USER.
set -euo pipefail
[[ $EUID -eq 0 || ${STACK_TESTE:-} == 1 ]] || { echo "rode como root"; exit 1; }

# Em producao o ambiente herdado (sudo -E, export vazado) e ignorado: atribui sem ler.
# >>> normaliza
if [[ ${STACK_TESTE:-} != 1 ]]; then
  CI_REDE_LIB=/usr/local/lib/stack-vps; CI_REDE_UNIT=/etc/systemd/system; CI_RUN_USER=/run/user
fi
# <<< normaliza

CI_REDE_LIB=${CI_REDE_LIB:-/usr/local/lib/stack-vps}
CI_REDE_UNIT=${CI_REDE_UNIT:-/etc/systemd/system}
CI_RUN_USER=${CI_RUN_USER:-/run/user}
REPO=$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)

TAILNET_V4=100.64.0.0/10
TAILNET_V6=fd7a:115c:a1e0::/48
METADATA=169.254.169.254/32
CADEIA=STACK-CI
TAG=stack-ci

# unico ponto de chamada: xt <iptables|ip6tables> args...
xt() { local c=$1; shift; "$c" -w 10 "$@"; }

# lista o OUTPUT; falha (lock, binario ausente) NUNCA vira "lista vazia"
listar() {
  xt "$1" -S OUTPUT || { echo "falha ao listar o OUTPUT ($1); lock do xtables ocupado?" >&2; return 1; }
}

# "<quantos saltos para STACK-CI> <1 se a regra da posicao 1 e o salto do uid>" (linha 1 do -S e a politica)
salto_info() {
  local l; l=$(listar "$1") || return 1
  echo "$(grep -c -e '-j STACK-CI$' <<<"$l" || true) $(sed -n 2p <<<"$l" | grep -cE -- "--uid-owner $2 .*-j STACK-CI\$" || true)"
}

# apaga os saltos de ordem >= $2 (um a um: os numeros deslocam a cada -D)
remove_saltos() {
  local l n
  while :; do
    l=$(listar "$1") || exit 1
    n=$(awk -v min="$2" '/^-A OUTPUT/{n++} /-j STACK-CI$/ && n>=min {print n; exit}' <<<"$l")
    [[ -n $n ]] || return 0
    xt "$1" -D OUTPUT "$n"
  done
}

# 0 = ok, 1 = nao; qualquer outro codigo (lock) aborta
tem_regra() {
  local rc=0; xt "$@" 2>/dev/null || rc=$?
  case $rc in 0) return 0 ;; 1) return 1 ;; *) echo "iptables falhou (rc $rc); lock do xtables?" >&2; exit 1 ;; esac
}

# aplica_familia <iptables|ip6tables> <uid> <destino>...
aplica_familia() {
  local ipt=$1 uid=$2 d info; shift 2
  tem_regra "$ipt" -S "$CADEIA" >/dev/null || xt "$ipt" -N "$CADEIA"
  for d in "$@"; do
    tem_regra "$ipt" -C "$CADEIA" -d "$d" -m comment --comment "$TAG" -j REJECT ||
      xt "$ipt" -A "$CADEIA" -d "$d" -m comment --comment "$TAG" -j REJECT
  done
  info=$(salto_info "$ipt" "$uid") || exit 1
  # primeiro entra o salto certo na posicao 1, so depois saem os outros: nunca ha janela sem isolamento
  [[ ${info#* } == 1 ]] || xt "$ipt" -I OUTPUT 1 -m owner --uid-owner "$uid" -m comment --comment "$TAG" -j "$CADEIA"
  remove_saltos "$ipt" 2
}

# status_familia <iptables|ip6tables> <uid> <destino>...
status_familia() {
  local ipt=$1 uid=$2 d info; shift 2
  info=$(salto_info "$ipt" "$uid") || exit 1
  [[ $info == "1 1" ]] || return 1
  for d in "$@"; do
    tem_regra "$ipt" -C "$CADEIA" -d "$d" -m comment --comment "$TAG" -j REJECT || return 1
  done
}

remove_familia() {
  remove_saltos "$1" 1
  tem_regra "$1" -S "$CADEIA" >/dev/null || return 0
  xt "$1" -F "$CADEIA"
  xt "$1" -X "$CADEIA" 2>/dev/null || { echo "$1: cadeia $CADEIA ainda referenciada; nao removida" >&2; return 1; }
}

modo=${1:-}
case $modo in
  ""|--instalar|--status|--remover) ;;
  *) echo "uso: $0 [--instalar | --remover | --status]"; exit 2 ;;
esac

if [[ $modo == --remover ]]; then
  # sem a rede os runners (ou containers orfaos) sairiam para a tailnet: exige --parar antes
  recusa() { echo "$1; pare os runners antes: 40-ci-runners.sh --parar"; exit 1; }
  ! systemctl is-active --quiet stack-ci-runners.service || recusa "stack-ci-runners ativa"
  if cuid=$(id -u ci 2>/dev/null) && [[ $cuid =~ ^[1-9][0-9]*$ ]]; then
    cd /
    ids=$(sudo -u ci env XDG_RUNTIME_DIR="$CI_RUN_USER/$cuid" DOCKER_HOST="unix://$CI_RUN_USER/$cuid/docker.sock"       docker ps -q --filter label=stack-ci) || recusa "nao consegui listar os containers do ci"
    [[ -z $ids ]] || recusa "ha containers de runner (stack-ci) rodando"
  fi
  rc=0; remove_familia iptables || rc=1; remove_familia ip6tables || rc=1
  if (( rc == 0 )); then echo "ci-rede: removida"; else echo "ci-rede: remocao incompleta"; fi
  exit "$rc"
fi

# sem a conta (ou com UID de sistema) nao se insere regra nenhuma: --uid-owner 0 cortaria o proprio root
# (SSH/tailscaled) e uma regra sem dono pegaria o host inteiro. Mesmo piso do 38-ci-conta.sh.
if ! uid=$(id -u ci 2>/dev/null) || [[ ! $uid =~ ^[1-9][0-9]*$ ]] || (( uid < 1000 )); then
  if [[ $modo == --status ]]; then echo inativa; exit 1; fi
  echo "a conta ci nao existe ou tem UID invalido ('${uid:-}', esperado >= 1000); rode o 38-ci-conta.sh antes"; exit 1
fi

if [[ $modo == --status ]]; then
  if status_familia iptables "$uid" "$TAILNET_V4" "$METADATA" && status_familia ip6tables "$uid" "$TAILNET_V6"; then
    echo ativa; exit 0
  fi
  echo inativa; exit 1
fi

aplica_familia iptables "$uid" "$TAILNET_V4" "$METADATA"
xt ip6tables -S OUTPUT >/dev/null 2>&1 || { echo "ip6tables indisponível; v4 aplicado, v6 NÃO"; exit 1; }
aplica_familia ip6tables "$uid" "$TAILNET_V6"

if [[ $modo == --instalar ]]; then
  install -d -m 755 "$CI_REDE_LIB"
  install -m 755 "$0" "$CI_REDE_LIB/39-ci-rede.sh"
  install -m 644 "$REPO/systemd/stack-ci-rede.service" "$CI_REDE_UNIT/"
  systemctl daemon-reload; systemctl enable stack-ci-rede.service >/dev/null
fi
echo "ci-rede: ativa para o uid $uid"
