#!/usr/bin/env bash
# shellcheck source=tests/lib.sh
. "$(dirname "$0")/lib.sh"
S=$RAIZ_REPO/scripts/45-jobs.sh
echo "45-jobs (instalador dos jobs agendados)"

# Mundo falso: jobs em $T/jobs, unidades em $T/units; systemctl e systemd-analyze so registram.
mundo() {
  novo_tmp
  export JOBS_DIR=$T/jobs JOBS_UNIT_DIR=$T/units JOBS_BIN=/opt/stack-vps/bin/stack-job JOBS_ANALYZE=$STUBS/systemd-analyze
  export JOBS_SRV=$T/srv JOBS_USER_AGENTE JOBS_USER_DEV JOBS_GROUP
  JOBS_USER_AGENTE=$(id -un); JOBS_USER_DEV=$JOBS_USER_AGENTE; JOBS_GROUP=$(id -gn)
  mkdir -p "$JOBS_DIR/bin" "$JOBS_UNIT_DIR" "$JOBS_SRV/state" "$JOBS_SRV/secrets"
  stub systemctl
  # o analyze falso trata um valor que comeca com '-' como opcao (como o real): sem o '--' registra OPCAO
  printf '#!/usr/bin/env bash\necho "systemd-analyze $*" >> "$STUB_LOG"\n[[ $1 == calendar && $2 == -- ]] || { echo "OPCAO $*" >> "$STUB_LOG"; exit 0; }\n[[ $3 == banana* ]] && exit 1\nexit 0\n' > "$STUBS/systemd-analyze"
  chmod +x "$STUBS/systemd-analyze"
  printf '#!/usr/bin/env bash\necho exemplo\n' > "$JOBS_DIR/bin/exemplo.sh"; chmod +x "$JOBS_DIR/bin/exemplo.sh"
}
# job <nome> <habilitado> [agenda] [linhas extras]
job() {
  printf 'DESCRICAO=Job %s de teste\nAGENDA=%s\nCOMANDO=jobs/bin/exemplo.sh arg1\nTIMEOUT_MIN=15\nHABILITADO=%s\n%s\n' \
    "$1" "${3:-*-*-* 03:00:00}" "$2" "${4:-}" > "$JOBS_DIR/$1.job"
}
roda() { saida=$(bash "$S" "$@" 2>&1); rc=$?; }
unid() { echo "$JOBS_UNIT_DIR/stack-job-$1"; }
snap() { (cd "$JOBS_UNIT_DIR" && find . -type f | sort | xargs -r sha256sum); }

# --- so HABILITADO=sim gera unidades ---
mundo; job a sim; job b nao; job c sim "Mon *-*-* 04:00:00" 'SEGREDOS=chave-x'; roda
afirma_rc "$rc" 0 "instala: rc 0"
for u in a.service a.timer c.service c.timer; do if [[ -f $(unid $u) ]]; then ok "gera stack-job-$u"; else falha "gera stack-job-$u"; fi; done
if [[ ! -e $(unid b.service) && ! -e $(unid b.timer) ]]; then ok "HABILITADO=nao: nada gerado"; else falha "HABILITADO=nao: nada gerado"; fi
s=$(<"$(unid a.service)")
grep -qx 'User=agente' <<<"$s" && grep -qx 'ExecStart=/opt/stack-vps/bin/stack-job a' <<<"$s" && grep -qx 'WorkingDirectory=/' <<<"$s"; afirma "$?" "service: User, ExecStart e WorkingDirectory"
grep -qx 'Type=oneshot' <<<"$s" && grep -qx 'TimeoutStartSec=25min' <<<"$s"; afirma "$?" "service: oneshot e TimeoutStartSec"
t=$(<"$(unid c.timer)")
grep -qx 'OnCalendar=Mon \*-\*-\* 04:00:00' <<<"$t" && grep -qx 'Persistent=true' <<<"$t" && grep -qx 'RandomizedDelaySec=300' <<<"$t"; afirma "$?" "timer: OnCalendar, Persistent e RandomizedDelaySec"
! grep -rqiE 'chave-x|Environment|EnvironmentFile|secret' "$JOBS_UNIT_DIR"; afirma "$?" "unidades sem segredo nem Environment"
afirma_log "systemctl daemon-reload" "daemon-reload"
afirma_log "systemctl enable --now stack-job-a.timer" "enable --now do timer a"
afirma_log "systemctl enable --now stack-job-c.timer" "enable --now do timer c"
nega_log "stack-job-b" "nenhum systemctl para o job desligado"
afirma_log "systemd-analyze calendar -- *-*-* 03:00:00" "agenda validada pelo systemd-analyze (com --)"
nega_log "OPCAO" "analyze sempre chamado com --"
grep -qx 'PrivateTmp=yes' "$(unid a.service)" && grep -qx 'ProtectSystem=full' "$(unid a.service)" && grep -qx 'MemoryMax=2G' "$(unid a.service)"; afirma "$?" "service: PrivateTmp, ProtectSystem e MemoryMax"

