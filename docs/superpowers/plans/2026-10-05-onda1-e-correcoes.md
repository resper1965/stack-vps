# Onda 1 do ambiente-alvo + correções da revisão — plano de execução

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Corrigir os achados Critical/Important da revisão da migração e entregar a Onda 1 do ambiente-alvo (usuário `agente` isolado, segredos em níveis, `cloudflared` no baseline, alertas), aplicada e provada na VPS atual antes da reinstalação.

**Architecture:** Mesmo padrão do repositório: scripts bash idempotentes em `scripts/`, testes com stubs em `tests/` rodados na VPS por `TESTAR`. O que é sistema (usuários, permissões, Docker rootless) é provado na VPS com checagens explícitas, não por stub.

**Tech Stack:** bash, git, gitleaks 8.18.4, restic, systemd, Docker rootless (docker-ce-rootless-extras 29.7.2), ntfy.sh, Resend API, Telegram Bot API.

**Specs:** `docs/superpowers/specs/2026-10-05-ambiente-alvo-design.md` (Onda 1) e `docs/superpowers/specs/2026-10-05-migracao-vps-design.md`; achados em `.superpowers/sdd/2026-10-05-migracao-vps/progress.md` (linha "Final review").

## Global Constraints

- Branch `feat/migracao-vps` (mesma da migração; o PR único entra antes da janela).
- Commit em português, conventional commits, com o trailer de coautoria do harness.
- Scripts que exigem root aceitam `STACK_TESTE=1` só nos testes.
- Segredos: `/srv/dev/secrets/admin.env` (600 dev:dev), `/srv/dev/secrets/agente.env` (640 dev:agente), `/srv/dev/secrets/projetos/<p>.env` (640 dev:agente); diretório `secrets` 750 dev:agente.
- `agente`: sem `sudo`, fora dos grupos `docker` e `dev`, no grupo `devs`; `/srv/dev/data` e `/srv/forense` 750 dev:dev.
- Bloqueio do envio do laptop: extensões `pst e01 dd zip 7z rar xlsx xls csv pdf docx doc pptx ppt msg eml pem key pfx p12`, arquivos `.env`/`.env.*` (exceto `.env.example`), chaves `id_rsa*`/`id_ed25519*`/`id_ecdsa*` (exceto `.pub`), arquivos acima de 50 MB.
- Alertas: só na mudança de estado (ok↔falha); canais ntfy, Resend, Telegram; canal sem configuração é pulado; falha de um não impede os outros.
- Ações em conta de terceiros (GitHub, Cloudflare, Resend, Telegram) só com confirmação do Ricardo no momento.

**Apoio** (Git Bash): `. "$TEMP/apoio.sh"` define `SSHV` (ssh para `stack`) e `TESTAR` (envia `scripts tests bin systemd compose docker` para `~/stack-vps-wip` e roda `bash tests/run.sh`).

---

### Task 1: Filtro do envio do laptop (C1, I1, I2, I3, I11)

**Files:** Modify `scripts/20-laptop-github.sh`; Modify `tests/test-20-laptop-github.sh`

**Interfaces:**
- Produces: `eh_bloqueado <nome>` (rc 0 se bloqueado, imprime motivo); `bloqueio_hist <dir> <rev-args...>` (blobs do histórico: nome e tamanho); `bloqueio_arvore <dir> <listagem -z>`; listagem de pasta sem git por `GIT_DIR` temporário (`git ls-files -co --exclude-standard -z`), sem tocar na pasta.

- [ ] **Step 1: Casos de teste novos** (acrescentar antes do `fim`):

```bash
# acento no nome (C1)
novo_tmp; prepara; remoto ac ac; antes=$(cabeca ac)
echo x > "$B/ac/Relatório Técnico.pdf"; git -C "$B/ac" add .; git -C "$B/ac" commit -qm r
linha "$B/ac" forense-io ac push; bash "$S" "$TSV" >/dev/null 2>&1
[[ $(cabeca ac) == "$antes" ]]; afirma $? "acento: remoto intocado"
res | grep -q 'Relatório Técnico.pdf'; afirma $? "acento: motivo com o nome real"

# arquivo commitado e apagado continua no historico (I1)
novo_tmp; prepara; mkdir -p "$B/hist"; git -C "$B/hist" init -q -b main
echo x > "$B/hist/laudo.pdf"; git -C "$B/hist" add .; git -C "$B/hist" commit -qm a
git -C "$B/hist" rm -q laudo.pdf; git -C "$B/hist" commit -qm b
linha "$B/hist" forense-io hist criar; bash "$S" "$TSV" >/dev/null 2>&1
res | grep -q $'^PENDENTE\tcriar\tforense-io/hist\textensao: laudo.pdf'; afirma $? "historico: pdf apagado bloqueia"
nega_log "gh repo create" "historico: gh nao chamado"

# node_modules sem .gitignore (I2)
novo_tmp; prepara; mkdir -p "$B/nm/node_modules/x"; echo 1 > "$B/nm/node_modules/x/i.js"; echo 1 > "$B/nm/a.js"
linha "$B/nm" resper1965 nm criar; bash "$S" "$TSV" >/dev/null 2>&1
res | grep -q 'node_modules sem .gitignore'; afirma $? "node_modules: PENDENTE"
[[ ! -d $B/nm/.git ]]; afirma $? "node_modules: pasta intocada"

# repo aninhado (I2)
novo_tmp; prepara; mkdir -p "$B/pai/filho"; git -C "$B/pai/filho" init -q; echo 1 > "$B/pai/a.js"
linha "$B/pai" resper1965 pai criar; bash "$S" "$TSV" >/dev/null 2>&1
res | grep -q 'repositorio aninhado'; afirma $? "aninhado: PENDENTE"

# git sem commit: gitleaks no modo pasta (I3)
novo_tmp; prepara; mkdir -p "$B/sc"; git -C "$B/sc" init -q -b main; echo 1 > "$B/sc/a.js"
linha "$B/sc" resper1965 sc criar; bash "$S" "$TSV" --simular >/dev/null 2>&1
afirma_log "--no-git" "git sem commit: gitleaks --no-git"

# docx e .env (I11)
novo_tmp; prepara; mkdir -p "$B/dx"; echo x > "$B/dx/proposta.docx"
linha "$B/dx" resper1965 dx criar; bash "$S" "$TSV" >/dev/null 2>&1
res | grep -q 'extensao: proposta.docx'; afirma $? "docx: bloqueado"
novo_tmp; prepara; mkdir -p "$B/ev"; echo S=1 > "$B/ev/.env"; echo x > "$B/ev/.env.example"
linha "$B/ev" resper1965 ev criar; bash "$S" "$TSV" >/dev/null 2>&1
res | grep -q 'segredo: .env$'; afirma $? ".env: bloqueado (e .env.example nao)"
```

