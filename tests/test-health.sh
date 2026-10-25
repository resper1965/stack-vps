#!/usr/bin/env bash
# shellcheck source=tests/lib.sh
. "$(dirname "$0")/lib.sh"
H=$RAIZ_REPO/bin/health.sh
echo "health (acesso: emergencia, opencode, pmo)"
# Outras secoes dependem da maquina (disco, memoria, backup): assertamos nas linhas, nao no rc global.
prepara() {
  export STACK_CF_DIR=$T/cf HEALTH_PMO_ENV=$T/servidor.env HEALTH_OPENCODE_URL=http://127.0.0.1:4096/ HEALTH_PMO_SOCKET=$T/pmo.sock HEALTH_9ROUTER_UNIT=$T/nao-existe.service HEALTH_9ROUTER_URL=http://127.0.0.1:20128/api/health
  mkdir -p "$STACK_CF_DIR"; printf 'ingress:\n  - service: http_status:404\n' > "$STACK_CF_DIR/config.yml"
  printf 'PMO_HOSTS=pmo.esper.ws,outro.esper.ws\n' > "$HEALTH_PMO_ENV"
  systemctl_com 1; stub tailscale 0 100.1.2.3; stub ip; stub docker; stub df 0 "Use%"
  curl_com 200 200
}
# systemctl_com <rc-do-is-failed>: is-failed devolve esse rc, o resto (is-active, is-enabled) 0
systemctl_com() {
  printf '#!/usr/bin/env bash
echo "systemctl $*" >> "$STUB_LOG"
[[ $1 == is-failed ]] && exit %s
exit 0
' "$1" > "$STUBS/systemctl"
  chmod +x "$STUBS/systemctl"; }
# curl_com <codigo-opencode/9router> <codigo-pmo> [codigo-POST /v1/chat/completions, padrao 401]: o stub distingue pelo --unix-socket e pela URL
curl_com() {
  cat > "$STUBS/curl" <<STUB
#!/usr/bin/env bash
echo "curl \$*" >> "\$STUB_LOG"
[[ "$2" == fail && "\$*" == *--unix-socket* ]] && exit 7
[[ "\$*" == */v1/chat/completions* && "\$*" == *POST* ]] && { printf '%s' "${3:-401}"; exit 0; }
[[ "$1" == fail && "\$*" != *--unix-socket* ]] && exit 7
[[ "\$*" == *--unix-socket* ]] && printf '%s' "$2" || printf '%s' "$1"
STUB
  chmod +x "$STUBS/curl"; }
roda() { saida=$(bash "$H" 2>&1); rc=$?; }
tem() { grep -qF -- "$1" <<<"$saida"; }

novo_tmp; prepara; roda
tem "ok    web de emergência desligada"; afirma "$?" "emergencia desligada: ok"
tem "opencode web" && tem "ok    opencode web"; afirma "$?" "opencode 200: ok"
tem "ok    painel do PMO"; afirma "$?" "pmo 200: ok"
afirma_log "Host: pmo.esper.ws" "pmo: usa o primeiro host de PMO_HOSTS"

novo_tmp; prepara; printf 'ingress:\n  - hostname: emergencia.esper.ws\n    service: http://localhost:4096\n  - service: http_status:404\n' > "$STACK_CF_DIR/config.yml"; roda
tem "FALHA web de emergência ligada"; afirma "$?" "emergencia ligada: FALHA"
afirma_rc "$rc" 1 "emergencia ligada: rc 1"

novo_tmp; prepara; curl_com 401 200; roda
tem "ok    opencode web"; afirma "$?" "opencode 401: ok"
curl_com 302 200; roda; tem "ok    opencode web"; afirma "$?" "opencode 302: ok"
curl_com 500 200; roda; tem "FALHA opencode web"; afirma "$?" "opencode 500: FALHA"
curl_com fail 200; roda; tem "FALHA opencode web"; afirma "$?" "opencode curl falha: FALHA"

