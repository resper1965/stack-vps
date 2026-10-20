#!/usr/bin/env bash
# Rede da conta "ci": os runners nao alcancam a tailnet nem o metadata da nuvem. A regra e por UID
# (-m owner --uid-owner) no OUTPUT do host, porque o Docker rootless do ci sai pelo processo dele
# (slirp4netns/pasta) e nao passa por DOCKER-USER. Uma cadeia STACK-CI por familia guarda os REJECT;
# uma unica regra na posicao 1 do OUTPUT salta para ela so para o UID do ci. Nunca limpa OUTPUT
# nem cadeia que nao e nossa. Idempotente; reaplicada no boot pelo stack-ci-rede.service.
# Uso: sudo ./39-ci-rede.sh [--instalar | --remover | --status]
# Sobrescreviveis nos testes (so com STACK_TESTE=1): CI_REDE_LIB, CI_REDE_UNIT.
set -euo pipefail
[[ $EUID -eq 0 || ${STACK_TESTE:-} == 1 ]] || { echo "rode como root"; exit 1; }

# Em producao o ambiente herdado (sudo -E, export vazado) e ignorado: atribui sem ler.
# >>> normaliza
if [[ ${STACK_TESTE:-} != 1 ]]; then
  CI_REDE_LIB=/usr/local/lib/stack-vps; CI_REDE_UNIT=/etc/systemd/system
fi
# <<< normaliza

CI_REDE_LIB=${CI_REDE_LIB:-/usr/local/lib/stack-vps}
CI_REDE_UNIT=${CI_REDE_UNIT:-/etc/systemd/system}
REPO=$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)

TAILNET_V4=100.64.0.0/10
TAILNET_V6=fd7a:115c:a1e0::/48
METADATA=169.254.169.254/32
CADEIA=STACK-CI
TAG=stack-ci

# numeros de ordem, em OUTPUT, das regras que saltam para a nossa cadeia (qualquer UID)
saltos() { "$1" -S OUTPUT | awk '/^-A OUTPUT/{n++} /-j STACK-CI$/{print n}'; }

# o salto existe uma vez so, na posicao 1 e com o UID atual (a linha 1 do -S e a politica)
salto_ok() {
  [[ $(saltos "$1") == 1 ]] && "$1" -S OUTPUT | sed -n 2p | grep -qE -- "--uid-owner $2( |\$)"
}

remove_saltos() {
  local n
  while n=$(saltos "$1" | sed -n 1p); [[ -n $n ]]; do "$1" -D OUTPUT "$n"; done
}

# aplica_familia <iptables|ip6tables> <uid> <destino>...
aplica_familia() {
  local ipt=$1 uid=$2 d; shift 2
  "$ipt" -N "$CADEIA" 2>/dev/null || true
  for d in "$@"; do
    "$ipt" -C "$CADEIA" -d "$d" -m comment --comment "$TAG" -j REJECT 2>/dev/null ||
      "$ipt" -A "$CADEIA" -d "$d" -m comment --comment "$TAG" -j REJECT
  done
  salto_ok "$ipt" "$uid" || {
    remove_saltos "$ipt"
    "$ipt" -I OUTPUT 1 -m owner --uid-owner "$uid" -m comment --comment "$TAG" -j "$CADEIA"
  }
}

# status_familia <iptables|ip6tables> <uid> <destino>...
status_familia() {
  local ipt=$1 uid=$2 d; shift 2
  salto_ok "$ipt" "$uid" || return 1
  for d in "$@"; do
    "$ipt" -C "$CADEIA" -d "$d" -m comment --comment "$TAG" -j REJECT 2>/dev/null || return 1
  done
}

remove_familia() {
  remove_saltos "$1"
  "$1" -F "$CADEIA" 2>/dev/null || true
  "$1" -X "$CADEIA" 2>/dev/null || true
}

modo=${1:-}
case $modo in
  ""|--instalar|--status|--remover) ;;
  *) echo "uso: $0 [--instalar | --remover | --status]"; exit 2 ;;
esac

if [[ $modo == --remover ]]; then
  remove_familia iptables; remove_familia ip6tables
  echo "ci-rede: removida"; exit 0
fi

# sem a conta nao se insere regra nenhuma: uma regra sem --uid-owner pegaria o host inteiro
if ! uid=$(id -u ci 2>/dev/null) || [[ ! $uid =~ ^[0-9]+$ ]]; then
  if [[ $modo == --status ]]; then echo inativa; exit 1; fi
  echo "a conta ci nao existe; rode o 38-ci-conta.sh antes"; exit 1
fi

if [[ $modo == --status ]]; then
  if status_familia iptables "$uid" "$TAILNET_V4" "$METADATA" && status_familia ip6tables "$uid" "$TAILNET_V6"; then
    echo ativa; exit 0
  fi
  echo inativa; exit 1
fi

aplica_familia iptables "$uid" "$TAILNET_V4" "$METADATA"
aplica_familia ip6tables "$uid" "$TAILNET_V6"

if [[ $modo == --instalar ]]; then
  install -d -m 755 "$CI_REDE_LIB"
  install -m 755 "$0" "$CI_REDE_LIB/39-ci-rede.sh"
  install -m 644 "$REPO/systemd/stack-ci-rede.service" "$CI_REDE_UNIT/"
  systemctl daemon-reload; systemctl enable stack-ci-rede.service >/dev/null
fi
echo "ci-rede: ativa para o uid $uid"