- [ ] **Step 2: `TESTAR`** → Expected: os casos novos falham (acento passa; histórico, node_modules, aninhado, `--no-git`, docx e `.env` sem PENDENTE).

- [ ] **Step 3: Implementação** — substituir em `scripts/20-laptop-github.sh` as linhas de `EXT_BLOQ` até o fim de `bloqueio()` por:

```bash
EXT_BLOQ='\.(pst|e01|dd|zip|7z|rar|xlsx|xls|csv|pdf|docx|doc|pptx|ppt|msg|eml|pem|key|pfx|p12)$'
MAX=$((50 * 1024 * 1024))

# eh_bloqueado <caminho>: rc 0 e motivo no stdout se o arquivo nao pode subir
eh_bloqueado() {
  local f=$1 base=${1##*/} min=${1,,}
  if [[ $min =~ $EXT_BLOQ ]]; then echo "extensao: $f"; return 0; fi
  if [[ $base == .env || ( $base == .env.* && $base != .env.example ) ]]; then echo "segredo: $f"; return 0; fi
  if [[ $base =~ ^id_(rsa|ed25519|ecdsa)  && $base != *.pub ]]; then echo "segredo: $f"; return 0; fi
  return 1
}

# bloqueio_hist <dir> <rev-args...>: todo blob que o envio leva (historico inteiro do intervalo)
bloqueio_hist() {
  local d=$1 tipo tam nome; shift
  while read -r tipo tam nome; do
    [[ $tipo == blob ]] || continue
    if eh_bloqueado "$nome"; then return 0; fi
    if (( tam > MAX )); then echo "acima de 50MB: $nome"; return 0; fi
  done < <(git -C "$d" rev-list --objects "$@" | git -C "$d" cat-file --batch-check='%(objecttype) %(objectsize) %(rest)')
  return 0
}

# bloqueio_arvore <dir>: le caminhos separados por NUL (o que um "git add -A" levaria)
bloqueio_arvore() {
  local d=$1 f s
  while IFS= read -r -d '' f; do
    if [[ $f == */ ]]; then echo "repositorio aninhado: $f"; return 0; fi
    if [[ /$f == */node_modules/* || /$f == */.venv/* ]]; then echo "node_modules sem .gitignore: $f"; return 0; fi
    if eh_bloqueado "$f"; then return 0; fi
    s=$(stat -c %s "$d/$f" 2>/dev/null || echo 0)
    if (( s > MAX )); then echo "acima de 50MB: $f"; return 0; fi
  done
  return 0
}

# lista o que "git add -A" levaria, sem tocar na pasta (GIT_DIR temporario se nao for repo)
lista_add() {
  local d=$1 tmp
  if git -C "$d" rev-parse --git-dir >/dev/null 2>&1; then
    git -C "$d" ls-files -co --exclude-standard -z
  else
    tmp=$(mktemp -d); git init -q "$tmp"
    git --git-dir="$tmp/.git" --work-tree="$d" ls-files -co --exclude-standard -z
    rm -rf "$tmp"
  fi
}
```

No `faz_push`, trocar a linha do `motivo=` por:

```bash
    motivo=$(bloqueio_hist "$d" "${range[@]}")
```

Em `faz_criar`, trocar as duas linhas do `motivo=` e a do `gl`/`gitleaks` por:

```bash
  local tem_head=0
  (( eh_git )) && git -C "$d" rev-parse -q --verify HEAD >/dev/null && tem_head=1
  if (( tem_head )); then motivo=$(bloqueio_hist "$d" --all)
  else motivo=$(lista_add "$d" | bloqueio_arvore "$d"); fi
  if [[ -n $motivo ]]; then registra PENDENTE criar "$dono" "$repo" "$motivo"; return; fi
  local -a gl=(detect --source "$d" --no-banner --redact); (( tem_head )) || gl+=(--no-git)
  gitleaks "${gl[@]}" >/dev/null 2>&1 </dev/null || { registra PENDENTE criar "$dono" "$repo" "segredo apontado pelo gitleaks"; return; }
```

(Sem `--directory`, o git lista um repositório aninhado como `sub/` e as subpastas comuns arquivo por arquivo.)

- [ ] **Step 4: `TESTAR`** → Expected: `20-laptop-github` todo `ok`.
- [ ] **Step 5: Commit** `fix: envio do laptop barra nome com acento, historico, node_modules, repo aninhado e documentos`

### Task 2: Fluxo do envio do laptop (I4, I5, I6, I7)

**Files:** Modify `scripts/20-laptop-github.sh`, `tests/test-20-laptop-github.sh`

- [ ] **Step 1: Casos novos** — e trocar `stub gh` do `prepara` por um `gh` que cria o remoto de verdade:

```bash
gh_stub() { cat > "$STUBS/gh" <<'EOS'
#!/usr/bin/env bash
echo "gh $*" >> "$STUB_LOG"
src=; nome=$3
while (($#)); do [[ $1 == --source ]] && src=$2; shift; done
git init -q --bare "$STUB_REMOTOS/${nome#*/}.git" && git -C "$src" remote add origin "$STUB_REMOTOS/${nome#*/}.git"
EOS
  chmod +x "$STUBS/gh"; export STUB_REMOTOS=$T/gh; mkdir -p "$STUB_REMOTOS"; }
```

```bash
# so alteracao nao commitada (I4)
novo_tmp; prepara; remoto dt dt; echo x > "$B/dt/novo.txt"
linha "$B/dt" resper1965 dt push; bash "$S" "$TSV" >/dev/null 2>&1
res | grep -q $'^PENDENTE\tpush\tresper1965/dt\talteracoes nao commitadas'; afirma $? "sujo sem commit: PENDENTE"

# ultima linha sem quebra (I5)
novo_tmp; prepara; mkdir -p "$B/ul"; echo 1 > "$B/ul/a.js"
printf 'windows\t%s\tresper1965\tul\tapps\tcriar' "$B/ul" >> "$TSV"
bash "$S" "$TSV" --simular >/dev/null 2>&1
res | grep -q 'resper1965/ul'; afirma $? "ultima linha sem quebra: processada"

# argumento errado (I6)
novo_tmp; prepara; remoto ar ar; antes=$(cabeca ar); git -C "$B/ar" commit -q --allow-empty -m x
linha "$B/ar" resper1965 ar push; bash "$S" "$TSV" --simula >/dev/null 2>&1; afirma_rc $? 1 "--simula: recusa"
[[ $(cabeca ar) == "$antes" ]]; afirma $? "--simula: nada enviado"

# criar envia todas as branches e retoma se o remoto ja existe (I7)
novo_tmp; prepara; gh_stub; mkdir -p "$B/br"; git -C "$B/br" init -q -b main
echo 1 > "$B/br/a.js"; git -C "$B/br" add .; git -C "$B/br" commit -qm a; git -C "$B/br" branch outra
linha "$B/br" resper1965 br criar; bash "$S" "$TSV" >/dev/null 2>&1
git --git-dir="$T/gh/br.git" rev-parse -q --verify outra >/dev/null; afirma $? "criar: todas as branches sobem"
git -C "$B/br" commit -q --allow-empty -m b
bash "$S" "$TSV" >/dev/null 2>&1
[[ $(git --git-dir="$T/gh/br.git" rev-parse main) == $(git -C "$B/br" rev-parse main) ]]; afirma $? "criar de novo: retoma como push"
```

O caso antigo "criar: gh com --private" passa a usar `gh_stub` (ele também registra no log).

- [ ] **Step 2: `TESTAR`** → Expected: os quatro grupos novos falham.

- [ ] **Step 3: Implementação**

Argumentos (substitui a linha do `SIMULAR=`):

```bash
SIMULAR=0
case ${2:-} in --simular) SIMULAR=1 ;; "") ;; *) echo "uso: $0 <tsv> [--simular]"; exit 1 ;; esac
(( $# <= 2 )) || { echo "uso: $0 <tsv> [--simular]"; exit 1; }
export GIT_TERMINAL_PROMPT=0
```

No `faz_push`: declarar `registrou=0`; em toda chamada de `registra` dentro do laço, setar `registrou=1` (trocar `registra` por `registra_b` com `registra_b() { registra "$@"; registrou=1; }` definida no topo da função); depois do laço:

```bash
  if (( ! registrou )) && { [[ -n $(git -C "$d" status --porcelain 2>/dev/null) ]] || [[ -n $(git -C "$d" stash list 2>/dev/null) ]]; }; then
    registra PENDENTE push "$dono" "$repo" "alteracoes nao commitadas (ou stash) ficaram no laptop"
  fi
```

Em `faz_criar`: se já existe `origin`, delegar ao push em vez de recusar:

```bash
  if (( eh_git )) && git -C "$d" remote get-url origin >/dev/null 2>&1; then
    faz_push "$d" "$dono" "$repo" "$arvore"; return; fi
```

e substituir do `(( eh_git )) || git -C "$d" init` até o fim da função por:

```bash
  (( eh_git )) || git -C "$d" init -q -b main
  if ! git -C "$d" rev-parse -q --verify HEAD >/dev/null; then
    if ! { git -C "$d" add -A && git -C "$d" commit -q -m "chore: importacao inicial do laptop"; }; then
      registra PENDENTE criar "$dono" "$repo" "commit inicial falhou (git user.email?)"; return; fi
  fi
  if ! gh repo create "$dono/$repo" --private --source "$d" --remote origin >/dev/null 2>&1 </dev/null; then
    registra PENDENTE criar "$dono" "$repo" "gh repo create falhou"; return; fi
  if git -C "$d" push -q -u origin --all </dev/null 2>/dev/null; then
    registra OK criar "$dono" "$repo" "repo privado criado$(sujo "$d")"; novo_escopo "$dono" "$repo" "$arvore"
  else registra PENDENTE criar "$dono" "$repo" "repo criado, push falhou: rode de novo"; fi
```

Leitura do TSV (I5):

```bash
while IFS=$'\t' read -r -u 3 origem caminho dono repo arvore acao || [[ -n ${origem:-} ]]; do
```

- [ ] **Step 4: `TESTAR`** → Expected: `20-laptop-github` todo `ok`.
- [ ] **Step 5: Commit** `fix: envio do laptop valida argumento, le ultima linha, acusa trabalho nao commitado e retoma criacao`

### Task 3: Segredos em níveis (`admin.env`, `agente.env`, `projetos/`)

