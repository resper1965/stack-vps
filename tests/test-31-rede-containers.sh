#!/usr/bin/env bash
# shellcheck source=tests/lib.sh
. "$(dirname "$0")/lib.sh"
S=$RAIZ_REPO/scripts/31-rede-containers.sh
echo "31-rede-containers"
novo_tmp
cat > "$STUBS/iptables" <<'EOS'
#!/usr/bin/env bash
echo "iptables $*" >> "$STUB_LOG"; [[ $1 == -C ]] && exit 1; exit 0
EOS
chmod +x "$STUBS/iptables"
bash "$S" >/dev/null 2>&1; afirma_rc $? 0 "aplica"
afirma_log "iptables -I DOCKER-USER 1 -d 100.64.0.0/10 -j DROP" "bloqueia a tailnet"
afirma_log "iptables -I DOCKER-USER 1 -d 169.254.169.254/32 -j DROP" "bloqueia o metadata"
fim
