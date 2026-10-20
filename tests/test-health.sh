#!/usr/bin/env bash
# shellcheck source=tests/lib.sh
. "$(dirname "$0")/lib.sh"
H=$RAIZ_REPO/bin/health.sh
echo "health (acesso: emergencia, opencode, pmo)"
# Outras secoes dependem da maquina (disco, memoria, backup): assertamos nas linhas, nao no rc global.
prepara() {
  export STACK_CF_DIR=$T/cf HEALTH_PMO_ENV=$T/servidor.env HEALTH_OPENCODE_URL=http://127.0.0.1:4096/ HEALTH_PMO_SOCKET=$T/pmo.sock
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
# unidade dos runners: instalada/ativa/habilitada controladas por STUB_CI_CAT/ACTIVE/ENABLED (padrao: nao instalada)
if [[ $* == *stack-ci-runners* ]]; then
  case $1 in cat) exit "${STUB_CI_CAT:-1}" ;; is-active) exit "${STUB_CI_ACTIVE:-0}" ;; is-enabled) exit "${STUB_CI_ENABLED:-0}" ;; esac
fi
exit 0
' "$1" > "$STUBS/systemctl"
  chmod +x "$STUBS/systemctl"; }
# curl_com <codigo-opencode> <codigo-pmo>: o stub distingue pelo --unix-socket
curl_com() {
  cat > "$STUBS/curl" <<STUB
#!/usr/bin/env bash
echo "curl \$*" >> "\$STUB_LOG"
[[ "$2" == fail && "\$*" == *--unix-socket* ]] && exit 7
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

# secao ci: some sem a unidade; isolamento, servico e status.json (conteudo do arquivo e nao confiavel)
# status_com <segundos-de-idade> <runners> <erro-json>
status_com() {
  printf '{"atualizado": %s, "runners": %s, "erro": %s, "orgs": {}}' "$(python3 -c "import time;print(time.time()-$1)")" "$2" "$3" > "$HEALTH_CI_STATUS"; }
ci_prepara() {
  novo_tmp; prepara; export STUB_CI_CAT=0 STUB_CI_ACTIVE=0 STUB_CI_ENABLED=0
  export HEALTH_CI_STATUS=$T/status.json HEALTH_CI_REDE=$T/rede.sh
  printf '#!/usr/bin/env bash\necho ativa\n' > "$HEALTH_CI_REDE"; chmod +x "$HEALTH_CI_REDE"
  status_com 0 3 null
}
ci_sec() { sed -n '/^ci$/,/^disco$/p' <<<"$saida"; }

novo_tmp; prepara; unset STUB_CI_CAT; roda
! grep -qx 'ci' <<<"$saida"; afirma "$?" "ci: unidade ausente, sem secao"
! grep -qE 'runners|conta ci' <<<"$saida"; afirma "$?" "ci: unidade ausente, sem nenhuma linha de ci"

ci_prepara; roda
tem "ok    isolamento de rede da conta ci"; afirma "$?" "ci: isolamento ativo ok"
tem "ok    runners (3)"; afirma "$?" "ci: saudavel com 3 runners"
grep -cx 'ci' <<<"$saida" | grep -qx 1; afirma "$?" "ci: cabecalho unico"
! ci_sec | grep -q FALHA; afirma "$?" "ci: saudavel sem FALHA"
status_com 5 0 null; roda; tem "ok    runners (0)"; afirma "$?" "ci: zero runners nao e falha"

ci_prepara; printf '#!/usr/bin/env bash\necho inativa\nexit 1\n' > "$HEALTH_CI_REDE"; roda
tem "FALHA isolamento de rede da conta ci inativo"; afirma "$?" "ci: isolamento inativo: FALHA"
afirma_rc "$rc" 1 "ci: isolamento inativo: rc 1"
rm "$HEALTH_CI_REDE"; roda
tem "FALHA isolamento de rede da conta ci inativo (sem 39-ci-rede.sh)"; afirma "$?" "ci: script de rede ausente: FALHA"

ci_prepara; export STUB_CI_ACTIVE=3; roda
tem "FALHA runners parados (stack-ci-runners inativo)"; afirma "$?" "ci: parado e habilitado: FALHA"
afirma_rc "$rc" 1 "ci: parado e habilitado: rc 1"
! tem "runners ("; afirma "$?" "ci: parado: nao le o status"
export STUB_CI_ENABLED=1; roda
tem "pend  runners instalados, mas não habilitados"; afirma "$?" "ci: nao habilitado: pend"
! ci_sec | grep -q FALHA; afirma "$?" "ci: nao habilitado: sem FALHA"

ci_prepara; rm "$HEALTH_CI_STATUS"; roda
tem "FALHA runners sem status (arquivo ausente ou inválido)"; afirma "$?" "ci: status ausente: FALHA"
afirma_rc "$rc" 1 "ci: status ausente: rc 1"
ci_prepara; printf '{"atualizado": %s, "runners": 3, "erro": null, "marca": "SEGREDO-NO-ALVO"}' "$(date +%s)" > "$T/alvo"
rm "$HEALTH_CI_STATUS"; ln -s "$T/alvo" "$HEALTH_CI_STATUS"; roda
tem "FALHA runners sem status"; afirma "$?" "ci: symlink recusado mesmo com conteudo valido"
! tem "SEGREDO-NO-ALVO"; afirma "$?" "ci: symlink: conteudo do alvo nao aparece"
for ruim in 'nao-e-json' '[]' '{"atualizado": "x", "runners": 1, "erro": null}' '{"atualizado": 1, "runners": "3", "erro": null}' \
  '{"atualizado": true, "runners": 1, "erro": null}' '{"atualizado": 1, "runners": 1.5, "erro": null}' '{"atualizado": 1, "runners": 1}' \
  '{"atualizado": 1, "runners": 1, "erro": 5}' '{"atualizado": NaN, "runners": 1, "erro": null}'; do
  ci_prepara; printf '%s' "$ruim" > "$HEALTH_CI_STATUS"; roda
  tem "FALHA runners sem status (arquivo ausente ou inválido)"; afirma "$?" "ci: status invalido ($ruim)"
done
ci_prepara; status_com 5 3 '"$(rm -rf /) <script>alert(1)</script> SEGREDO"'; roda
tem "FALHA runners com erro registrado (ver journalctl -u stack-ci-runners)"; afirma "$?" "ci: erro registrado: FALHA fixa"
! grep -qE 'rm -rf|script|SEGREDO' <<<"$saida"; afirma "$?" "ci: texto do erro nunca impresso"
afirma_rc "$rc" 1 "ci: erro registrado: rc 1"
ci_prepara; status_com 200 3 null; roda
tem "FALHA runners sem atualização há 3 min"; afirma "$?" "ci: status velho (200 s): FALHA"
afirma_rc "$rc" 1 "ci: status velho: rc 1"
ci_prepara; status_com -120 3 null; roda
tem "FALHA runners sem status"; afirma "$?" "ci: timestamp no futuro (+120 s): FALHA"
ci_prepara; status_com -30 3 null; roda
tem "ok    runners (3)"; afirma "$?" "ci: futuro dentro da tolerancia (+30 s): ok"
ci_prepara; head -c 200000 /dev/zero | tr '\0' 'A' > "$HEALTH_CI_STATUS"; roda
tem "FALHA runners sem status"; afirma "$?" "ci: arquivo enorme: FALHA sem travar"
ci_prepara; { printf '{"atualizado": %s, "runners": 3, "erro": null' "$(date +%s)"; head -c 70000 /dev/zero | tr '\0' ' '; printf '}'; } > "$HEALTH_CI_STATUS"; roda
tem "FALHA runners sem status"; afirma "$?" "ci: JSON valido acima de 64 KiB: FALHA"
unset STUB_CI_CAT STUB_CI_ACTIVE STUB_CI_ENABLED HEALTH_CI_STATUS HEALTH_CI_REDE
fim