**Files:** Modify `scripts/02-layout.sh`, `04-agents.sh`, `06-tunnel.sh`, `08-clonar-repos.sh`, `09-clonar-escopo.sh`, `12-push-state.sh`, `lib/restic-env.sh`, `15-restore.sh`, `.env.example`; tests que citam `.env`.

- [ ] **Step 1:** Em todos os scripts, `/srv/dev/secrets/.env` → `/srv/dev/secrets/admin.env`, exceto o `04`, que passa a ler `/srv/dev/secrets/agente.env` (roda como `agente`, Task 6). Teste: `grep -rn 'secrets/\.env' scripts bin` → Expected: nada.
- [ ] **Step 2:** `02-layout.sh` — trocar o bloco do `secrets` por:

```bash
getent group agente >/dev/null || groupadd agente   # o usuario nasce no 16; o grupo ja serve as permissoes
install -d -m 750 -o dev -g agente /srv/dev/secrets /srv/dev/secrets/projetos
[[ -f /srv/dev/secrets/admin.env ]]  || install -m 600 -o dev -g dev    /dev/null /srv/dev/secrets/admin.env
[[ -f /srv/dev/secrets/agente.env ]] || install -m 640 -o dev -g agente /dev/null /srv/dev/secrets/agente.env
chmod 750 /srv/dev/data
install -d -m 750 -o dev -g dev /srv/forense
```

- [ ] **Step 3:** `.env.example` vira `admin.env.example` (todas as chaves de hoje + `NTFY_TOPIC`, `RESEND_API_KEY`, `ALERTA_DE`, `TELEGRAM_BOT_TOKEN`, `TELEGRAM_CHAT_ID`) e nasce `agente.env.example` (`GITHUB_TOKEN`, `CLOUDFLARE_API_TOKEN` só leitura, `CLOUDFLARE_ACCOUNT_ID`, `COMPOSIO_API_KEY`, `SERPAPI_API_KEY`, `FEATHERLESS_API_KEY`).
- [ ] **Step 4:** `TESTAR` → Expected: rc 0 (os testes de 06/14/15 usam `STACK_ENV`; o 15 de teste continua com destino isolado).
- [ ] **Step 5: Commit** `feat: segredos separados em admin, agente e por projeto`

### Task 4: Backup cobre o essencial e o agente (I8, I9)

**Files:** Modify `scripts/lib/restic-env.sh`, `scripts/14-backup.sh`, `scripts/15-restore.sh`, `tests/test-14-backup.sh`, `tests/test-15-restore.sh`

**Interfaces:** `BACKUP_REQUIRED` e `BACKUP_OPTIONAL` (arrays, prefixados por `STACK_ROOT`); `BACKUP_PATHS` = os dois juntos.

- [ ] **Step 1: Testes** — no `prepara` do 14, criar também `etc/cloudflared/credentials.json` e `srv/dev/secrets/admin.env` (o `X=1` passa para `admin.env`); caso novo:

```bash
novo_tmp; prepara; restic_stub nenhum; rm "$STACK_ROOT/etc/cloudflared/credentials.json"
bash "$S" >/dev/null 2>&1; afirma_rc $? 1 "falta essencial: recusa"
nega_log "restic backup" "falta essencial: nao faz backup parcial"
[[ ! -e $STACK_ROOT/srv/dev/state/.last-backup ]]; afirma $? "falta essencial: sem .last-backup"
```

No 15: `afirma_log "--include /home/agente/.claude"` e `afirma_log "--include /srv/forense"`.

- [ ] **Step 2: `TESTAR`** → Expected: casos novos falham.
- [ ] **Step 3:** `lib/restic-env.sh`:

```bash
BACKUP_REQUIRED=("$R/srv/dev/state" "$R/srv/dev/secrets/admin.env" "$R/etc/cloudflared/credentials.json")
BACKUP_OPTIONAL=("$R/srv/dev/data" "$R/srv/forense" "$R/srv/dev/secrets/agente.env" "$R/srv/dev/secrets/projetos"
                 "$R/home/dev/.claude" "$R/home/dev/.codex" "$R/home/agente/.claude" "$R/home/agente/.codex")
BACKUP_PATHS=("${BACKUP_REQUIRED[@]}" "${BACKUP_OPTIONAL[@]}")
BACKUP_EXCLUDES=("$R/home/dev/.claude/.credentials.json" "$R/home/dev/.codex/auth.json"
                 "$R/home/agente/.claude/.credentials.json" "$R/home/agente/.codex/auth.json"
                 "$R/home/dev/.claude/plugins" "$R/home/agente/.claude/plugins" "node_modules")
```

`14-backup.sh`, antes do `paths=()`:

```bash
for p in "${BACKUP_REQUIRED[@]}"; do [[ -e $p ]] || { echo "falta caminho essencial: $p"; exit 1; }; done
```

`15-restore.sh`: cabeçalho passa a dizer `sudo --preserve-env=CLOUDFLARE_ACCOUNT_ID,R2_ACCESS_KEY_ID,R2_SECRET_ACCESS_KEY,RESTIC_PASSWORD ./15-restore.sh`; bloco de destino `/`:

```bash
if [[ $DEST == / ]]; then
  for d in /srv/dev/state /srv/dev/data /home/dev/.claude /home/dev/.codex; do
    if [[ -e $d ]]; then chown -R dev:dev "$d"; fi
  done
  for d in /home/agente/.claude /home/agente/.codex; do
    if [[ -e $d ]] && id agente >/dev/null 2>&1; then chown -R agente:agente "$d"; fi
  done
  if [[ -e /srv/forense ]]; then chown -R dev:dev /srv/forense; chmod 750 /srv/forense; fi
  if [[ -f /srv/dev/secrets/admin.env ]]; then chown dev:dev /srv/dev/secrets/admin.env; chmod 600 /srv/dev/secrets/admin.env; fi
  if [[ -f /srv/dev/secrets/agente.env ]]; then chown dev:agente /srv/dev/secrets/agente.env; chmod 640 /srv/dev/secrets/agente.env; fi
  if [[ -d /srv/dev/secrets/projetos ]]; then chown -R dev:agente /srv/dev/secrets/projetos; chmod -R u=rwX,g=rX,o= /srv/dev/secrets/projetos; fi
  if [[ -f /etc/cloudflared/credentials.json ]]; then
    chown root:root /etc/cloudflared/credentials.json; chmod 600 /etc/cloudflared/credentials.json
  fi
fi
```

