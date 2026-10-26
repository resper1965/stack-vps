#!/usr/bin/env bash
# Libera user namespaces SO para o bubblewrap (/usr/bin/bwrap), usado pelo isolamento do Codex, no
# Ubuntu 24.04 (kernel.apparmor_restrict_unprivileged_userns=1). Duas pecas: o perfil AppArmor
# apparmor/usr.bin.bwrap e um dpkg-statoverride que deixa o bwrap 0750 root:agente, para que a
# liberacao valha so para o agente e nao para qualquer conta local. Nunca toca no sysctl global.
# Uso: sudo ./47-apparmor-bwrap.sh [--instalar | --remover | --status]
# Sobrescreviveis nos testes (so com STACK_TESTE=1): AB_BWRAP, AB_DIR, AB_SYSCTL.
set -euo pipefail
[[ $EUID -eq 0 || ${STACK_TESTE:-} == 1 ]] || { echo "rode como root"; exit 1; }

# >>> normaliza
if [[ ${STACK_TESTE:-} != 1 ]]; then
  AB_BWRAP=/usr/bin/bwrap; AB_DIR=/etc/apparmor.d
  AB_SYSCTL=/proc/sys/kernel/apparmor_restrict_unprivileged_userns
fi
# <<< normaliza

AB_BWRAP=${AB_BWRAP:-/usr/bin/bwrap}
AB_DIR=${AB_DIR:-/etc/apparmor.d}
AB_SYSCTL=${AB_SYSCTL:-/proc/sys/kernel/apparmor_restrict_unprivileged_userns}
REPO=$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)
PERFIL_REPO=$REPO/apparmor/usr.bin.bwrap
PERFIL=$AB_DIR/usr.bin.bwrap
GRUPO=agente
ESPERADO="root $GRUPO 750 $AB_BWRAP"

# statoverride atual do bwrap (vazio se nao ha)
override() { dpkg-statoverride --list "$AB_BWRAP" 2>/dev/null || true; }
identico() { [[ -f $PERFIL ]] && cmp -s "$PERFIL_REPO" "$PERFIL"; }

modo=${1:-}
case $modo in
  ""|--instalar|--status|--remover) ;;
  *) echo "uso: $0 [--instalar | --remover | --status]"; exit 2 ;;
esac

if [[ $modo == --status ]]; then
  if [[ ! -f $PERFIL ]]; then echo "perfil: ausente"
  elif identico; then echo "perfil: instalado"
  else echo "perfil: instalado (diferente do repo)"; fi
  echo "restricao do kernel (apparmor_restrict_unprivileged_userns): $(cat "$AB_SYSCTL" 2>/dev/null || echo desconhecida)"
  echo "bwrap: $(stat -c '%a %U:%G' "$AB_BWRAP" 2>/dev/null || echo ausente); statoverride: $(override)"
  exit 0
fi

[[ -f $PERFIL_REPO ]] || { echo "perfil do repo ausente: $PERFIL_REPO"; exit 1; }

if [[ $modo == --remover ]]; then
  if [[ -f $PERFIL ]]; then
    identico || { echo "recusado: $PERFIL difere do perfil do repo (arquivo do dono); nada removido"; exit 1; }
  fi
  ov=$(override)
  [[ -z $ov || $ov == "$ESPERADO" ]] || { echo "recusado: statoverride do bwrap nao e o nosso ($ov); nada removido"; exit 1; }
  if [[ -f $PERFIL ]]; then
    apparmor_parser -R "$PERFIL"
    rm -f "$PERFIL"
  fi
  if [[ -n $ov ]]; then
    dpkg-statoverride --remove "$AB_BWRAP"
    chown root:root "$AB_BWRAP"; chmod 0755 "$AB_BWRAP"
  fi
  echo "apparmor-bwrap: removido (perfil descarregado, bwrap 0755 root:root)"
  exit 0
fi

# --instalar: toda a validacao antes de qualquer mudanca
[[ -e $AB_BWRAP ]] || { echo "recusado: $AB_BWRAP nao existe (apt install bubblewrap)"; exit 1; }
getent group "$GRUPO" >/dev/null || { echo "recusado: grupo $GRUPO nao existe"; exit 1; }
apparmor_parser -Q -T "$PERFIL_REPO" >/dev/null || { echo "recusado: perfil do repo invalido"; exit 1; }
ov=$(override)
[[ -z $ov || $ov == "$ESPERADO" ]] || { echo "recusado: ja existe statoverride diferente para o bwrap ($ov)"; exit 1; }
if [[ -f $PERFIL ]] && ! identico; then
  echo "recusado: $PERFIL existe e difere do perfil do repo; nao sobrescrevo"; exit 1
fi

feito=0
if ! identico; then
  install -m 0644 "$PERFIL_REPO" "$PERFIL"; chown root:root "$PERFIL"
  feito=1
fi
apparmor_parser -r "$PERFIL"
if [[ $ov != "$ESPERADO" ]]; then
  dpkg-statoverride --update --add root "$GRUPO" 0750 "$AB_BWRAP"
  feito=1
fi
if (( feito )); then echo "apparmor-bwrap: instalado ($PERFIL; $AB_BWRAP 0750 root:$GRUPO)"
else echo "apparmor-bwrap: ja instalado; perfil recarregado"; fi
echo "rollback: sudo $REPO/scripts/47-apparmor-bwrap.sh --remover"