# --- idempotencia ---
antes=$(snap); : > "$STUB_LOG"; roda
afirma_rc "$rc" 0 "idempotente: rc 0"
if [[ $(snap) == "$antes" ]]; then ok "idempotente: unidades identicas"; else falha "idempotente: unidades identicas"; fi
nega_log "daemon-reload" "idempotente: sem daemon-reload quando nada mudou"
afirma_log "enable --now stack-job-a.timer" "idempotente: enable --now de novo (inofensivo)"
# mudar a agenda reescreve so o timer e recarrega
sed -i 's/^AGENDA=.*/AGENDA=*-*-* 05:30:00/' "$JOBS_DIR/a.job"; : > "$STUB_LOG"; roda
grep -qx 'OnCalendar=\*-\*-\* 05:30:00' "$(unid a.timer)"; afirma "$?" "agenda nova: timer reescrito"
afirma_log "daemon-reload" "agenda nova: daemon-reload"
afirma_log "try-restart stack-job-a.timer" "agenda nova: timer reiniciado"

# --- remove obsoletos ---
rm "$JOBS_DIR/c.job"; : > "$STUB_LOG"; roda
if [[ ! -e $(unid c.service) && ! -e $(unid c.timer) && -f $(unid a.timer) ]]; then ok "job que sumiu: unidades removidas, as outras ficam"; else falha "job que sumiu: unidades removidas, as outras ficam"; fi
afirma_log "disable --now stack-job-c.timer" "job que sumiu: timer desabilitado"
job a nao; : > "$STUB_LOG"; roda
if [[ ! -e $(unid a.service) && ! -e $(unid a.timer) ]]; then ok "virou nao: unidades removidas"; else falha "virou nao: unidades removidas"; fi
afirma_log "disable --now stack-job-a.timer" "virou nao: timer desabilitado"
touch "$JOBS_UNIT_DIR/stack-ci-runners.service"; roda
if [[ -f $JOBS_UNIT_DIR/stack-ci-runners.service ]]; then ok "unidade que nao e de job fica intacta"; else falha "unidade que nao e de job fica intacta"; fi