- [ ] **Step 4: `TESTAR`** → Expected: rc 0.
- [ ] **Step 5: Commit** `fix: backup recusa rodar sem o essencial e cobre agente e forense; restore documenta sudo`

### Task 5: `cloudflared` no baseline (I10)

**Files:** Modify `scripts/03-tooling.sh`, `scripts/06-tunnel.sh`

- [ ] **Step 1:** `03-tooling.sh`, depois do `$APT install`:

```bash
# cloudflared: o tunnel de reserva depende dele e nenhuma imagem o traz
if ! command -v cloudflared >/dev/null; then
  install -d -m 755 /usr/share/keyrings
  curl -fsSL https://pkg.cloudflare.com/cloudflare-main.gpg -o /usr/share/keyrings/cloudflare-main.gpg
  echo 'deb [signed-by=/usr/share/keyrings/cloudflare-main.gpg] https://pkg.cloudflare.com/cloudflared any main' \
    > /etc/apt/sources.list.d/cloudflared.list
  $APT update -qq && $APT install -y -qq cloudflared >/dev/null
fi
```

e acrescentar `uidmap slirp4netns direnv` à lista do apt (usados nas Tasks 6 e 9 do ambiente).
- [ ] **Step 2:** `06-tunnel.sh`, logo após a checagem de root: `command -v cloudflared >/dev/null || { echo "cloudflared ausente: rode 03-tooling.sh"; exit 1; }`; trocar `cloudflared service install >/dev/null 2>&1 || true` por `[[ -f /etc/systemd/system/cloudflared.service ]] || cloudflared service install`. O teste do 06 já tem stub de `cloudflared` → `TESTAR` rc 0.
- [ ] **Step 3: Commit** `fix: baseline instala cloudflared e o 06 recusa rodar sem ele`

### Task 6: Usuário `agente` (`16-agente.sh`) e comandos `ia`/`iax`

**Files:** Create `scripts/16-agente.sh`, `bin/ia`; Modify `scripts/04-agents.sh`, `scripts/05-servicos.sh`

**Interfaces:** `sudo ./16-agente.sh` (idempotente); `/usr/local/bin/ia` e `/usr/local/bin/iax` (link para o mesmo arquivo); o `04` roda como `agente`.

- [ ] **Step 1: `bin/ia`**

```bash
#!/usr/bin/env bash
# ia: abre o Claude Code como "agente" no diretorio atual. iax: o mesmo com o Codex.
# O agente nao tem sudo, nao le data/ nem forense/ e so ve os segredos de agente.env.
set -euo pipefail
case ${0##*/} in ia) cmd=claude ;; iax) cmd=codex ;; *) echo "chame como ia ou iax"; exit 1 ;; esac
exec sudo -u agente -H bash -c '
  cd "$1" 2>/dev/null || cd /srv/dev/repos; shift
  export PATH="$HOME/.local/bin:$HOME/.local/share/mise/shims:$PATH"
  export DOCKER_HOST="unix:///run/user/$(id -u)/docker.sock"
  if [[ -f "$PWD/.envrc" ]]; then eval "$(direnv export bash 2>/dev/null)"; fi
  set -a; . /srv/dev/secrets/agente.env; set +a
  umask 002
  exec "$0" "$@"' "$cmd" "$PWD" "$@"
```

- [ ] **Step 2: `scripts/16-agente.sh`**

```bash
#!/usr/bin/env bash
# Usuario "agente" para Claude/Codex: sem sudo, sem docker do sistema, Docker rootless proprio,
# grupo "devs" com dev para repos/ e state/. data/ e forense/ ficam so com dev. Idempotente.
set -euo pipefail
[[ $EUID -eq 0 ]] || { echo "rode como root"; exit 1; }
REPO=$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)

getent group devs >/dev/null || groupadd devs
id agente &>/dev/null || adduser --disabled-password --gecos "" --ingroup agente agente 2>/dev/null \
  || adduser --disabled-password --gecos "" agente
usermod -aG devs dev; usermod -aG devs agente
gpasswd -d agente sudo 2>/dev/null || true; gpasswd -d agente docker 2>/dev/null || true
grep -q '^agente:' /etc/subuid || usermod --add-subuids 200000-265535 --add-subgids 200000-265535 agente

# repos e state compartilhados; data e forense so do dev
for d in /srv/dev/repos /srv/dev/state; do
  chgrp -R devs "$d"; chmod -R g+rwX "$d"; find "$d" -type d -exec chmod g+s {} +
done
chmod 750 /srv/dev/data; install -d -m 750 -o dev -g dev /srv/forense
git config --system core.sharedRepository group
git config --system --get-all safe.directory | grep -qx '\*' || git config --system --add safe.directory '*'
for u in dev agente; do grep -q 'umask 002' "/home/$u/.profile" || echo 'umask 002' >> "/home/$u/.profile"; done

# dev chama o agente sem senha; o agente nao tem sudo nenhum
echo 'dev ALL=(agente) NOPASSWD: ALL' > /etc/sudoers.d/91-dev-agente; chmod 440 /etc/sudoers.d/91-dev-agente; visudo -c -q
install -m 755 "$REPO/bin/ia" /usr/local/bin/ia; ln -sf /usr/local/bin/ia /usr/local/bin/iax

# Docker rootless: o AppArmor do Ubuntu 24.04 bloqueia namespace de usuario sem este perfil
cat > /etc/apparmor.d/usr.bin.rootlesskit <<'AA'
abi <abi/4.0>,
include <tunables/global>
"/usr/bin/rootlesskit" flags=(unconfined) {
  userns,
  include if exists <local/usr.bin.rootlesskit>
}
AA
systemctl reload apparmor
loginctl enable-linger agente
U=$(id -u agente)
for i in $(seq 1 20); do [[ -S /run/user/$U/bus ]] && break; sleep 0.5; done
sudo -u agente XDG_RUNTIME_DIR=/run/user/$U DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/$U/bus \
  bash -c 'systemctl --user is-active --quiet docker || dockerd-rootless-setuptool.sh install >/dev/null'

# Node do proprio agente (o do dev mora em /home/dev, 750)
sudo -u agente -H bash -c '
  command -v ~/.local/bin/mise >/dev/null || curl -fsSL https://mise.run | sh >/dev/null 2>&1
  grep -q "mise activate" ~/.bashrc || echo "eval \"\$(~/.local/bin/mise activate bash)\"" >> ~/.bashrc
  ~/.local/bin/mise use -g node@lts >/dev/null 2>&1'
echo "agente: $(id agente) | docker rootless: $(sudo -u agente XDG_RUNTIME_DIR=/run/user/$U systemctl --user is-active docker)"
```

