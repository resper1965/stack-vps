#!/usr/bin/env bash
# shellcheck source=tests/lib.sh
. "$(dirname "$0")/lib.sh"
V=$RAIZ_REPO/jobs/bin/varredura.sh; D=$RAIZ_REPO/jobs/bin/dnscheck.sh; B=$RAIZ_REPO/jobs/bin/backup-n360.sh
SEGREDO="SEGREDO-ACHADO-pelo-gitleaks-321"
echo "jobs/bin (varredura, dnscheck, backup-n360) com ferramentas stub e sentinelas"

# ---------- varredura ----------
vmundo() {
  novo_tmp; export HOME=$T/home VARREDURA_ESTADO=$T/estado; mkdir -p "$HOME" "$T/clone"
  export SG_JSON='{"results":[]}' GL_JSON='[]' OSV_JSON='{"results":[]}' OSV_RC=0 SG_FALHA=
  # semgrep: grava os dois relatorios; gitleaks: grava o relatorio (redigido) e VAZA o segredo na saida (a varredura deve calar);
  # osv-scanner: JSON no stdout
  cat > "$STUBS/semgrep" <<'STUB'
#!/usr/bin/env bash
echo "semgrep $*" >> "$STUB_LOG"
[[ -n $SG_FALHA ]] && exit 2
while [[ $# -gt 0 ]]; do case $1 in --json-output) printf '%s' "$SG_JSON" > "$2";; --sarif-output) echo '{}' > "$2";; esac; shift; done
exit 0
STUB
  cat > "$STUBS/gitleaks" <<'STUB'
#!/usr/bin/env bash
echo "gitleaks $*" >> "$STUB_LOG"
while [[ $# -gt 0 ]]; do [[ $1 == --report-path ]] && printf '%s' "$GL_JSON" > "$2"; shift; done
echo "Finding: Secret: SEGREDO-ACHADO-pelo-gitleaks-321"; echo "Secret: SEGREDO-ACHADO-pelo-gitleaks-321" >&2
exit 0
STUB
  cat > "$STUBS/osv-scanner" <<'STUB'
#!/usr/bin/env bash
echo "osv-scanner $*" >> "$STUB_LOG"
[[ $OSV_RC == 128 ]] || printf '%s' "$OSV_JSON"
exit "$OSV_RC"
STUB
  chmod +x "$STUBS"/semgrep "$STUBS"/gitleaks "$STUBS"/osv-scanner
}
vroda() { bash "$V" "$T/clone" projx > "$T/saida" 2>&1; RC=$?; }
osvj() { printf '{"results":[{"packages":[{"vulnerabilities":[%s],"groups":[%s]}]}]}' "$1" "$2"; }

vmundo; vroda; afirma_rc $RC 0 "varredura limpa: rc 0"
[[ $(wc -l < "$T/saida") == 1 ]] && r=0 || r=1; afirma $r "varredura: resumo em uma linha"
grep -q 'segredos=0' "$T/saida" && grep -q 'ok$' "$T/saida"; afirma $? "varredura: resumo diz ok e zero segredos"
[[ -f $T/estado/projx.varredura/semgrep.sarif && -f $T/estado/projx.varredura/gitleaks.json && -f $T/estado/projx.varredura/osv.json ]] && r=0 || r=1; afirma $r "varredura: relatorios gravados em <nome>.varredura"
afirma_log "--redact" "varredura: gitleaks com --redact"
afirma_log "--config p/default" "varredura: semgrep com p/default"
! grep -qF -- "$SEGREDO" "$T/saida"; afirma $? "varredura: nada do segredo na saida"

vmundo; export GL_JSON='[{"RuleID":"x","Secret":"REDACTED","Match":"REDACTED"}]'; vroda
afirma_rc $RC 10 "varredura: segredo achado => rc 10"; grep -q 'segredos=1' "$T/saida"; afirma $? "varredura: conta o segredo"
! grep -qF -- "$SEGREDO" "$T/saida" && ! grep -rqF -- "$SEGREDO" "$T/estado"; afirma $? "varredura: segredo achado nunca impresso nem gravado"

vmundo; export SG_JSON='{"results":[{"extra":{"severity":"ERROR"}},{"extra":{"severity":"WARNING"}},{"extra":{"severity":"INFO"}}]}'; vroda
afirma_rc $RC 10 "varredura: semgrep ERROR => rc 10"; grep -q 'ERROR=1 WARNING=1 INFO=1' "$T/saida"; afirma $? "varredura: conta por severidade (semgrep)"
grep -q 'ACHADOS (' "$T/saida" && ! grep -q REPROVADO "$T/saida"; afirma $? "varredura: resumo diz ACHADOS, nao REPROVADO"
vmundo; export SG_JSON='{"results":[{"extra":{"severity":"WARNING"}},{"extra":{"severity":"INFO"}}]}'; vroda
afirma_rc $RC 0 "varredura: so WARNING/INFO => rc 0"

vmundo; OSV_JSON=$(osvj '{"id":"A"}' '{"ids":["A"],"max_severity":"8.1"}'); export OSV_JSON OSV_RC=1; vroda
afirma_rc $RC 10 "varredura: osv HIGH (CVSS 8.1) => rc 10"; grep -q 'HIGH=1' "$T/saida"; afirma $? "varredura: conta HIGH"
vmundo; OSV_JSON=$(osvj '{"id":"A"}' '{"ids":["A"],"max_severity":"9.8"}'); export OSV_JSON OSV_RC=1; vroda
afirma_rc $RC 10 "varredura: osv CRITICAL => rc 10"; grep -q 'CRITICAL=1' "$T/saida"; afirma $? "varredura: conta CRITICAL"
vmundo; OSV_JSON=$(osvj '{"id":"A","database_specific":{"severity":"CRITICAL"}}' '{"ids":["A"]}'); export OSV_JSON OSV_RC=1; vroda
afirma_rc $RC 10 "varredura: osv CRITICAL so por rotulo => rc 10"
vmundo; OSV_JSON=$(osvj '{"id":"A"},{"id":"B","database_specific":{"severity":"MODERATE"}}' '{"ids":["A"],"max_severity":"5.0"},{"ids":["B"]}'); export OSV_JSON OSV_RC=1; vroda
afirma_rc $RC 0 "varredura: osv so MEDIUM => rc 0"; grep -q 'MEDIUM=2' "$T/saida"; afirma $? "varredura: MODERATE conta como MEDIUM"
vmundo; export OSV_RC=128; vroda; afirma_rc $RC 0 "varredura: osv sem dependencias (128) => rc 0"
vmundo; export OSV_RC=2; vroda; afirma_rc $RC 2 "varredura: osv com erro => rc 2"

vmundo; export SG_FALHA=1; vroda; afirma_rc $RC 2 "varredura: semgrep sem relatorio => rc 2"
vmundo; rm "$STUBS/gitleaks"; export PATH="$STUBS:/usr/bin:/bin"; vroda; afirma_rc $RC 2 "varredura: ferramenta ausente => rc 2"
grep -q 'ferramenta ausente (gitleaks)' "$T/saida"; afirma $? "varredura: mensagem cita a ferramenta ausente"
nega_log semgrep "varredura: nada roda se falta ferramenta"
vmundo; bash "$V" > "$T/saida" 2>&1; afirma_rc $? 2 "varredura: sem argumentos => uso"
bash "$V" "$T/nao-existe" projx > "$T/saida" 2>&1; afirma_rc $? 2 "varredura: diretorio inexistente => uso"
bash "$V" "$T/clone" "../x" > "$T/saida" 2>&1; afirma_rc $? 2 "varredura: nome invalido => uso"

# ---------- dnscheck ----------
TOKEN="CF-TOKEN-sentinela-555"; HOST="HOST-TOKEN-sentinela-777"
dmundo() {
  novo_tmp; export DNSCHECK_ESTADO=$T/estado CLOUDFLARE_API_TOKEN=$TOKEN DNS_RC=0 WP_RC=0; unset HOSTINGER_API
  mkdir -p "$T/clone"
  printf 'import os,sys\nprint("=== z.com: 3 registros ===")\nif os.environ["DNS_RC"] != "0": print("  FAIL x voltou"); print("  WARN y"); print("  WARN z")\nprint("  OK   a")\nsys.exit(int(os.environ["DNS_RC"]))\n' > "$T/clone/dnscheck.py"
  printf 'import os,sys\nprint("wp")\nsys.exit(int(os.environ["WP_RC"]))\n' > "$T/clone/wpaudit.py"
}
droda() { (cd "$T/clone" && bash "$D") > "$T/saida" 2>&1; RC=$?; }
semsegredo() { ! grep -qF -- "$TOKEN" "$T/saida" && ! grep -qF -- "$HOST" "$T/saida"; afirma $? "dnscheck: $1: tokens fora da saida"; }

dmundo; droda; afirma_rc $RC 0 "dnscheck: sem divergencia => rc 0"; semsegredo "ok"
[[ $(wc -l < "$T/saida") == 1 ]] && r=0 || r=1; afirma $r "dnscheck: resumo em uma linha"
[[ ! -e $T/estado/dns-repair-dnscheck.saida/wpaudit.txt ]] && r=0 || r=1; afirma $r "dnscheck: sem HOSTINGER_API nao roda wpaudit"
dmundo; export DNS_RC=1; droda; afirma_rc $RC 1 "dnscheck: divergencia => rc 1"
grep -q 'FAIL=1 WARN=2' "$T/saida"; afirma $? "dnscheck: resumo conta FAIL e WARN"; semsegredo "divergencia"
dmundo; export DNS_RC=2; droda; afirma_rc $RC 2 "dnscheck: erro de execucao => rc 2"
dmundo; export HOSTINGER_API=$HOST WP_RC=1; droda; afirma_rc $RC 1 "dnscheck: wpaudit 1 => rc 1"
[[ -f $T/estado/dns-repair-dnscheck.saida/wpaudit.txt ]] && r=0 || r=1; afirma $r "dnscheck: wpaudit rodou com HOSTINGER_API"; semsegredo "wpaudit"
dmundo; export HOSTINGER_API=$HOST WP_RC=0; droda; afirma_rc $RC 0 "dnscheck: wpaudit ok => rc 0"
dmundo; export HOSTINGER_API=$HOST WP_RC=2; droda; afirma_rc $RC 2 "dnscheck: wpaudit erro => rc 2"
dmundo; export DNS_RC=1 HOSTINGER_API=$HOST WP_RC=2; droda; afirma_rc $RC 2 "dnscheck: erro vence divergencia"
dmundo; unset CLOUDFLARE_API_TOKEN; droda; afirma_rc $RC 2 "dnscheck: sem CLOUDFLARE_API_TOKEN => rc 2"
dmundo; rm "$T/clone/dnscheck.py"; droda; afirma_rc $RC 2 "dnscheck: sem dnscheck.py => rc 2"

# ---------- backup-n360 ----------
URL='postgres://usuario:SENHA-sentinela-URL-888@db.exemplo.invalid:5432/postgres?sslmode=require'; PASS='frase secreta/sentinela:999'
bmundo() {
  novo_tmp; export BACKUP_DIR=$T/bk BACKUP_HOJE=2026-10-20 BACKUP_DIA_SEMANA=2 DATABASE_URL=$URL BACKUP_PASSPHRASE=$PASS PGD_RC=0 PGR_RC=0
  unset BACKUP_MIN_BYTES
  # pg_dump: registra argv e o servico; escreve um "dump" falso (comeca por PGDMP) no stdout
  cat > "$STUBS/pg_dump" <<'STUB'
#!/usr/bin/env bash
echo "pg_dump $* [PGSERVICE=$PGSERVICE]" >> "$STUB_LOG"
cp "$PGSERVICEFILE" "$STUB_LOG.servico"
[[ $PGD_RC == 0 ]] || { echo "erro com host db.exemplo.invalid" >&2; exit "$PGD_RC"; }
printf 'PGDMP-falso'; head -c 30000 /dev/zero | tr '\0' 'x'
STUB
  cat > "$STUBS/pg_restore" <<'STUB'
#!/usr/bin/env bash
echo "pg_restore $*" >> "$STUB_LOG"
c=$(head -c 5); [[ $c == PGDMP && $PGR_RC == 0 ]] && exit 0; exit 1
STUB
  chmod +x "$STUBS/pg_dump" "$STUBS/pg_restore"
}
broda() { bash "$B" > "$T/saida" 2>&1; RC=$?; }
bsem() { # rotulo: URL e passphrase fora da saida e do argv dos stubs
  ! grep -qF -- "SENHA-sentinela-URL-888" "$T/saida" "$STUB_LOG"; afirma $? "$1: URL/senha fora da saida e do argv"
  ! grep -qF -- "sentinela:999" "$T/saida" "$STUB_LOG"; afirma $? "$1: passphrase fora da saida e do argv"
  ! grep -q "postgres://" "$STUB_LOG"; afirma $? "$1: nenhum argv com URL"
}
modo() { [[ $(stat -c %a "$1") == "$2" ]]; }

bmundo; broda; afirma_rc $RC 0 "backup: ok"
F=$BACKUP_DIR/2026-10-20.dump.enc
[[ -f $F ]] && r=0 || r=1; afirma $r "backup: arquivo AAAA-MM-DD.dump.enc"; modo "$F" 600; afirma $? "backup: arquivo 0600"; modo "$BACKUP_DIR" 700; afirma $? "backup: pasta 0700"
! grep -q PGDMP "$F"; afirma $? "backup: arquivo cifrado (sem o claro)"
[[ $(openssl enc -d -aes-256-cbc -pbkdf2 -iter 600000 -pass env:BACKUP_PASSPHRASE -in "$F" 2>/dev/null | head -c 5) == PGDMP ]] && r=0 || r=1; afirma $r "backup: decifra com a passphrase"
afirma_log "pg_restore -l" "backup: validacao com pg_restore -l"
grep -qF "sem copia fora da VPS (restic/R2 adiado)" "$T/saida"; afirma $? "backup: resumo declara a falta de copia externa"
grep -q 'bytes' "$T/saida" && grep -q 'mais antigo' "$T/saida"; afirma $? "backup: resumo traz tamanho e idade do mais antigo"
bsem "backup"
grep -q '^host=db.exemplo.invalid' "$STUB_LOG.servico" && grep -q '^user=usuario' "$STUB_LOG.servico" && grep -q '^dbname=postgres' "$STUB_LOG.servico" && grep -q '^sslmode=require' "$STUB_LOG.servico"; afirma $? "backup: URL chegou ao pg_dump pelo arquivo de servico"
[[ -z $(find "$BACKUP_DIR" -mindepth 1 -maxdepth 1 -name '.tmp.*') ]] && r=0 || r=1; afirma $r "backup: sem temporario (nem servico) apos a execucao"
[[ $(grep -c . "$T/saida") == 1 ]] && r=0 || r=1; afirma $r "backup: resumo em uma linha"

# retencao: 16 antigos + hoje => 14
bmundo; mkdir -p "$BACKUP_DIR"; for d in $(seq -w 1 16); do : > "$BACKUP_DIR/2026-10-$d.dump.enc"; done
broda; afirma_rc $RC 0 "retencao: roda"
[[ $(find "$BACKUP_DIR" -name '*.dump.enc' | wc -l) == 14 ]]; afirma $? "retencao: ficam 14 dumps"
[[ ! -e $BACKUP_DIR/2026-10-03.dump.enc && -e $BACKUP_DIR/2026-10-04.dump.enc && -e $BACKUP_DIR/2026-10-20.dump.enc ]]; afirma $? "retencao: apaga os mais antigos e guarda o de hoje"
grep -q 'mais antigo 2026-10-04 (16 dias)' "$T/saida"; afirma $? "retencao: idade do mais antigo no resumo"

# validacao falha: dump descartado, anteriores intactos
bmundo; mkdir -p "$BACKUP_DIR"; echo velho > "$BACKUP_DIR/2026-10-19.dump.enc"; export PGR_RC=1; broda
afirma_rc $RC 1 "validacao falha => rc 1"; [[ ! -e $BACKUP_DIR/2026-10-20.dump.enc && $(cat "$BACKUP_DIR/2026-10-19.dump.enc") == velho ]]; afirma $? "validacao falha: sem dump novo, anterior intacto"; bsem "validacao falha"
# pg_dump falha
bmundo; export PGD_RC=1; broda; afirma_rc $RC 1 "pg_dump falha => rc 1"; [[ ! -e $BACKUP_DIR/2026-10-20.dump.enc ]]; afirma $? "pg_dump falha: nada gravado"
! grep -q 'db.exemplo.invalid' "$T/saida"; afirma $? "pg_dump falha: stderr do pg_dump nao repetido"; bsem "pg_dump falha"
# segunda-feira: tamanho minimo
bmundo; export BACKUP_DIA_SEMANA=1 BACKUP_MIN_BYTES=999999; broda; afirma_rc $RC 1 "segunda: dump abaixo do minimo => rc 1"
[[ ! -e $BACKUP_DIR/2026-10-20.dump.enc ]]; afirma $? "segunda: dump pequeno descartado"
bmundo; export BACKUP_DIA_SEMANA=2 BACKUP_MIN_BYTES=999999; broda; afirma_rc $RC 0 "outro dia: tamanho minimo nao se aplica"
bmundo; export BACKUP_DIA_SEMANA=1 BACKUP_MIN_BYTES=1000; broda; afirma_rc $RC 0 "segunda: dump acima do minimo => rc 0"
# pre-requisitos
bmundo; unset DATABASE_URL; broda; afirma_rc $RC 2 "sem DATABASE_URL => rc 2"; bsem "sem URL"
bmundo; unset BACKUP_PASSPHRASE; broda; afirma_rc $RC 2 "sem BACKUP_PASSPHRASE => rc 2"
bmundo; export DATABASE_URL='mysql://u:SENHA-sentinela-URL-888@h/db'; broda; afirma_rc $RC 2 "URL que nao e postgres => rc 2"; bsem "URL invalida"
bmundo; export BACKUP_HOJE=ontem; broda; afirma_rc $RC 2 "data invalida => rc 2"
fim
