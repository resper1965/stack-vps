#!/usr/bin/env bash
# shellcheck source=tests/lib.sh
. "$(dirname "$0")/lib.sh"
S=$RAIZ_REPO/scripts/39-ci-rede.sh
echo "39-ci-rede"

# Firewall falso e com estado: uma tabela de regras por cadeia em $T/fw (nome "<cmd>.<cadeia>").
# -C devolve 1 ate a regra ser inserida. Tudo e registrado no STUB_LOG. OUTPUT ja tem uma regra do ufw.
mundo() {
  novo_tmp
  export CI_REDE_LIB=$T/lib CI_REDE_UNIT=$T/unit
  mkdir -p "$T/fw" "$CI_REDE_LIB" "$CI_REDE_UNIT"; echo 4242 > "$T/uid"
  for c in iptables ip6tables; do echo "-j ufw-before-output" > "$T/fw/$c.OUTPUT"; done
  stub install
  cat > "$STUBS/systemctl" <<'EOS'
#!/usr/bin/env bash
T=$(dirname "$STUB_LOG"); echo "systemctl $*" >> "$STUB_LOG"
case "$*" in *"is-active --quiet stack-ci-runners.service"*) [[ -e $T/runners-ativo ]] ;; esac
EOS
  cat > "$STUBS/sudo" <<'EOS'
#!/usr/bin/env bash
T=$(dirname "$STUB_LOG"); echo "sudo $*" >> "$STUB_LOG"
[[ ! -e $T/docker-falha ]] || exit 1
cat "$T/containers" 2>/dev/null; exit 0
EOS
  chmod +x "$STUBS/systemctl" "$STUBS/sudo"
  cat > "$STUBS/iptables" <<'EOS'
#!/usr/bin/env bash
T=$(dirname "$STUB_LOG"); c=$(basename "$0")
[[ $1 == -w && $2 == 10 ]] || { echo "$c $*" >> "$T/sem-w"; exit 99; }
shift 2; echo "$c $*" >> "$STUB_LOG"
[[ $c == ip6tables && -e $T/sem-ip6 ]] && exit 127
op=$1; ch=${2:-}; f=$T/fw/$c.$ch; shift 2 2>/dev/null
case $op in
  -N) [[ ! -e $f ]] || exit 1; : > "$f" ;;
  -C) [[ -e $f ]] && grep -qxF -- "$*" "$f" ;;
  -A) [[ -e $f ]] || exit 1; echo "$*" >> "$f" ;;
  -I) [[ $1 == 1 && -e $f ]] || exit 1; shift; { echo "$*"; cat "$f"; } > "$f.n"; mv "$f.n" "$f" ;;
  -D) [[ -e $f && $1 =~ ^[0-9]+$ ]] || exit 1; sed -i "${1}d" "$f" ;;
  -S) [[ ! -e $T/falha-S ]] || exit 4; echo "-P $ch ACCEPT"; [[ -e $f ]] && sed "s/^/-A $ch /" "$f" ;;
  -F) [[ -e $f ]] || exit 1; : > "$f" ;;
  -X) [[ -e $f && ! -e $T/falha-X ]] || exit 1; rm "$f" ;;
esac
EOS
  cp "$STUBS/iptables" "$STUBS/ip6tables"
  cat > "$STUBS/id" <<'EOS'