- [ ] **Step 3: `04-agents.sh`** — `[[ $(id -un) == agente ]] || { echo "rode como agente: sudo -u agente -H ./04-agents.sh"; exit 1; }` e o `set -a; . /srv/dev/secrets/agente.env; set +a` no clone das skills.
- [ ] **Step 4: `TESTAR`** → Expected: shellcheck limpo, rc 0. (16 é provado na VPS, Task 9.)
- [ ] **Step 5: Commit** `feat: usuario agente sem sudo, com Docker rootless e comandos ia/iax`

### Task 7: `alertar.sh` (três canais)

**Files:** Create `scripts/alertar.sh`, `tests/test-alertar.sh`

**Interfaces:** `alertar.sh <titulo> <mensagem>`; lê `ALERTA_ENV` (padrão `/srv/dev/secrets/admin.env`); rc 0 se ao menos um canal entregou, 1 se nenhum.

- [ ] **Step 1: Teste**

```bash
#!/usr/bin/env bash
# shellcheck source=tests/lib.sh
. "$(dirname "$0")/lib.sh"
S=$RAIZ_REPO/scripts/alertar.sh
echo "alertar"
novo_tmp; export ALERTA_ENV=$T/env
printf 'NTFY_TOPIC=t1\nRESEND_API_KEY=r1\nALERTA_DE=a@x\nTELEGRAM_BOT_TOKEN=b1\nTELEGRAM_CHAT_ID=9\n' > "$ALERTA_ENV"
stub curl 0
bash "$S" "stack: falha" "disco cheio" >/dev/null 2>&1; afirma_rc $? 0 "tres canais: ok"
afirma_log "https://ntfy.sh/t1" "ntfy"
afirma_log "https://api.resend.com/emails" "resend"
afirma_log "https://api.telegram.org/botb1/sendMessage" "telegram"

novo_tmp; export ALERTA_ENV=$T/env; printf 'NTFY_TOPIC=t1\n' > "$ALERTA_ENV"; stub curl 0
bash "$S" t m >/dev/null 2>&1; afirma_rc $? 0 "so ntfy configurado: ok"
nega_log "resend" "sem chave: resend pulado"

novo_tmp; export ALERTA_ENV=$T/env
printf 'NTFY_TOPIC=t1\nTELEGRAM_BOT_TOKEN=b1\nTELEGRAM_CHAT_ID=9\n' > "$ALERTA_ENV"
cat > "$STUBS/curl" <<'EOS'
#!/usr/bin/env bash
echo "curl $*" >> "$STUB_LOG"; [[ "$*" == *ntfy.sh* ]] && exit 7; exit 0
EOS
chmod +x "$STUBS/curl"
bash "$S" t m >/dev/null 2>&1; afirma_rc $? 0 "ntfy falha: telegram ainda vai"
afirma_log "api.telegram.org" "telegram tentado depois da falha"

novo_tmp; export ALERTA_ENV=$T/env; : > "$ALERTA_ENV"; stub curl 0
bash "$S" t m >/dev/null 2>&1; afirma_rc $? 1 "nenhum canal: rc 1"
fim
```

- [ ] **Step 2: `TESTAR`** → Expected: falha (script inexistente).
- [ ] **Step 3: `scripts/alertar.sh`**

