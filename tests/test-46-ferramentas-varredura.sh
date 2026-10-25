#!/usr/bin/env bash
# shellcheck source=tests/lib.sh
. "$(dirname "$0")/lib.sh"
S=$RAIZ_REPO/scripts/46-ferramentas-varredura.sh
echo "46-ferramentas-varredura (SHA-256 literal conferido antes de extrair ou executar)"

# Mundo falso: curl serve um tar.gz com um "gitleaks" e um "osv-scanner" que registram EXECUTADO se rodarem.
prepara() {
  novo_tmp
  export HOME=$T/home VS_PREFIX=$T/prefix VS_CURL=$STUBS/curl VS_PIPX=$STUBS/pipx
  # pipx falso: registra o argv e cria o binario do semgrep onde o pipx real o poria (PIPX_BIN_DIR)
  printf '#!/usr/bin/env bash
echo "pipx $*" >> "%s"
install -d "$PIPX_BIN_DIR"; : > "$PIPX_BIN_DIR/semgrep"; chmod +x "$PIPX_BIN_DIR/semgrep"
' "$STUB_LOG" > "$STUBS/pipx"; chmod +x "$STUBS/pipx"
  mkdir -p "$HOME" "$T/srv/x"
  printf '#!/usr/bin/env bash\necho "EXECUTADO gitleaks" >> "%s"\n' "$STUB_LOG" > "$T/srv/x/gitleaks"; chmod +x "$T/srv/x/gitleaks"
  tar -czf "$T/srv/gitleaks.tgz" -C "$T/srv/x" gitleaks
  printf '#!/usr/bin/env bash\necho "EXECUTADO osv" >> "%s"\n' "$STUB_LOG" > "$T/srv/osv-scanner"; chmod +x "$T/srv/osv-scanner"
  cat > "$STUBS/curl" <<STUB
#!/usr/bin/env bash
echo "curl \$*" >> "$STUB_LOG"
while [[ \$# -gt 1 ]]; do [[ \$1 == -o ]] && { o=\$2; }; shift; done; u=\$1
case \$u in *gitleaks*) cp "$T/srv/gitleaks.tgz" "\$o" ;; *osv-scanner*) cp "$T/srv/osv-scanner" "\$o" ;; *) exit 22 ;; esac
STUB
  chmod +x "$STUBS/curl"
  SG=$(sha256sum "$T/srv/gitleaks.tgz" | cut -d' ' -f1); SO=$(sha256sum "$T/srv/osv-scanner" | cut -d' ' -f1)
  export VS_SHA_GITLEAKS=$SG VS_SHA_OSV=$SO
}
roda() { bash "$S" > "$T/saida" 2>&1; RC=$?; }

prepara; roda; afirma_rc $RC 0 "instala com hashes conferidos"
[[ -x $VS_PREFIX/bin/gitleaks && -x $VS_PREFIX/bin/osv-scanner ]] && r=0 || r=1; afirma $r "binarios em bin/ executaveis"
afirma_log "pipx install --force semgrep==1.182.1" "semgrep com versao fixa pelo pipx"
afirma_log "https://github.com/gitleaks/gitleaks/releases/download/v8.30.1/gitleaks_8.30.1_linux_x64.tar.gz" "URL fixa do gitleaks"
afirma_log "https://github.com/google/osv-scanner/releases/download/v2.7.0/osv-scanner_linux_amd64" "URL fixa do osv-scanner"
nega_log EXECUTADO "nada baixado foi executado na instalacao"
n=$(grep -c '^curl' "$STUB_LOG"); : > "$STUB_LOG"; roda; afirma_rc $RC 0 "segunda execucao"
nega_log curl "idempotente: nao baixa de novo"; nega_log "pipx install" "idempotente: nao reinstala o semgrep"
[[ $n == 2 ]] && r=0 || r=1; afirma $r "primeira execucao baixou exatamente 2 arquivos"

# hash divergente no gitleaks: recusa, nada instalado, nada executado
prepara; export VS_SHA_GITLEAKS=0000000000000000000000000000000000000000000000000000000000000000
roda; afirma_rc $RC 1 "hash do gitleaks divergente recusa"
grep -q "SHA-256 divergente" "$T/saida"; afirma $? "mensagem de hash divergente"
[[ ! -e $VS_PREFIX/bin/gitleaks && ! -e $VS_PREFIX/bin/osv-scanner ]] && r=0 || r=1; afirma $r "nada instalado"
nega_log EXECUTADO "nada executado"; nega_log "pipx install" "semgrep nao instalado apos falha de hash"
# hash divergente no osv-scanner: o gitleaks (conferido) fica, o osv nao
prepara; export VS_SHA_OSV=1111111111111111111111111111111111111111111111111111111111111111
roda; afirma_rc $RC 1 "hash do osv-scanner divergente recusa"
[[ ! -e $VS_PREFIX/bin/osv-scanner ]] && r=0 || r=1; afirma $r "osv-scanner nao instalado"; nega_log EXECUTADO "osv nao executado"
# hashes LITERAIS do script: sem sobrescrita, o conteudo falso (sem o hash oficial) e recusado
prepara; unset VS_SHA_GITLEAKS VS_SHA_OSV; roda; afirma_rc $RC 1 "hashes literais do script recusam conteudo falso"
grep -q '551f6fc83ea457d62a0d98237cbad105af8d557003051f41f3e7ca7b3f2470eb' "$S" && grep -q '160c6253e2922e9e0a6a9771c5c4c40a4b3c6090b34a3cdd5e80c96cc2e4218b' "$S"; afirma $? "hashes oficiais fixados no script"
# falha de download
prepara; printf '#!/usr/bin/env bash\nexit 22\n' > "$STUBS/curl"; roda; afirma_rc $RC 1 "download falho recusa"
# so o agente roda
prepara; env -u STACK_TESTE bash "$S" > "$T/saida" 2>&1; RC=$?
if [[ $(id -un) == agente ]]; then ok "(ja e agente)"; else afirma_rc $RC 1 "recusa fora do agente"; fi
fim
