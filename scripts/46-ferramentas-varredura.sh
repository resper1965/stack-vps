#!/usr/bin/env bash
# Ferramentas de varredura dos jobs (jobs/bin/varredura.sh): Semgrep (pipx), gitleaks e osv-scanner
# (binarios de release, versao FIXA, SHA-256 LITERAL conferido ANTES de extrair ou executar qualquer coisa).
# Instala em ~/.local/bin. Hash divergente: recusa, apaga o download e nao instala. Idempotente: um marcador
# por versao instalada evita baixar de novo. Nao altera nenhum projeto.
# Uso: sudo -u agente -H bash -c 'cd ~ && /opt/stack-vps/scripts/46-ferramentas-varredura.sh'
# Sobrescreviveis nos testes (so com STACK_TESTE=1): VS_PREFIX VS_CURL VS_PIPX VS_SHA_GITLEAKS VS_SHA_OSV.
set -euo pipefail
umask 022
[[ $(id -un) == agente || ${STACK_TESTE:-} == 1 ]] || { echo "rode como agente"; exit 1; }

SEMGREP_VERSAO=1.182.1
GITLEAKS_VERSAO=8.30.1
OSV_VERSAO=2.7.0
# Fonte: gitleaks_8.30.1_checksums.txt e osv-scanner_SHA256SUMS das releases oficiais (conferidos em 2026-10-25).
SHA_GITLEAKS=551f6fc83ea457d62a0d98237cbad105af8d557003051f41f3e7ca7b3f2470eb  # gitleaks_8.30.1_linux_x64.tar.gz
SHA_OSV=160c6253e2922e9e0a6a9771c5c4c40a4b3c6090b34a3cdd5e80c96cc2e4218b        # osv-scanner_linux_amd64
PREFIXO=$HOME/.local
CURL=curl
PIPX=pipx
if [[ ${STACK_TESTE:-} == 1 ]]; then
  PREFIXO=${VS_PREFIX:-$PREFIXO}; CURL=${VS_CURL:-$CURL}; PIPX=${VS_PIPX:-$PIPX}
  SHA_GITLEAKS=${VS_SHA_GITLEAKS:-$SHA_GITLEAKS}; SHA_OSV=${VS_SHA_OSV:-$SHA_OSV}
fi
BIN=$PREFIXO/bin
MARCAS=$PREFIXO/share/stack-ferramentas
install -d "$BIN" "$MARCAS"

tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT

# baixa <url> <arquivo> <sha256-esperado>: confere o hash antes de qualquer uso; divergiu = apaga e para
baixa() {
  "$CURL" -fsSL --proto '=https' --tlsv1.2 --retry 3 -o "$2" "$1" || { echo "falha ao baixar $1"; exit 1; }
  local got; got=$(sha256sum "$2" | cut -d' ' -f1)
  if [[ $got != "$3" ]]; then
    rm -f "$2"; echo "SHA-256 divergente em $1 (esperado ${3:0:12}..., veio ${got:0:12}...): nao instalei"; exit 1
  fi
}

# gitleaks: tar.gz; so o membro "gitleaks" e extraido, depois do hash
if [[ -e $MARCAS/gitleaks-$GITLEAKS_VERSAO && -x $BIN/gitleaks ]]; then echo "gitleaks $GITLEAKS_VERSAO ja instalado"
else
  baixa "https://github.com/gitleaks/gitleaks/releases/download/v$GITLEAKS_VERSAO/gitleaks_${GITLEAKS_VERSAO}_linux_x64.tar.gz" \
    "$tmp/gitleaks.tgz" "$SHA_GITLEAKS"
  tar -xzf "$tmp/gitleaks.tgz" -C "$tmp" gitleaks
  install -m 755 "$tmp/gitleaks" "$BIN/gitleaks"
  : > "$MARCAS/gitleaks-$GITLEAKS_VERSAO"; echo "gitleaks $GITLEAKS_VERSAO instalado"
fi

# osv-scanner: binario unico
if [[ -e $MARCAS/osv-scanner-$OSV_VERSAO && -x $BIN/osv-scanner ]]; then echo "osv-scanner $OSV_VERSAO ja instalado"
else
  baixa "https://github.com/google/osv-scanner/releases/download/v$OSV_VERSAO/osv-scanner_linux_amd64" \
    "$tmp/osv-scanner" "$SHA_OSV"
  install -m 755 "$tmp/osv-scanner" "$BIN/osv-scanner"
  : > "$MARCAS/osv-scanner-$OSV_VERSAO"; echo "osv-scanner $OSV_VERSAO instalado"
fi

# semgrep: wheel do PyPI em venv do pipx, versao fixa (o PyPI valida o hash do arquivo pelo indice, nao pelo script)
if [[ -e $MARCAS/semgrep-$SEMGREP_VERSAO && -x $BIN/semgrep ]]; then echo "semgrep $SEMGREP_VERSAO ja instalado"
else
  command -v "$PIPX" >/dev/null 2>&1 || { echo "falta o pipx (instale pelo 03-tooling.sh ou apt install pipx)"; exit 1; }
  PIPX_BIN_DIR=$BIN "$PIPX" install --force "semgrep==$SEMGREP_VERSAO"
  : > "$MARCAS/semgrep-$SEMGREP_VERSAO"; echo "semgrep $SEMGREP_VERSAO instalado"
fi
echo "ferramentas de varredura prontas em $BIN"