#!/usr/bin/env bash
T=$(dirname "$STUB_LOG"); [[ -e $T/sem-ci ]] && exit 1; cat "$T/uid"
EOS
  chmod +x "$STUBS/iptables" "$STUBS/ip6tables" "$STUBS/id"
}
# toda chamada ao firewall usou -w 10 (o stub grava em sem-w as que nao usaram)
com_w() { if [[ ! -e $T/sem-w ]]; then ok "$1: todas as chamadas com -w 10"; else falha "$1: chamada sem -w ($(head -1 "$T/sem-w"))"; fi; }
fw() { for f in "$T"/fw/*; do echo "== $(basename "$f")"; cat "$f"; done; }
# estado final de uma saida do script: texto exato
igual() { if [[ $1 == "$2" ]]; then ok "$3"; else falha "$3 ($1)"; fi; }

mundo
env -u STACK_TESTE bash "$S" >/dev/null 2>&1; rc=$?
if [[ $EUID -ne 0 ]]; then
  afirma_rc $rc 1 "sem root: recusa"; nega_log "tables" "sem root: nenhuma regra"
else ok "rodando como root: caso nao-root pulado"; fi

mundo
bash "$S" >/dev/null 2>&1; afirma_rc $? 0 "aplica"
afirma_log "iptables -N STACK-CI" "v4: cria a cadeia"; afirma_log "ip6tables -N STACK-CI" "v6: cria a cadeia"
afirma_log "iptables -A STACK-CI -d 100.64.0.0/10 -m comment --comment stack-ci -j REJECT" "v4: rejeita a tailnet"
afirma_log "iptables -A STACK-CI -d 169.254.169.254/32 -m comment --comment stack-ci -j REJECT" "v4: rejeita o metadata"
afirma_log "ip6tables -A STACK-CI -d fd7a:115c:a1e0::/48 -m comment --comment stack-ci -j REJECT" "v6: rejeita a tailnet"
afirma_log "iptables -I OUTPUT 1 -m owner --uid-owner 4242 -m comment --comment stack-ci -j STACK-CI" "v4: salto na posicao 1 so para o uid do ci"
afirma_log "ip6tables -I OUTPUT 1 -m owner --uid-owner 4242 -m comment --comment stack-ci -j STACK-CI" "v6: salto na posicao 1 so para o uid do ci"
igual "$(sed -n 1,2p "$T/fw/iptables.OUTPUT" | tr '\n' '|')" "-m owner --uid-owner 4242 -m comment --comment stack-ci -j STACK-CI|-j ufw-before-output|" "OUTPUT: salto antes das cadeias do ufw"

# toda regra inserida/anexada tem --uid-owner, ou e dentro da cadeia STACK-CI (que so e alcancada pelo salto)
sem_dono=$(grep -E '^ip6?tables -[IA] ' "$STUB_LOG" | grep -v -e '--uid-owner' | grep -vE '^ip6?tables -[IA] STACK-CI ' || true)
if [[ -z $sem_dono ]]; then ok "nenhuma regra fora da cadeia sem --uid-owner"; else falha "regra sem --uid-owner: $sem_dono"; fi
igual "$(grep -cE '^ip6?tables -I OUTPUT' "$STUB_LOG")" 2 "so dois saltos inseridos"
nega_log "-F OUTPUT" "nao limpa o OUTPUT"
com_w "aplica"

antes=$(fw)
: > "$STUB_LOG"
bash "$S" >/dev/null 2>&1; afirma_rc $? 0 "segunda execucao"
nega_log " -I " "idempotente: nada inserido"; nega_log " -A " "idempotente: nada anexado"; nega_log " -D " "idempotente: nada apagado"
if [[ $(fw) == "$antes" ]]; then ok "lista de regras identica depois da segunda execucao"; else falha "lista de regras mudou"; fi

# salto fora da posicao 1, duplicado ou com uid antigo: fica um so, na posicao 1, com o uid atual
mundo
for c in iptables ip6tables; do
  printf '%s\n' "-j ufw-before-output" "-m owner --uid-owner 999 -m comment --comment stack-ci -j STACK-CI" \
    "-m owner --uid-owner 4242 -m comment --comment stack-ci -j STACK-CI" > "$T/fw/$c.OUTPUT"
done
bash "$S" >/dev/null 2>&1; afirma_rc $? 0 "salto fora do lugar: corrige"
if (( $(grep -n '^iptables -I OUTPUT' "$STUB_LOG" | head -1 | cut -d: -f1) < $(grep -n '^iptables -D OUTPUT' "$STUB_LOG" | head -1 | cut -d: -f1) )); then ok "insere o salto certo antes de apagar os outros"; else falha "ordem insere/apaga"; fi
com_w "salto fora do lugar"
for c in iptables ip6tables; do
  igual "$(grep -c -e '-j STACK-CI$' "$T/fw/$c.OUTPUT") $(sed -n 1p "$T/fw/$c.OUTPUT") $(grep -c -e '-j ufw-before-output' "$T/fw/$c.OUTPUT")" \
    "1 -m owner --uid-owner 4242 -m comment --comment stack-ci -j STACK-CI 1" "$c: um salto, na posicao 1, uid atual; ufw intacto"
done

# salto certo ja na posicao 1 mais uma copia no fim: so apaga, nao insere
mundo
printf '%s
' "-m owner --uid-owner 4242 -m comment --comment stack-ci -j STACK-CI" "-j ufw-before-output"   "-m owner --uid-owner 4242 -m comment --comment stack-ci -j STACK-CI" > "$T/fw/iptables.OUTPUT"
bash "$S" >/dev/null 2>&1; afirma_rc $? 0 "salto duplicado: corrige"
nega_log "iptables -I OUTPUT" "duplicado: nao insere de novo"; afirma_log "iptables -D OUTPUT 3" "duplicado: apaga so a copia"

# UID invalido ou de sistema: recusa sem nenhuma chamada (uid 0 cortaria o proprio root)
for v in 0 999 "" abc -5 007; do
  mundo; printf '%s
' "$v" > "$T/uid"
  out=$(bash "$S" 2>&1); rc=$?
  afirma_rc $rc 1 "uid '$v': recusa"; nega_log "tables" "uid '$v': nenhuma chamada ao firewall"
  if [[ $out == *"UID invalido"* ]]; then ok "uid '$v': mensagem clara"; else falha "uid '$v': mensagem ($out)"; fi
done
for v in 1000 4242; do
  mundo; echo $v > "$T/uid"
  bash "$S" >/dev/null 2>&1; afirma_rc $? 0 "uid $v: aceito"; afirma_log "--uid-owner $v " "uid $v: regra com o uid"
done

# listagem falha (lock/timeout, rc 4): aborta e nao insere nada
mundo; : > "$T/falha-S"
out=$(bash "$S" 2>&1); afirma_rc $? 1 "-S falha: aborta"
if [[ $out == *"lock do xtables"* ]]; then ok "-S falha: mensagem clara"; else falha "-S falha: mensagem ($out)"; fi
nega_log " -I " "-S falha: nada inserido"; nega_log " -A " "-S falha: nada anexado"; nega_log " -D " "-S falha: nada apagado"
out=$(bash "$S" --status 2>&1); afirma_rc $? 1 "-S falha: status nao diz ativa"
if [[ $out != *ativa* || $out == *inativa* ]]; then ok "-S falha: status nao afirma ativa"; else falha "status: $out"; fi
bash "$S" --remover >/dev/null 2>&1; afirma_rc $? 1 "-S falha: --remover aborta"; nega_log " -F " "-S falha: nada limpo"

# ip6tables indisponivel: v4 aplicado, v6 nao, falha fechado com aviso
mundo; : > "$T/sem-ip6"
out=$(bash "$S" 2>&1); afirma_rc $? 1 "sem ip6tables: falha"
if [[ $out == *"ip6tables indisponível; v4 aplicado, v6 NÃO"* ]]; then ok "sem ip6tables: aviso explicito"; else falha "aviso ip6tables ($out)"; fi
afirma_log "iptables -I OUTPUT 1" "sem ip6tables: v4 ficou aplicado"; nega_log "ip6tables -I" "sem ip6tables: nada no v6"

# sem a conta ci: nada e inserido
mundo; : > "$T/sem-ci"
out=$(bash "$S" 2>&1); afirma_rc $? 1 "ci inexistente: recusa"
if [[ $out == *"ci nao existe"* ]]; then ok "mensagem clara"; else falha "mensagem clara ($out)"; fi
nega_log "iptables" "ci inexistente: nenhuma chamada ao iptables"; nega_log "ip6tables" "ci inexistente: nenhuma chamada ao ip6tables"
echo abc > "$T/uid"; rm "$T/sem-ci"
bash "$S" >/dev/null 2>&1; afirma_rc $? 1 "uid nao numerico: recusa"; nega_log "tables" "uid invalido: nenhuma chamada"

# remover: so o salto e as cadeias STACK-CI
mundo
bash "$S" >/dev/null 2>&1; : > "$STUB_LOG"
bash "$S" --remover >/dev/null 2>&1; afirma_rc $? 0 "--remover"
afirma_log "iptables -F STACK-CI" "v4: esvazia a cadeia"; afirma_log "ip6tables -X STACK-CI" "v6: apaga a cadeia"
nega_log "-F OUTPUT" "nao limpa o OUTPUT"
if grep -E ' -[FX] ' "$STUB_LOG" | grep -vqE ' -[FX] STACK-CI$'; then falha "mexeu em cadeia que nao e nossa"; else ok "so mexe em STACK-CI"; fi
if [[ $(cat "$T/fw/iptables.OUTPUT") == "-j ufw-before-output" && ! -e $T/fw/iptables.STACK-CI && ! -e $T/fw/ip6tables.STACK-CI ]]; then ok "estado: OUTPUT so com o ufw, cadeias sumiram"; else falha "estado depois do --remover"; fi
com_w "remover"
mundo; bash "$S" >/dev/null 2>&1; : > "$T/falha-X"
out=$(bash "$S" --remover 2>&1); afirma_rc $? 1 "-X falha (cadeia referenciada): rc 1"
if [[ $out != *"removida"* || $out == *"incompleta"* ]] && [[ $out == *"ainda referenciada"* ]]; then ok "nao diz removida quando -X falhou"; else falha "mensagem do -X ($out)"; fi
mundo; bash "$S" >/dev/null 2>&1
bash "$S" --remover >/dev/null 2>&1
bash "$S" --remover >/dev/null 2>&1; afirma_rc $? 0 "--remover repetido: tolerante"
touch "$T/sem-ci"; bash "$S" --remover >/dev/null 2>&1; afirma_rc $? 0 "--remover funciona sem a conta ci"

# remover recusa com runners ativos ou containers stack-ci (fail-closed), sem tocar no firewall
for caso in runners-ativo containers docker-falha; do
  mundo; bash "$S" >/dev/null 2>&1; : > "$STUB_LOG"
  if [[ $caso == containers ]]; then echo abc123 > "$T/containers"; else : > "$T/$caso"; fi
  out=$(bash "$S" --remover 2>&1); rc=$?
  afirma_rc $rc 1 "--remover com $caso: recusa"
  if [[ $out == *"pare os runners antes: 40-ci-runners.sh --parar"* ]]; then ok "$caso: mensagem manda parar"; else falha "$caso: mensagem ($out)"; fi
  nega_log " -F " "$caso: firewall intocado"; nega_log " -D " "$caso: salto mantido"
done

# status
mundo
out=$(bash "$S" --status 2>&1); rc=$?
igual "$out" inativa "status antes: inativa"; afirma_rc $rc 1 "status antes: rc 1"
nega_log " -I " "status nao altera nada"; nega_log " -N " "status nao cria cadeia"
bash "$S" >/dev/null 2>&1
out=$(bash "$S" --status 2>&1); rc=$?
igual "$out" ativa "status depois: ativa"; afirma_rc $rc 0 "status depois: rc 0"
sed -i '/fd7a/d' "$T/fw/ip6tables.STACK-CI"
out=$(bash "$S" --status 2>&1); rc=$?
igual "$out" inativa "falta a regra v6: inativa"; afirma_rc $rc 1 "falta a regra v6: rc 1"
bash "$S" >/dev/null 2>&1; bash "$S" --remover >/dev/null 2>&1
igual "$(bash "$S" --status 2>&1)" inativa "status depois do --remover: inativa"
bash "$S" >/dev/null 2>&1; touch "$T/sem-ci"
out=$(bash "$S" --status 2>&1); rc=$?
igual "$out" inativa "status sem a conta: inativa"; afirma_rc $rc 1 "status sem a conta: rc 1"

# instalar: aplica e depois instala; habilita sem --now
mundo
bash "$S" --instalar >/dev/null 2>&1; afirma_rc $? 0 "--instalar"
afirma_log "install -m 755 $S $CI_REDE_LIB/39-ci-rede.sh" "copia o script (0755)"
afirma_log "install -m 644 $RAIZ_REPO/systemd/stack-ci-rede.service $CI_REDE_UNIT/" "copia a unidade (0644)"
afirma_log "systemctl daemon-reload" "daemon-reload"; afirma_log "systemctl enable stack-ci-rede.service" "enable"
com_w "instalar"
nega_log "--now" "sem --now (as regras acabaram de ser aplicadas)"; nega_log "systemctl start" "sem start"
if (( $(grep -n 'iptables -I OUTPUT' "$STUB_LOG" | head -1 | cut -d: -f1) < $(grep -n '^install ' "$STUB_LOG" | head -1 | cut -d: -f1) )); then ok "aplica antes de instalar"; else falha "ordem aplica/instala"; fi
mundo; touch "$T/sem-ci"
bash "$S" --instalar >/dev/null 2>&1; afirma_rc $? 1 "--instalar sem a conta: recusa"; nega_log "install" "sem conta: nada instalado"
mundo; bash "$S" --bobagem >/dev/null 2>&1; afirma_rc $? 2 "argumento desconhecido: uso"; nega_log "tables" "argumento desconhecido: nada tocado"

# unidade
U=$RAIZ_REPO/systemd/stack-ci-rede.service
for l in "Type=oneshot" "RemainAfterExit=yes" "After=network-online.target docker.service" "Wants=network-online.target" \
         "Restart=on-failure" "RestartSec=15" "ExecStart=/usr/local/lib/stack-vps/39-ci-rede.sh" "WantedBy=multi-user.target"; do
  if grep -qxF "$l" "$U"; then ok "unidade: $l"; else falha "unidade: $l"; fi
done

# producao: override de ambiente e ignorado (guard extraido do script, como no teste do 38)
guard=$(sed -n '/^# >>> normaliza/,/^# <<< normaliza/p' "$S")
if [[ -n $guard ]]; then ok "guard encontrado"; else falha "guard encontrado"; fi
r=$(env -u STACK_TESTE CI_REDE_LIB=/x CI_REDE_UNIT=/y bash -c "$guard"$'\necho "$CI_REDE_LIB $CI_REDE_UNIT"')
igual "$r" "/usr/local/lib/stack-vps /etc/systemd/system" "sem STACK_TESTE: overrides ignorados"
r=$(STACK_TESTE=1 CI_REDE_LIB=/x CI_REDE_UNIT=/y bash -c "$guard"$'\necho "$CI_REDE_LIB $CI_REDE_UNIT"')
igual "$r" "/x /y" "com STACK_TESTE=1: overrides valem"
fim