```bash
#!/usr/bin/env bash
# Envia um alerta a todos os canais configurados: ntfy, e-mail (Resend) e Telegram.
# Canal sem configuracao e pulado; falha de um nao impede os outros. rc 1 se nenhum entregou.
# Uso: alertar.sh <titulo> <mensagem>
set -uo pipefail
TITULO=${1:?uso: $0 <titulo> <mensagem>}; MSG=${2:-}
ENVF=${ALERTA_ENV:-/srv/dev/secrets/admin.env}
if [[ -s $ENVF ]]; then
  set -a
  # shellcheck source=/dev/null
  . "$ENVF"
  set +a
fi
entregues=0
json() { python3 -c 'import json,sys; print(json.dumps(sys.argv[1]))' "$1"; }

if [[ -n ${NTFY_TOPIC:-} ]]; then
  curl -fsS -m 15 -H "Title: $TITULO" -d "$MSG" "https://ntfy.sh/$NTFY_TOPIC" >/dev/null && entregues=$((entregues+1)) \
    || echo "alerta: ntfy falhou"
fi
if [[ -n ${RESEND_API_KEY:-} ]]; then
  curl -fsS -m 15 -X POST https://api.resend.com/emails -H "Authorization: Bearer $RESEND_API_KEY" \
    -H 'Content-Type: application/json' \
    -d "{\"from\":$(json "${ALERTA_DE:-stack <onboarding@resend.dev>}"),\"to\":[\"resper@bekaa.eu\"],\"subject\":$(json "$TITULO"),\"text\":$(json "$MSG")}" \
    >/dev/null && entregues=$((entregues+1)) || echo "alerta: e-mail falhou"
fi
if [[ -n ${TELEGRAM_BOT_TOKEN:-} && -n ${TELEGRAM_CHAT_ID:-} ]]; then
  curl -fsS -m 15 "https://api.telegram.org/bot$TELEGRAM_BOT_TOKEN/sendMessage" \
    --data-urlencode "chat_id=$TELEGRAM_CHAT_ID" --data-urlencode "text=$TITULO
$MSG" >/dev/null && entregues=$((entregues+1)) || echo "alerta: telegram falhou"
fi
(( entregues > 0 ))
```

- [ ] **Step 4: `TESTAR`** → Expected: `alertar` todo `ok`.
- [ ] **Step 5: Commit** `feat: alerta em ntfy, e-mail e Telegram`

### Task 8: Health ampliado e vigia por hora

**Files:** Modify `bin/health.sh`; Create `scripts/vigia-health.sh`, `systemd/stack-health.service`, `systemd/stack-health.timer`, `tests/test-vigia-health.sh`; Modify `scripts/05-servicos.sh`

**Interfaces:** `vigia-health.sh` lê `VIGIA_HEALTH` (padrão `/srv/dev/bin/health.sh`), `VIGIA_ALERTAR` (padrão `/usr/local/lib/stack-vps/alertar.sh`), `VIGIA_ESTADO` (padrão `/var/lib/stack-vps/health.estado`); alerta só na mudança.

- [ ] **Step 1: Teste**

```bash
#!/usr/bin/env bash
# shellcheck source=tests/lib.sh
. "$(dirname "$0")/lib.sh"
S=$RAIZ_REPO/scripts/vigia-health.sh
echo "vigia-health"
prepara() { export VIGIA_ESTADO=$T/estado VIGIA_ALERTAR=$STUBS/alertar VIGIA_HEALTH=$STUBS/health; stub alertar; }
novo_tmp; prepara; stub health 1 "FALHA disco"
bash "$S" >/dev/null 2>&1; afirma_log "alertar stack: FALHA" "primeira falha: alerta"
: > "$STUB_LOG"; bash "$S" >/dev/null 2>&1; nega_log "alertar" "falha repetida: silencio"
stub health 0 "ok"; bash "$S" >/dev/null 2>&1; afirma_log "alertar stack: recuperado" "volta ao ok: alerta"
: > "$STUB_LOG"; bash "$S" >/dev/null 2>&1; nega_log "alertar" "ok repetido: silencio"
novo_tmp; prepara; stub health 0 "ok"
bash "$S" >/dev/null 2>&1; nega_log "alertar" "primeiro ok: silencio"
fim
```

- [ ] **Step 2: `TESTAR`** → Expected: falha.
- [ ] **Step 3: `scripts/vigia-health.sh`**

```bash
#!/usr/bin/env bash
# Roda o health.sh e alerta so quando o estado muda (ok -> falha ou falha -> ok).
set -uo pipefail
HEALTH=${VIGIA_HEALTH:-/srv/dev/bin/health.sh}
ALERTAR=${VIGIA_ALERTAR:-/usr/local/lib/stack-vps/alertar.sh}
ESTADO=${VIGIA_ESTADO:-/var/lib/stack-vps/health.estado}
mkdir -p "$(dirname "$ESTADO")"
saida=$("$HEALTH" 2>&1); rc=$?
agora=ok; (( rc == 0 )) || agora=falha
antes=$(cat "$ESTADO" 2>/dev/null || echo ok)
echo "$agora" > "$ESTADO"
if [[ $agora != "$antes" ]]; then
  if [[ $agora == falha ]]; then "$ALERTAR" "stack: FALHA" "$(grep FALHA <<< "$saida")"
  else "$ALERTAR" "stack: recuperado" "health.sh voltou a passar"; fi
fi
echo "$saida"
```

Unidades:

```ini
# systemd/stack-health.service
[Unit]
Description=Health da VPS com alerta na mudanca de estado
[Service]
Type=oneshot
ExecStart=/usr/local/lib/stack-vps/vigia-health.sh
```

```ini
# systemd/stack-health.timer
[Unit]
Description=Health da VPS de hora em hora
[Timer]
OnCalendar=hourly
Persistent=true
[Install]
WantedBy=timers.target
```

- [ ] **Step 4: `bin/health.sh`** — antes do bloco `disco`:

```bash
echo "sistema"
mem=$(awk '/MemAvailable/{a=$2}/MemTotal/{t=$2}END{print int(a*100/t)}' /proc/meminfo)
(( mem >= 10 )) && ok "memoria livre ${mem}%" || bad "memoria livre ${mem}%"
if [[ -f /var/run/reboot-required ]]; then bad "reboot pendente ($(cat /var/run/reboot-required.pkgs 2>/dev/null | head -3 | tr '\n' ' '))"
else ok "sem reboot pendente"; fi
wl=/srv/dev/state/weekly.log
if [[ -f $wl ]] && (( ($(date +%s) - $(stat -c %Y "$wl")) / 86400 <= 8 )); then ok "rotina semanal em dia"
else bad "rotina semanal sem rodar ha mais de 8 dias"; fi
```