# --- fail-closed: um .job invalido recusa tudo ---
mundo; job a sim; roda; antes=$(snap)
job ruim sim "*-*-* 03:00:00" 'FOO=bar'; job b sim; sed -i '/^HABILITADO/d' "$JOBS_DIR/b.job"; : > "$STUB_LOG"
rm "$JOBS_DIR/a.job"; job a nao; roda
afirma_rc "$rc" 1 "job invalido: rc 1"
if [[ $(snap) == "$antes" ]]; then ok "job invalido: nada instalado nem removido (a ficaria desligado)"; else falha "job invalido: nada instalado nem removido (a ficaria desligado)"; fi
nega_log "systemctl" "job invalido: nenhum systemctl"
grep -q 'ruim.job' <<<"$saida" && grep -q 'FOO' <<<"$saida"; afirma "$?" "job invalido: diz qual e por que"
mundo; job a sim; job ruim sim "*-*-* 03:00:00" 'COMANDO=/bin/true'; sed -i '/^COMANDO=jobs/d' "$JOBS_DIR/ruim.job"; roda
afirma_rc "$rc" 1 "comando fora de jobs/bin: rc 1"; if [[ ! -e $(unid a.timer) ]]; then ok "comando fora de jobs/bin: nada instalado"; else falha "comando fora de jobs/bin: nada instalado"; fi
mundo; job a sim; job ruim sim 'banana'; roda
afirma_rc "$rc" 1 "agenda recusada pelo systemd-analyze: rc 1"; if [[ ! -e $(unid a.timer) ]]; then ok "agenda invalida: nada instalado"; else falha "agenda invalida: nada instalado"; fi
mundo; job A sim; roda; afirma_rc "$rc" 1 "nome de job invalido: rc 1"
mundo; job a sim; printf 'DESCRICAO=x $(id)\nAGENDA=daily\nCOMANDO=jobs/bin/exemplo.sh\nTIMEOUT_MIN=1\n' > "$JOBS_DIR/sub.job"; roda
afirma_rc "$rc" 1 "linha com \$(: rc 1"; if [[ ! -e $(unid a.timer) ]]; then ok "linha com \$(: nada instalado"; else falha "linha com \$(: nada instalado"; fi

# --- agenda sem systemd-analyze: regex conservadora ---
agenda() { mundo; export JOBS_ANALYZE=analyze-que-nao-existe; job a sim "$1"; roda; }
for ag in "daily" "weekly" "*-*-* 03:00:00" "Mon *-*-* 04:00:00" "Mon,Fri 06:30" "*-*-01 02:00:00" "hourly"; do
  agenda "$ag"; afirma_rc "$rc" 0 "regex: aceita '$ag'"; done
for ag in "banana" "*-*-* 99x" "Mon" "in 5 min" "*/5 * * * *"; do
  agenda "$ag"; afirma_rc "$rc" 1 "regex: recusa '$ag'"; done

# --- --listar nao muda nada ---
mundo; job a sim; job b nao; job ruim sim "*-*-* 03:00:00" 'FOO=1'; roda; antes=$(snap); : > "$STUB_LOG"
roda --listar
afirma_rc "$rc" 0 "listar: rc 0 mesmo com .job invalido"
grep -qE '^a +habilitado' <<<"$saida" && grep -qE '^b +desligado' <<<"$saida" && grep -qE '^ruim +INVALIDO' <<<"$saida"; afirma "$?" "listar: estado de cada .job"
if [[ $(snap) == "$antes" ]]; then ok "listar: nao muda nada"; else falha "listar: nao muda nada"; fi
nega_log "systemctl" "listar: nenhum systemctl"
roda --banana; afirma_rc "$rc" 2 "opcao desconhecida: rc 2"

# --- AGENDA que parece opcao do systemd-analyze ---
for ag in "--help" "--version" "-x"; do
  mundo; job a sim; job opc sim "$ag"; roda
  afirma_rc "$rc" 1 "agenda '$ag': recusa"
  if [[ ! -e $(unid a.timer) ]]; then ok "agenda '$ag': nada instalado"; else falha "agenda '$ag': nada instalado"; fi
  nega_log "OPCAO" "agenda '$ag': o analyze nunca recebe o valor como opcao"
  grep -q "AGENDA nao pode comecar com '-'" <<<"$saida"; afirma "$?" "agenda '$ag': motivo claro"
done

