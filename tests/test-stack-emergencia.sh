#!/usr/bin/env bash
# shellcheck source=tests/lib.sh
. "$(dirname "$0")/lib.sh"
S=$RAIZ_REPO/bin/stack-emergencia
echo "stack-emergencia"
prepara() {
  export STACK_CF_DIR=$T/cf EMERGENCIA_ALERTAR=$STUBS/alertar; mkdir -p "$STACK_CF_DIR"
  stub systemctl; stub alertar
  cat > "$STACK_CF_DIR/config.yml" <<'YML'
tunnel: abc
ingress:
  - hostname: a.esper.ws
    service: http://localhost:1
  - hostname: b.esper.ws
    service: http://localhost:2
  - service: http_status:404
YML
}
regras() { grep -c 'hostname: emergencia.esper.ws' "$STACK_CF_DIR/config.yml"; }

novo_tmp; prepara
afirma_rc "$(bash "$S" status)" desligada "status inicial: desligada"
bash "$S" on >/dev/null 2>&1; afirma_rc "$?" 0 "on: rc 0"
afirma_rc "$(regras)" 1 "on: uma regra"
afirma_rc "$(grep -A2 'hostname: emergencia' "$STACK_CF_DIR/config.yml" | tail -2 | tr '\n' '|')" \
  "    service: http://localhost:4096|  - service: http_status:404|" "on: antes do catch-all, indentacao igual"
grep -q 'hostname: a.esper.ws' "$STACK_CF_DIR/config.yml" && grep -q 'hostname: b.esper.ws' "$STACK_CF_DIR/config.yml"
afirma "$?" "on: mantem as outras regras"
afirma_rc "$(bash "$S" status)" ligada "status: ligada"
afirma_log "systemctl restart cloudflared" "on: reinicia o cloudflared"
afirma_log "alertar stack: emergência LIGADA" "on: alerta LIGADA"
bash "$S" on >/dev/null 2>&1; afirma_rc "$(regras)" 1 "on duas vezes: ainda uma regra"
: > "$STUB_LOG"
bash "$S" off >/dev/null 2>&1; afirma_rc "$(regras)" 0 "off: remove"
afirma_rc "$(wc -l < "$STACK_CF_DIR/config.yml")" 7 "off: config volta ao original"
afirma_rc "$(bash "$S" status)" desligada "status: desligada"
afirma_log "alertar stack: emergência desligada" "off: alerta desligada"
afirma_log "systemctl restart cloudflared" "off: reinicia o cloudflared"

novo_tmp; prepara
bash "$S" xpto >/dev/null 2>&1; afirma_rc "$?" 2 "argumento invalido: rc 2"
bash "$S" >/dev/null 2>&1; afirma_rc "$?" 2 "sem argumento: rc 2"

novo_tmp; prepara; printf 'ingress:\n  - hostname: a.esper.ws\n    service: http://localhost:1\n' > "$STACK_CF_DIR/config.yml"
antes=$(cat "$STACK_CF_DIR/config.yml")
bash "$S" on >/dev/null 2>&1; afirma_rc "$?" 1 "on sem catch-all: rc 1"
afirma_rc "$(cat "$STACK_CF_DIR/config.yml")" "$antes" "on sem catch-all: config intacta"
nega_log "systemctl restart" "on sem catch-all: nao reinicia"

novo_tmp; prepara; rm "$STACK_CF_DIR/config.yml"
bash "$S" on >/dev/null 2>&1; afirma_rc "$?" 1 "on sem config.yml: rc 1"
afirma_rc "$(bash "$S" status)" desligada "status sem config: desligada"

novo_tmp; prepara; stub alertar 1
bash "$S" on >/dev/null 2>&1; afirma_rc "$?" 0 "alerta falhou: comando segue com rc 0"

for modo in on off; do
  novo_tmp; prepara; [[ $modo == off ]] && bash "$S" on >/dev/null 2>&1
  : > "$STUB_LOG"
  printf '#!/usr/bin/env bash\nprintf partial\nexit 1\n' > "$STUBS/awk"; chmod +x "$STUBS/awk"
  antes=$(cat "$STACK_CF_DIR/config.yml")
  bash "$S" "$modo" >/dev/null 2>&1; rc=$?
  afirma "$(( rc == 0 ))" "$modo com awk falhando: rc != 0"
  afirma_rc "$(cat "$STACK_CF_DIR/config.yml")" "$antes" "$modo com awk falhando: config intacta"
  afirma_rc "$(find "$STACK_CF_DIR" -type f | wc -l)" 1 "$modo com awk falhando: sem temporario sobrando"
  nega_log "systemctl restart" "$modo com awk falhando: nao reinicia"
done
fim