- [ ] **Step 5: `05-servicos.sh`** — instalar `alertar.sh` e `vigia-health.sh` em `/usr/local/lib/stack-vps/`, as duas unidades em `/etc/systemd/system/`, e `systemctl enable --now stack-health.timer`.
- [ ] **Step 6: `TESTAR`** → Expected: rc 0. **Commit** `feat: health ampliado e vigia de hora em hora com alerta na mudanca`

### Task 9: Aplicar a Onda 1 na VPS atual e provar

Operacional. Gates do Ricardo marcados (R).

- [ ] **Step 1:** Backup de segurança do `.env`: `SSHV 'cp /srv/dev/secrets/.env /srv/dev/secrets/.env.bak-$(date +%F)'`.
- [ ] **Step 2:** Separar segredos: `admin.env` = `.env` inteiro, sem duplicata de `CLOUDFLARE_API_TOKEN` (fica a última) e com `FEATHERLESS_API_KEY` corrigido; `agente.env` = `GITHUB_TOKEN` (provisório até o Step 7), `CLOUDFLARE_ACCOUNT_ID`, `COMPOSIO_API_KEY`, `SERPAPI_API_KEY`, `FEATHERLESS_API_KEY`. Nenhum valor é impresso. Os scripts de `/srv/dev/bin` são reinstalados pelo `05` (Step 4) já lendo `admin.env`. Remover `.env` só depois do Step 8.
- [ ] **Step 3:** `sudo bash ~/stack-vps-wip/scripts/03-tooling.sh` (cloudflared já existe; entram uidmap, slirp4netns, direnv).
- [ ] **Step 4:** `sudo bash ~/stack-vps-wip/scripts/02-layout.sh && sudo bash ~/stack-vps-wip/scripts/16-agente.sh && sudo bash ~/stack-vps-wip/scripts/05-servicos.sh`. Expected: `docker rootless: active`; timers `stack-backup` e `stack-health` listados.
- [ ] **Step 5:** `sudo -u agente -H bash ~/stack-vps-wip/scripts/04-agents.sh` — o diretório wip precisa ser legível pelo agente: rodar a partir de `/srv/dev/repos/infra/stack-vps` atualizado com a branch (`git fetch` + `checkout feat/migracao-vps` exige push; alternativa: copiar o wip para `/tmp/stack-vps-wip` com `chmod -R a+rX`). Expected: versões do claude e do codex.
- [ ] **Step 6: Provas como `agente`:**

```bash
SSHV 'sudo -u agente -H bash -lc "
  sudo -n true 2>/dev/null && echo FALHA-sudo || echo ok-sem-sudo
  ls /srv/dev/data >/dev/null 2>&1 && echo FALHA-data || echo ok-sem-data
  cat /srv/dev/secrets/admin.env >/dev/null 2>&1 && echo FALHA-admin || echo ok-sem-admin
  test -r /srv/dev/secrets/agente.env && echo ok-le-agente-env
  touch /srv/dev/repos/apps/.teste-agente && rm /srv/dev/repos/apps/.teste-agente && echo ok-escreve-repos
  DOCKER_HOST=unix:///run/user/\$(id -u)/docker.sock docker run --rm hello-world >/dev/null && echo ok-docker-rootless
  docker -H unix:///var/run/docker.sock ps >/dev/null 2>&1 && echo FALHA-docker-sistema || echo ok-sem-docker-sistema"'
```

Expected: só linhas `ok-*`.

- [ ] **Step 7 (R): Tokens mínimos.** Ricardo cria os tokens fine-grained do GitHub (um por dono) e o token Cloudflare de leitura (passo a passo no chat); entram no `agente.env` por `read -rs` no terminal dele. Proteção de branch: listar os repositórios ativos do escopo e aplicar com `gh api` **somente após o Ricardo aprovar a lista**.
- [ ] **Step 8 (R): Alertas.** Gerar `NTFY_TOPIC` aleatório no `admin.env` (Ricardo assina no app ntfy); Ricardo informa `RESEND_API_KEY` e cria o bot do Telegram (`TELEGRAM_BOT_TOKEN`, `TELEGRAM_CHAT_ID`) por `read -rs`. Prova: `sudo systemctl stop cloudflared; sudo /usr/local/lib/stack-vps/vigia-health.sh` → alerta nos canais configurados; `start` → "recuperado"; rodar de novo → nada.
- [ ] **Step 9:** `ia --version` e `iax --version` como `dev` → versões; `/srv/dev/bin/health.sh`.

### Task 10: Documentação

**Files:** `docs/srv-dev-README.md`, `docs/CLAUDE.md`, `docs/AGENTS.md`, `README.md`

- [ ] **Step 1:** README: tabela de ordem ganha `16-agente.sh` (depois do 07) e o 04 passa a `sudo -u agente -H ./scripts/04-agents.sh`; `.env.example` → `admin.env.example` e `agente.env.example`.
- [ ] **Step 2:** `srv-dev-README.md`: árvore com `secrets/{admin.env,agente.env,projetos/}` e `/srv/forense`; roteiro de recuperação com `16` e `04` como agente, e `sudo --preserve-env=...` no `15`; seção "Agentes" (`ia`/`iax`, o que o agente pode e não pode); seção "Alertas".
- [ ] **Step 3:** `CLAUDE.md`/`AGENTS.md` §2: os agentes rodam como `agente`; segredo vem de `agente.env` e do `.envrc` do projeto; `data/` e `forense/` inacessíveis por permissão. `diff` dos dois → iguais.
- [ ] **Step 4: Commit** `docs: agente isolado, segredos em niveis e alertas`

## Fora deste plano

Minors da revisão (M1–M7) ficam registrados no ledger para decisão do Ricardo. Ondas 2 e 3 do ambiente-alvo. Fases 1–4 da migração seguem o plano `2026-10-05-migracao-vps.md`.
