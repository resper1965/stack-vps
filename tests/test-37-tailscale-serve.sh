#!/usr/bin/env bash
# shellcheck source=tests/lib.sh
. "$(dirname "$0")/lib.sh"
S=$RAIZ_REPO/scripts/37-tailscale-serve.sh
echo "37-tailscale-serve"

ts_stub() { # tailscale: registra tudo; status --json devolve o nome da maquina
  cat > "$STUBS/tailscale" <<'EOS'
#!/usr/bin/env bash
echo "tailscale $*" >> "$STUB_LOG"
[[ $1 == status && ${2:-} == --json ]] && echo '{"Self":{"DNSName":"stack.exemplo.ts.net."}}'
exit 0
EOS
  chmod +x "$STUBS/tailscale"; }

novo_tmp; ts_stub; stub systemctl 0
out=$(bash "$S" 2>&1); afirma_rc $? 0 "publica"
afirma_log "tailscale serve --bg --https=443 http://127.0.0.1:4096" "OpenCode em 443"
afirma_log "tailscale serve --bg --https=8443 unix:/run/pmo/pmo.sock" "PMO em 8443 por socket"
if [[ $out == *"https://stack.exemplo.ts.net"* && $out == *"https://stack.exemplo.ts.net:8443"* ]]; then ok "imprime as URLs com o nome da tailnet"; else falha "imprime as URLs"; fi

bash "$S" >/dev/null 2>&1; afirma_rc $? 0 "segunda execucao"
n=$(grep '^tailscale serve --bg' "$STUB_LOG" | sort -u | wc -l)
if [[ $n == 2 ]]; then ok "reaplicar mantem exatamente 2 alvos distintos (veio $n)"; else falha "reaplicar mantem exatamente 2 alvos distintos (veio $n)"; fi

novo_tmp; ts_stub; stub systemctl 3
out=$(bash "$S" 2>&1); afirma_rc $? 1 "tailscaled inativo: recusa"
if [[ $out == *tailscaled* ]]; then ok "diz que o tailscaled nao esta ativo"; else falha "diz que o tailscaled nao esta ativo"; fi
nega_log "tailscale serve" "inativo: nao chama serve"

novo_tmp; ts_stub; stub systemctl 0
cat > "$STUBS/tailscale" <<'EOS'
#!/usr/bin/env bash
echo "tailscale $*" >> "$STUB_LOG"
[[ $1 == status ]] && echo 'lixo'
exit 0
EOS
bash "$S" >/dev/null 2>&1; afirma_rc $? 0 "nome da tailnet ilegivel: nao falha"

novo_tmp; ts_stub; stub systemctl 0
env -u STACK_TESTE bash "$S" >/dev/null 2>&1; rc=$?
if [[ $EUID -ne 0 ]]; then afirma_rc $rc 1 "sem root: recusa"; nega_log "tailscale serve" "sem root: nao chama serve"; else ok "rodando como root: caso nao-root pulado"; fi
fim