# --- pastas do agente: link simbolico e dono errado (fail-closed, nada instalado, alvo do link intacto) ---
mundo; job a sim; mkdir -p "$T/alvo-do-root"; chmod 711 "$T/alvo-do-root"; ln -s "$T/alvo-do-root" "$JOBS_SRV/jobs"; roda
afirma_rc "$rc" 1 "link em srv/jobs: recusa"
grep -q 'link simbolico' <<<"$saida"; afirma "$?" "link em srv/jobs: mensagem"
if [[ ! -e $(unid a.timer) && $(stat -c %a "$T/alvo-do-root") == 711 && -z $(ls -A "$T/alvo-do-root") ]]; then ok "link em srv/jobs: nada instalado e alvo intacto"; else falha "link em srv/jobs: nada instalado e alvo intacto"; fi
mundo; job a sim; mkdir -p "$T/alvo-do-root" "$JOBS_SRV/jobs"; ln -s "$T/alvo-do-root" "$JOBS_SRV/jobs/work"; roda
afirma_rc "$rc" 1 "link em srv/jobs/work: recusa"
mundo; job a sim; mkdir -p "$T/alvo-do-root"; ln -s "$T/alvo-do-root" "$JOBS_SRV/state/jobs"; roda
afirma_rc "$rc" 1 "link em srv/state/jobs: recusa"
mundo; job a sim; mkdir -p "$T/alvo-do-root"; ln -s "$T/alvo-do-root" "$JOBS_SRV/backups"; roda
afirma_rc "$rc" 1 "link em srv/backups: recusa"
mundo; job a sim; mkdir -p "$T/alvo-do-root"; ln -s "$T/alvo-do-root" "$JOBS_SRV/secrets/jobs"; roda
afirma_rc "$rc" 1 "link em srv/secrets/jobs: recusa"
mundo; job a sim; mkdir -p "$T/alvo-do-root"; rmdir "$JOBS_SRV/state"; ln -s "$T/alvo-do-root" "$JOBS_SRV/state"; roda
afirma_rc "$rc" 1 "pai (srv/state) e link: recusa"
mundo; job a sim; mkdir -p "$JOBS_SRV/state/jobs"; JOBS_USER_AGENTE=outro-usuario roda
afirma_rc "$rc" 1 "dono errado em srv/state/jobs: recusa"
grep -q 'nao e do dono' <<<"$saida"; afirma "$?" "dono errado: mensagem"
if [[ ! -e $(unid a.timer) ]]; then ok "dono errado: nada instalado"; else falha "dono errado: nada instalado"; fi
mundo; job a sim; touch "$JOBS_SRV/backups"; roda
afirma_rc "$rc" 1 "arquivo no lugar da pasta: recusa"
# pasta existente do dono certo: nao e tocada (modo preservado); ausente e criada com o modo pedido
mundo; job a sim; mkdir -p "$JOBS_SRV/state/jobs"; chmod 755 "$JOBS_SRV/state/jobs"; roda
afirma_rc "$rc" 0 "pasta existente do dono certo: ok"
if [[ $(stat -c %a "$JOBS_SRV/state/jobs") == 755 ]]; then ok "pasta existente: modo intacto (sem chmod)"; else falha "pasta existente: modo intacto (sem chmod)"; fi
if [[ $(stat -c %a "$JOBS_SRV/jobs/work") == 750 && $(stat -c %a "$JOBS_SRV/secrets/jobs") == 2750 && $(stat -c %a "$JOBS_SRV/backups") == 750 ]]; then ok "pastas ausentes: criadas com o modo certo"; else falha "pastas ausentes: criadas com o modo certo"; fi

# --- temporarios nunca ficam na pasta das unidades (a gravacao morre no meio) ---
mundo; job a sim
printf '#!/usr/bin/env bash\nkill -TERM "$PPID"; sleep 1\n' > "$STUBS/mv"; chmod +x "$STUBS/mv"; roda
if [[ $rc != 0 ]]; then ok "morte no meio da gravacao: o instalador termina com erro"; else falha "morte no meio da gravacao: o instalador termina com erro"; fi
if [[ -z $(ls -A "$JOBS_UNIT_DIR") ]]; then ok "trap: nenhum temporario sobra na pasta das unidades"; else falha "trap: nenhum temporario sobra ($(ls -A "$JOBS_UNIT_DIR"))"; fi

fim
