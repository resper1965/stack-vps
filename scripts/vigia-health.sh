#!/usr/bin/env bash
# Roda o health.sh e alerta quando o conjunto de falhas muda: falha nova, falha resolvida ou volta
# ao ok. Uma falha cronica (ex.: reboot pendente) nao silencia as que aparecerem depois.
# O estado novo so e gravado se o alerta foi entregue; senao, a proxima rodada tenta de novo.
set -uo pipefail
HEALTH=${VIGIA_HEALTH:-/usr/local/lib/stack-vps/health.sh}
ALERTAR=${VIGIA_ALERTAR:-/usr/local/lib/stack-vps/alertar.sh}
ESTADO=${VIGIA_ESTADO:-/var/lib/stack-vps/health.estado}
LIMITE=${VIGIA_TIMEOUT:-120}
mkdir -p "$(dirname "$ESTADO")"; touch "$ESTADO"

saida=$(timeout "$LIMITE" "$HEALTH" 2>&1); rc=$?
(( rc == 124 )) && saida+=$'\n'"  FALHA health travou (mais de ${LIMITE}s)"
agora=$(grep -o 'FALHA.*' <<< "$saida" | sed 's/ *$//' | sort -u)
antes=$(cat "$ESTADO")

if [[ $agora != "$antes" ]]; then
  novas=$(comm -13 <(echo "$antes") <(echo "$agora") | sed '/^$/d')
  resolvidas=$(comm -23 <(echo "$antes") <(echo "$agora") | sed '/^$/d')
  if [[ -z $agora ]]; then titulo="stack: recuperado"; msg="health.sh voltou a passar"
  else titulo="stack: FALHA"; msg="novas:
${novas:-(nenhuma)}
resolvidas:
${resolvidas:-(nenhuma)}"; fi
  if "$ALERTAR" "$titulo" "$msg"; then echo "$agora" > "$ESTADO"; fi
fi
echo "$saida"