novo_tmp; prepara; curl_com 200 fail; roda
tem "FALHA painel do PMO"; afirma "$?" "pmo falha: FALHA"
curl_com 200 502; roda; tem "FALHA painel do PMO"; afirma "$?" "pmo 502: FALHA"

novo_tmp; prepara; rm "$HEALTH_PMO_ENV"; curl_com 200 fail; roda
tem "pend  painel do PMO sem /etc/pmo/servidor.env"; afirma "$?" "sem servidor.env: pend"
! tem "FALHA painel do PMO"; afirma "$?" "sem servidor.env: nao e falha"

# 9router: sem unidade, sem secao; com unidade, /api/health 200 + POST /v1/chat/completions sem chave 401 = ok, senao FALHA
novo_tmp; prepara; roda
! tem "9router"; afirma "$?" "9router sem unidade: sem secao"
touch "$T/9router.service"; export HEALTH_9ROUTER_UNIT=$T/9router.service
roda; tem "ok    9router"; afirma "$?" "9router HTTP 200: ok"
tem "ok    9router exige chave de API"; afirma "$?" "9router POST chat 401 sem chave: ok"
afirma_log "http://127.0.0.1:20128/api/health" "9router: checa /api/health"
curl_com 200 200 200; roda; tem "FALHA 9router sem exigir chave de API"; afirma "$?" "9router POST chat 200 sem chave: FALHA"
afirma_rc "$rc" 1 "9router sem exigir chave: rc 1"
curl_com 200 200 500; roda; tem "FALHA 9router: POST /v1/chat/completions sem chave respondeu 500"; afirma "$?" "9router POST chat 500: FALHA"
curl_com 401 200; roda; tem "FALHA 9router"; afirma "$?" "9router /api/health 401: FALHA"
curl_com 500 200; roda; tem "FALHA 9router"; afirma "$?" "9router HTTP 500: FALHA"
afirma_rc "$rc" 1 "9router HTTP 500: rc 1"
curl_com fail 200; roda; tem "FALHA 9router"; afirma "$?" "9router curl falha: FALHA"
curl_com 307 200; roda; tem "FALHA 9router"; afirma "$?" "9router 307: FALHA"
curl_com 000 200; roda; tem "FALHA 9router"; afirma "$?" "9router parado (HTTP 000): FALHA"
afirma_rc "$rc" 1 "9router parado: rc 1"

# espelho do Linear: is-failed rc 0 = unidade falhou; rc 1 (falhou nao, ou unidade inexistente) = silencio
novo_tmp; prepara; systemctl_com 0; roda
tem "FALHA espelho do Linear"; afirma "$?" "pmo-linear falhou: FALHA"
systemctl_com 1; roda
! tem "espelho do Linear"; afirma "$?" "pmo-linear sem falha: sem linha"

# secao hostinger: comando ausente some; rc 0 repassa a linha; rc 1 vira pend sem FALHA
novo_tmp; prepara; export HEALTH_HOSTINGER=$T/nao-existe; roda
! tem "hostinger"; afirma "$?" "hostinger ausente: sem secao"
printf '#!/usr/bin/env bash\necho "  ok    hostinger cpu 10%% ram 20%% disco 30%%"\n' > "$T/hs"; chmod +x "$T/hs"; export HEALTH_HOSTINGER=$T/hs; roda
tem "ok    hostinger cpu 10% ram 20% disco 30%"; afirma "$?" "hostinger rc 0: linha repassada"
printf '#!/usr/bin/env bash\necho "  FALHA hostinger indisponível"\nexit 1\n' > "$T/hs"; roda
tem "pend  hostinger indisponível"; afirma "$?" "hostinger rc 1: pend"
! grep -E 'FALHA.*hostinger' <<<"$saida" >/dev/null; afirma "$?" "hostinger rc 1: nao e FALHA"
unset HEALTH_HOSTINGER
fim
