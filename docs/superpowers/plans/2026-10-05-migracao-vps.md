# Migração e instalação definitiva da VPS — plano de execução

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Deixar a VPS `stack` fechada (acesso só por Tailscale, tunnel de reserva), recriável pelos scripts mais o backup no R2, e com todo o trabalho do laptop no GitHub e clonado nela.

**Architecture:** Scripts bash idempotentes numerados em `scripts/`, testados por um runner próprio (`tests/run.sh`) com comandos externos substituídos por stubs no `PATH`. O plano alterna tarefas de código (TDD) com tarefas operacionais na VPS e no laptop; cada fase tem um portão que depende do Ricardo.

**Tech Stack:** bash, shellcheck, Tailscale, cloudflared, UFW, restic + Cloudflare R2 (S3), systemd timer, git, gh, gitleaks 8.18.4.

**Spec:** `docs/superpowers/specs/2026-10-05-migracao-vps-design.md`

## Global Constraints

- Commit em português, conventional commits (`feat:`, `fix:`, `docs:`, `chore:`, `test:`); código e nomes de variável em inglês ou no padrão já usado nos scripts (os existentes usam português — manter o padrão do arquivo).
- Branch de trabalho: `feat/migracao-vps`, criada a partir de `docs/migracao-vps`. Nada vai para `main` antes do portão da Task 16.
- Todo script é idempotente e começa com `#!/usr/bin/env bash` + `set -euo pipefail` (exceto os de laço tolerante, que já usam `set -uo pipefail`).
- Scripts que exigem root aceitam `STACK_TESTE=1` como dispensa da checagem, **só** para os testes.
- Nenhum segredo em arquivo versionado, em argumento de commit ou na saída dos scripts. Chaves que o Ricardo informa entram por `read -rs` no terminal dele.
- Ações destrutivas ou que alteram conta de terceiros (hPanel, painel do Tailscale, conta Cloudflare, criação de repo no GitHub) só com confirmação explícita do Ricardo no momento.
- `/srv/dev/data/**` não é lido nem listado; só entra no backup como caminho.
- UFW final: entrada negada; 22/tcp só em `tailscale0`; loopback liberado pelas regras-base do UFW.
- Restic: repositório `s3:https://<CLOUDFLARE_ACCOUNT_ID>.r2.cloudflarestorage.com/stack-vps-backup`; retenção `--keep-daily 7 --keep-weekly 4 --keep-monthly 6`; timer diário 06:00 UTC.
- Bloqueio de envio do laptop: arquivos acima de 50 MB e extensões `.pst .e01 .dd .zip .xlsx .csv .pdf`.

**Comandos de apoio** (rodar no Git Bash do Windows, na raiz do repositório):

```bash
# acesso à VPS — até a Task 5 pelo IP; da Task 5 em diante por "stack"
VPS_HOST=dev@148.230.77.242          # depois da Task 5: VPS_HOST=dev@stack
SSHV() { /c/Windows/System32/OpenSSH/ssh.exe -o BatchMode=yes -o ConnectTimeout=10 -i ~/.ssh/id_ed25519_stackvps "$VPS_HOST" "$@"; }
# envia a árvore de trabalho para ~/stack-vps-wip na VPS e roda os testes lá
TESTAR() { tar -cf - scripts tests bin systemd compose | SSHV 'rm -rf ~/stack-vps-wip && mkdir ~/stack-vps-wip && tar -xf - -C ~/stack-vps-wip && cd ~/stack-vps-wip && bash tests/run.sh'; }
# o mesmo repositório visto de dentro do WSL, e o scratchpad da sessão (arquivos temporários)
REPO_WSL='/mnt/c/Users/resper/OneDrive/Área de Trabalho/DESENVOLVIMENTO/STACK-VPS'
SCRATCH="$TEMP/stack-vps-migracao"; mkdir -p "$SCRATCH"
```

## Review Focus

1. **VPS recém-formatada, onde o `02` já criou `.env` vazio e `state/reviews/` vazio** → o `15-restore.sh` precisa considerar o destino livre e restaurar; só arquivo não vazio conta como ocupado. Teste na Task 9.
2. **`07-firewall.sh` rodado com o Tailscale caído ou sem IP** → não pode tocar no UFW. Teste na Task 3.
3. **Caminho com espaço e acento** (`/mnt/c/Users/resper/OneDrive/Área de Trabalho/...`) no TSV do laptop → o `20` processa sem quebrar. Teste na Task 11.
4. **TSV salvo no Windows com CRLF** → a última coluna (`acao`) não pode carregar `\r`. Teste na Task 11.
5. **Falha do restic no meio do backup** → `.last-backup` não é gravado, para o `health.sh` acusar. Teste na Task 8.

---

## Fase 0a — acesso (código)

### Task 1: Runner de testes e shellcheck

**Files:**
- Create: `tests/lib.sh`, `tests/run.sh`
- Modify: `scripts/03-tooling.sh:12` (acrescenta `shellcheck` à lista do apt)
- Modify: qualquer script que o shellcheck reprovar em nível `warning`

**Interfaces:**
- Produces: `tests/lib.sh` com `novo_tmp`, `stub <nome> [rc] [saida]`, `afirma_rc <rc> <esperado> <desc>`, `afirma_log <trecho> <desc>`, `nega_log <trecho> <desc>`, `afirma <condicao-rc> <desc>`, `fim`; variáveis `T`, `STUBS`, `STUB_LOG`, `RAIZ_REPO`. Todo `tests/test-*.sh` começa com `#!/usr/bin/env bash`, `# shellcheck source=tests/lib.sh` e `. "$(dirname "$0")/lib.sh"`, e termina com `fim`.

- [ ] **Step 1: Criar a branch**

```bash
git switch -c feat/migracao-vps
```

- [ ] **Step 2: Escrever `tests/lib.sh`**

```bash
# Utilitarios dos testes: raiz temporaria, stubs no PATH e asserts. Fonte: . tests/lib.sh
# shellcheck shell=bash disable=SC2034  # variaveis usadas pelos testes que fazem source
set -uo pipefail
RAIZ_REPO=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
PATH_ORIGINAL=$PATH
falhas=0

# Cada caso comeca do zero: PATH limpo de stubs anteriores e log vazio.
novo_tmp() {
  T=$(mktemp -d); STUBS=$T/stubs; mkdir -p "$STUBS"
  export STUB_LOG=$T/stub.log; : > "$STUB_LOG"
  export PATH="$STUBS:$PATH_ORIGINAL" STACK_TESTE=1 STACK_ENV=$T/sem-env
}

# stub <nome> [codigo-de-saida] [saida]: registra "nome args" no STUB_LOG
stub() {
  local n=$1 rc=${2:-0} out=${3:-}
  { echo '#!/usr/bin/env bash'
    echo "echo \"$n \$*\" >> \"\$STUB_LOG\""
    [[ -n $out ]] && printf 'echo %q\n' "$out"
    echo "exit $rc"; } > "$STUBS/$n"
  chmod +x "$STUBS/$n"
}

ok()    { printf '  ok    %s\n' "$1"; }
falha() { printf '  FALHA %s\n' "$1"; falhas=$((falhas+1)); }
afirma_rc()  { if [[ $1 == "$2" ]]; then ok "$3"; else falha "$3 (rc esperado $2, veio $1)"; fi; }
afirma_log() { if grep -qF -- "$1" "$STUB_LOG"; then ok "$2"; else falha "$2 (sem '$1' no log)"; fi; }
nega_log()   { if grep -qF -- "$1" "$STUB_LOG"; then falha "$2 (achei '$1' no log)"; else ok "$2"; fi; }
afirma()     { if [[ $1 == 0 ]]; then ok "$2"; else falha "$2"; fi; }
fim() { exit $(( falhas > 0 )); }
```

- [ ] **Step 3: Escrever `tests/run.sh`**

```bash
#!/usr/bin/env bash
# Roda o shellcheck e todos os tests/test-*.sh. Sai com 1 se algo falhar.
cd "$(dirname "$0")/.." || exit 1
shopt -s nullglob   # scripts/lib/ so passa a existir na Task 8
rc=0
echo "shellcheck"
if shellcheck -x -S warning scripts/*.sh scripts/lib/*.sh bin/*.sh tests/*.sh 2>/dev/null; then echo "  ok"; else
  shellcheck -x -S warning scripts/*.sh scripts/lib/*.sh bin/*.sh tests/*.sh; rc=1; fi
for t in tests/test-*.sh; do [[ -e $t ]] || continue; echo "$t"; bash "$t" || rc=1; done
exit $rc
```

- [ ] **Step 4: Acrescentar `shellcheck` ao `03-tooling.sh` e instalar na VPS**

Em `scripts/03-tooling.sh`, na linha do `$APT install`, acrescentar `shellcheck` à lista:

```bash
$APT install -y -qq git tmux ripgrep fd-find jq htop ncdu restic rclone curl unzip shellcheck >/dev/null
```

E na VPS atual:

```bash
SSHV 'sudo apt-get -o DPkg::Lock::Timeout=600 install -y -qq shellcheck >/dev/null && shellcheck --version | head -2'
```

Esperado: `ShellCheck - shell script analysis tool` e a versão.

- [ ] **Step 5: Rodar o runner e corrigir os avisos dos scripts existentes**

```bash
TESTAR
```

Esperado na primeira vez: avisos do shellcheck nos scripts que nunca passaram por ele. Corrigir cada `warning` com a mudança mínima (aspas, `read -r`, `local` separado de atribuição). Se for falso positivo, desligar só aquela linha com comentário do motivo, por exemplo:

```bash
# shellcheck disable=SC2034  # usada pelo script que faz source deste
```

Repetir `TESTAR` até sair `shellcheck` → `ok` e código 0.

- [ ] **Step 6: Commit**

```bash
git add tests/ scripts/
git commit -m "test: runner com shellcheck e stubs para os scripts da VPS"
```

---

### Task 2: Tailscale no baseline (`01b-tailscale.sh`)

O spec diz que o `01` instala o Tailscale. Ele faz isso chamando o `01b`, que também roda sozinho na VPS atual (fase 0a) sem reaplicar o baseline inteiro.

**Files:**
- Create: `scripts/01b-tailscale.sh`, `tests/test-01b-tailscale.sh`
- Modify: `scripts/01-baseline.sh` (chamada ao `01b` antes do eco final; `ignoreip` do fail2ban)

**Interfaces:**
- Consumes: `tests/lib.sh` (Task 1).
- Produces: `scripts/01b-tailscale.sh`, uso `sudo TS_AUTHKEY=tskey-auth-... ./01b-tailscale.sh`; sai 0 se já está na tailnet ou se entrou; sai 1 sem `TS_AUTHKEY` quando precisa entrar.

- [ ] **Step 1: Escrever o teste**

`tests/test-01b-tailscale.sh`:

```bash
#!/usr/bin/env bash
# shellcheck source=tests/lib.sh
. "$(dirname "$0")/lib.sh"
S=$RAIZ_REPO/scripts/01b-tailscale.sh
echo "01b-tailscale"

ts_stub() { # tailscale com status de saida configuravel
  cat > "$STUBS/tailscale" <<EOF
#!/usr/bin/env bash
echo "tailscale \$*" >> "\$STUB_LOG"
case \$1 in status) exit $1;; ip) echo 100.101.102.103;; esac
exit 0
EOF
  chmod +x "$STUBS/tailscale"; }

novo_tmp; ts_stub 1; stub systemctl; stub curl
env -u TS_AUTHKEY bash "$S" >/dev/null 2>&1; afirma_rc $? 1 "fora da tailnet e sem chave: recusa"
nega_log "tailscale up" "sem chave: nao chama up"

novo_tmp; ts_stub 1; stub systemctl; stub curl
TS_AUTHKEY=tskey-auth-teste bash "$S" >/dev/null 2>&1; afirma_rc $? 0 "com chave: entra"
afirma_log "tailscale up --authkey=tskey-auth-teste --hostname=stack" "entra como stack"

novo_tmp; ts_stub 0; stub systemctl; stub curl
env -u TS_AUTHKEY bash "$S" >/dev/null 2>&1; afirma_rc $? 0 "ja na tailnet: nada a fazer"
nega_log "tailscale up" "ja na tailnet: nao chama up"
nega_log "curl" "binario presente: nao reinstala"
fim
```

- [ ] **Step 2: Rodar e ver falhar**

```bash
TESTAR
```

Esperado: `tests/test-01b-tailscale.sh` com `FALHA` (script inexistente → rc 127).

- [ ] **Step 3: Escrever `scripts/01b-tailscale.sh`**

```bash
#!/usr/bin/env bash
# Tailscale: instala e entra na tailnet como "stack". Idempotente.
# Uso: sudo TS_AUTHKEY=tskey-auth-... ./01b-tailscale.sh
# A chave e de uso unico, gerada no painel do Tailscale na hora; nunca vai para arquivo.
set -euo pipefail
[[ $EUID -eq 0 || ${STACK_TESTE:-} == 1 ]] || { echo "rode como root"; exit 1; }

command -v tailscale >/dev/null || curl -fsSL https://tailscale.com/install.sh | sh
systemctl enable --now tailscaled

if tailscale status >/dev/null 2>&1; then
  echo "tailscale: ja na tailnet"
else
  [[ -n ${TS_AUTHKEY:-} ]] || { echo "informe TS_AUTHKEY (uso unico, gerada no painel do Tailscale)"; exit 1; }
  tailscale up --authkey="$TS_AUTHKEY" --hostname=stack
fi
echo "tailscale: $(tailscale ip -4 | head -1) — desative a expiracao de chave do no 'stack' no painel"
```

- [ ] **Step 4: Ligar o `01b` ao `01` e liberar a tailnet no fail2ban**

Em `scripts/01-baseline.sh`, trocar a linha do `ignoreip`:

```
ignoreip = 127.0.0.1/8 ::1 169.254.0.0/16 100.64.0.0/10
```

e, imediatamente antes da última linha (`echo "baseline ok. ..."`), inserir:

```bash
# Tailscale entra junto com o baseline: e o caminho principal de acesso.
"$(dirname "$(readlink -f "$0")")"/01b-tailscale.sh
```

Atualizar o comentário de uso no topo do `01`:

```bash
# Idempotente. Uso: sudo TS_AUTHKEY=tskey-auth-... ./01-baseline.sh "ssh-ed25519 AAAA... comentario"
```

- [ ] **Step 5: Rodar e ver passar**

```bash
TESTAR
```

Esperado: `01b-tailscale` com 7 `ok`; código 0.

- [ ] **Step 6: Commit**

```bash
git add scripts/01b-tailscale.sh scripts/01-baseline.sh tests/test-01b-tailscale.sh
git commit -m "feat: Tailscale no baseline, como caminho principal de acesso"
```

---

### Task 3: UFW fechado na tailnet (`07-firewall.sh`)

**Files:**
- Modify: `scripts/07-firewall.sh` (reescrita)
- Create: `tests/test-07-firewall.sh`

**Interfaces:**
- Consumes: `tests/lib.sh`.
- Produces: `sudo ./07-firewall.sh` sem argumentos; sai 1 sem alterar nada se `tailscale ip -4` não devolver `100.*`.

- [ ] **Step 1: Escrever o teste**

`tests/test-07-firewall.sh`:

```bash
#!/usr/bin/env bash
# shellcheck source=tests/lib.sh
. "$(dirname "$0")/lib.sh"
S=$RAIZ_REPO/scripts/07-firewall.sh
echo "07-firewall"

novo_tmp; stub tailscale 1; stub ufw
bash "$S" >/dev/null 2>&1; afirma_rc $? 1 "tailscale caido: recusa"
nega_log "ufw" "tailscale caido: UFW intocado"

novo_tmp; stub tailscale 0 ""; stub ufw
bash "$S" >/dev/null 2>&1; afirma_rc $? 1 "tailscale sem IP: recusa"
nega_log "ufw" "sem IP: UFW intocado"

novo_tmp; stub tailscale 0 "100.101.102.103"; stub ufw
bash "$S" >/dev/null 2>&1; afirma_rc $? 0 "tailscale ok: aplica"
afirma_log "ufw default deny incoming" "entrada negada por padrao"
afirma_log "ufw allow in on tailscale0 to any port 22 proto tcp" "22 so na tailscale0"
nega_log "ufw allow 22/tcp" "22 publica nao e liberada"
fim
```

- [ ] **Step 2: Rodar e ver falhar**

```bash
TESTAR
```

Esperado: `FALHA tailscale caido: recusa` (o `07` atual não confere o Tailscale e libera a 22).

- [ ] **Step 3: Reescrever `scripts/07-firewall.sh`**

```bash
#!/usr/bin/env bash
# UFW: entrada negada; a 22 so pela tailnet. O loopback, por onde chega o Cloudflare Tunnel,
# ja e liberado pelas regras-base do UFW. Uso: sudo ./07-firewall.sh
# Recusa rodar sem o Tailscale de pe: fechar a 22 publica sem a tailnet tranca a VPS.
# Saida de emergencia: console do hPanel -> ufw allow 22/tcp
set -euo pipefail
[[ $EUID -eq 0 || ${STACK_TESTE:-} == 1 ]] || { echo "rode como root"; exit 1; }

TSIP=$(tailscale ip -4 2>/dev/null | head -1 || true)
[[ $TSIP == 100.* ]] || { echo "tailscale sem IP 100.x: rode 01b-tailscale.sh antes; UFW nao foi alterado"; exit 1; }

ufw --force reset >/dev/null
ufw default deny incoming >/dev/null
ufw default allow outgoing >/dev/null
ufw allow in on tailscale0 to any port 22 proto tcp comment 'ssh pela tailnet' >/dev/null
ufw --force enable >/dev/null
ufw status verbose | head -12
```

- [ ] **Step 4: Rodar e ver passar**

```bash
TESTAR
```

Esperado: `07-firewall` com 8 `ok`.

- [ ] **Step 5: Commit**

```bash
git add scripts/07-firewall.sh tests/test-07-firewall.sh
git commit -m "feat: UFW libera a 22 so na tailnet e recusa rodar sem Tailscale"
```

---

### Task 4: Tunnel de reserva, health e config de SSH

**Files:**
- Modify: `scripts/06-tunnel.sh` (caminhos sobrescrevíveis; trava da credencial)
- Modify: `bin/health.sh` (seção `acesso` no lugar de `tunnel`)
- Modify: `docs/ssh-config-wsl.md` (reescrita)
- Create: `tests/test-06-tunnel.sh`

**Interfaces:**
- Consumes: `tests/lib.sh`.
- Produces: `06-tunnel.sh` lê `STACK_ENV` (padrão `/srv/dev/secrets/.env`) e `STACK_CF_DIR` (padrão `/etc/cloudflared`); sai 1 com "rode 15-restore.sh antes" se o tunnel existe e falta a credencial. Hosts SSH `stack` (tailnet) e `stack-cf` (tunnel).

- [ ] **Step 1: Escrever o teste**

`tests/test-06-tunnel.sh`:

```bash
#!/usr/bin/env bash
# shellcheck source=tests/lib.sh
. "$(dirname "$0")/lib.sh"
S=$RAIZ_REPO/scripts/06-tunnel.sh
echo "06-tunnel"

novo_tmp
printf 'CLOUDFLARE_API_TOKEN=x\nCLOUDFLARE_ACCOUNT_ID=acc\n' > "$T/env"
export STACK_ENV=$T/env STACK_CF_DIR=$T/cloudflared
stub curl 0 '{"success":true,"result":[{"id":"tid-123"}]}'
stub systemctl; stub cloudflared
bash "$S" dono@exemplo.com > "$T/out" 2>&1; afirma_rc $? 1 "tunnel existe sem credencial: recusa"
grep -q "rode 15-restore.sh antes" "$T/out"; afirma $? "mensagem aponta o restore"
nega_log "-X POST" "nao cria segundo tunnel"
[[ ! -e $T/cloudflared/config.yml ]]; afirma $? "nao escreve config.yml"
fim
```

- [ ] **Step 2: Rodar e ver falhar**

```bash
TESTAR
```

Esperado: `FALHA tunnel existe sem credencial: recusa` (hoje o `06` lê `/srv/dev/secrets/.env` fixo e segue adiante).

- [ ] **Step 3: Alterar `scripts/06-tunnel.sh`**

Trocar a checagem de root e o carregamento do `.env`:

```bash
[[ $EUID -eq 0 || ${STACK_TESTE:-} == 1 ]] || { echo "rode como root"; exit 1; }
EMAIL="${1:?informe o e-mail da politica de Access}"
ZONA=esper.ws
HOST=ssh.$ZONA
ENVF=${STACK_ENV:-/srv/dev/secrets/.env}
CFD=${STACK_CF_DIR:-/etc/cloudflared}

# shellcheck source=/dev/null
set -a; . "$ENVF"; set +a
```

Logo depois da busca do `TID` (antes do `if [[ -z $TID ]]`), inserir:

```bash
# VPS reinstalada: o tunnel existe na Cloudflare, mas a credencial so nasce na criacao.
# Ela volta pelo backup; criar outro tunnel deixaria o DNS apontando para o antigo.
if [[ -n $TID && ! -s $CFD/credentials.json ]]; then
  echo "tunnel stack-vps existe mas falta $CFD/credentials.json: rode 15-restore.sh antes"; exit 1
fi
```

Substituir no resto do script todas as ocorrências de `/etc/cloudflared` por `$CFD` (são cinco: `install -d`, a escrita do `credentials.json`, o `cat >` do `config.yml`, e as duas referências dentro do heredoc do `config.yml` — `credentials-file: $CFD/credentials.json`).

Trocar o eco final de validação:

```bash
echo "Valide o caminho de reserva: ssh stack-cf"
```

- [ ] **Step 4: Rodar e ver passar**

```bash
TESTAR
```

Esperado: `06-tunnel` com 4 `ok`.

- [ ] **Step 5: Seção `acesso` no `bin/health.sh`**

Substituir o bloco `echo "tunnel"` … `fi` por:

```bash
echo "acesso"
if systemctl is-active --quiet tailscaled && ip4=$(tailscale ip -4 2>/dev/null | head -1) && [[ $ip4 == 100.* ]]; then
  ok "tailscale na tailnet ($ip4)"
else bad "tailscale fora da tailnet"; fi
if systemctl is-active --quiet cloudflared; then ok "cloudflared ativo (reserva)"
else bad "cloudflared parado"; fi
```

- [ ] **Step 6: Reescrever `docs/ssh-config-wsl.md`**

````markdown
# ~/.ssh/config na máquina local (dentro do WSL)

Dois caminhos para a mesma VPS: `stack` pela tailnet (principal) e `stack-cf` pelo Cloudflare
Tunnel (reserva). Se os dois caírem, o console do hPanel é a emergência.

## Pré-requisitos

- Tailscale no Windows, logado na mesma tailnet. O WSL usa a rede do Windows.
- Para o `stack-cf`, o `cloudflared` dentro do WSL:

```sh
curl -fsSL https://pkg.cloudflare.com/cloudflare-main.gpg | sudo tee /usr/share/keyrings/cloudflare-main.gpg >/dev/null
echo 'deb [signed-by=/usr/share/keyrings/cloudflare-main.gpg] https://pkg.cloudflare.com/cloudflared any main' | sudo tee /etc/apt/sources.list.d/cloudflared.list
sudo apt update && sudo apt install -y cloudflared
```

## Blocos

```
Host stack
    HostName stack
    User dev
    IdentityFile ~/.ssh/id_ed25519_stackvps
    IdentitiesOnly yes
    ServerAliveInterval 30
    ServerAliveCountMax 3

Host stack-cf
    HostName ssh.esper.ws
    User dev
    IdentityFile ~/.ssh/id_ed25519_stackvps
    IdentitiesOnly yes
    ProxyCommand cloudflared access ssh --hostname %h
    ServerAliveInterval 30
    ServerAliveCountMax 3
```

Se `ssh stack` disser que não resolve o nome, o WSL está em modo NAT e o MagicDNS não chega
nele. Troque `HostName stack` pelo IP `100.x` que aparece em `tailscale status` no Windows.

## Login do Access (só para `stack-cf`)

O WSL não abre navegador sozinho. Antes do primeiro `ssh stack-cf`, rode:

```sh
cloudflared access login https://ssh.esper.ws
```

Ele imprime uma URL: abra no navegador do Windows, autentique, e o token vale 24h.
Sem esse passo o `ssh stack-cf` fica parado esperando, sem mensagem.

## VS Code

Remote-SSH apontando para `stack`. Com a extensão WSL ativa, o VS Code do Windows usa este mesmo
perfil — não duplique a configuração no `%USERPROFILE%\.ssh\config`.

## Portas de desenvolvimento

Com a tailnet, um serviço na porta 3000 da VPS abre no navegador do laptop em
`http://stack:3000`. No Docker, publique só no loopback ou no IP da tailnet
(`-p 127.0.0.1:3000:3000`): porta publicada pelo Docker ignora o UFW.
````

- [ ] **Step 7: Rodar e commitar**

```bash
TESTAR
git add scripts/06-tunnel.sh bin/health.sh docs/ssh-config-wsl.md tests/test-06-tunnel.sh
git commit -m "feat: tunnel de reserva recusa subir sem credencial; health confere Tailscale"
```

Esperado no `TESTAR`: tudo `ok`, código 0.

---

## Fase 0a — acesso (operação na VPS atual)

### Task 5: Tailscale na VPS atual

**Portão:** o Ricardo gera a auth key e, depois, desativa a expiração da chave do nó.

**Files:** nenhum versionado.

**Interfaces:**
- Consumes: `scripts/01b-tailscale.sh` (Task 2), em `~/stack-vps-wip` na VPS (enviado pelo `TESTAR`).
- Produces: nó `stack` na tailnet; `VPS_HOST=dev@stack` passa a valer para o resto do plano.

- [ ] **Step 1: Pedir a auth key ao Ricardo**

Mensagem ao Ricardo: abrir https://login.tailscale.com/admin/settings/keys → **Generate auth key** → Reusable desligado, Ephemeral desligado → **Generate key**. Ele **não** cola a chave no chat: roda o comando do Step 2 no terminal dele.

- [ ] **Step 2: Ricardo roda a entrada na tailnet**

Comando para o Ricardo colar no PowerShell (a chave é pedida sem eco e não fica no histórico):

```powershell
ssh -t -i $env:USERPROFILE\.ssh\id_ed25519_stackvps dev@148.230.77.242 'read -rsp "auth key: " k; echo; sudo TS_AUTHKEY="$k" bash ~/stack-vps-wip/scripts/01b-tailscale.sh'
```

Esperado: `tailscale: 100.x.y.z — desative a expiracao de chave do no 'stack' no painel`.

- [ ] **Step 3: Ricardo desativa a expiração**

https://login.tailscale.com/admin/machines → nó **stack** → menu **…** → **Disable key expiry**.

- [ ] **Step 4: Validar pelo Windows**

```bash
"/c/Program Files/Tailscale/tailscale.exe" status | grep -w stack
VPS_HOST=dev@stack
SSHV 'hostname; tailscale ip -4'
```

Esperado: linha do `stack` sem `offline`; `stack` e o IP `100.x`.

- [ ] **Step 5: Validar pelo WSL**

```bash
wsl -e bash -lc 'getent hosts stack || echo SEM-MAGICDNS; timeout 20 ssh -o BatchMode=yes -i ~/.ssh/id_ed25519_stackvps dev@stack hostname'
```

Esperado: `stack`. Se aparecer `SEM-MAGICDNS`, repetir o `ssh` com o IP `100.x` e registrar no `docs/ssh-config-wsl.md` que o WSL deste laptop precisa do IP (a doc já traz o desvio).

---

### Task 6: Validar o tunnel de reserva

O log do `cloudflared` em 05/10 mostra conexões registradas (GRU) com reconexões normais; o travamento da sessão foi o `cloudflared access ssh` esperando login no navegador. Esta task prova o caminho e atualiza o binário (o log avisa versão 2026.9.1 desatualizada).

**Portão:** o Ricardo abre a URL de login do Access.

- [ ] **Step 1: Estado do tunnel na VPS**

```bash
SSHV 'systemctl is-active cloudflared; sudo journalctl -u cloudflared --since "-2h" --no-pager | grep -c "Registered tunnel connection"; cloudflared --version'
```

Esperado: `active`, contagem ≥ 1.

- [ ] **Step 2: Atualizar o cloudflared**

```bash
SSHV 'sudo apt-get -o DPkg::Lock::Timeout=600 install -y -qq --only-upgrade cloudflared >/dev/null; cloudflared --version; sudo systemctl restart cloudflared; sleep 5; systemctl is-active cloudflared'
```

Esperado: versão ≥ 2026.9.3 e `active`. Se o pacote não vier do apt (instalado por `cloudflared service install` a partir de binário), registrar a origem e seguir sem atualizar.

- [ ] **Step 3: Login do Access e `ssh stack-cf`**

O Ricardo aplica os blocos do `docs/ssh-config-wsl.md` (Task 4) no `~/.ssh/config` do WSL e roda no WSL:

```sh
cloudflared access login https://ssh.esper.ws
ssh stack-cf hostname
```

Esperado: `stack`. Se o login não imprimir URL, ou se o `ssh stack-cf` falhar depois do login, parar aqui e diagnosticar com o log do serviço:

```bash
SSHV 'sudo journalctl -u cloudflared -n 50 --no-pager'
```

e com a API (aplicação de Access de `ssh.esper.ws` e política `so-o-dono` existentes):

```bash
SSHV 'set -a; . /srv/dev/secrets/.env; set +a; curl -s -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" "https://api.cloudflare.com/client/v4/accounts/$CLOUDFLARE_ACCOUNT_ID/access/apps" | python3 -c "import sys,json;print([a[\"domain\"] for a in json.load(sys.stdin).get(\"result\") or []])"'
```

Esperado: lista contendo `ssh.esper.ws`.

---

### Task 7: Fechar a 22 pública na VPS atual

**Portão:** `ssh stack` (Task 5) e `ssh stack-cf` (Task 6) validados.

- [ ] **Step 1: Abrir uma segunda sessão de segurança**

O Ricardo deixa uma sessão `ssh stack` aberta num terminal à parte durante esta task.

- [ ] **Step 2: Aplicar o `07`**

```bash
SSHV 'sudo bash ~/stack-vps-wip/scripts/07-firewall.sh'
```

Esperado: `Status: active`, `Default: deny (incoming)`, e uma regra `22/tcp on tailscale0 ALLOW IN Anywhere`.

- [ ] **Step 3: Provar os três comportamentos**

```bash
SSHV hostname                                                    # tailnet: responde "stack"
/c/Windows/System32/OpenSSH/ssh.exe -o BatchMode=yes -o ConnectTimeout=8 -i ~/.ssh/id_ed25519_stackvps dev@148.230.77.242 hostname; echo "rc=$?"
wsl -e bash -lc 'timeout 30 ssh stack-cf hostname'               # tunnel: responde "stack"
```

Esperado: `stack`; `Connection timed out` com `rc=255`; `stack`.

Se o `SSHV hostname` falhar: entrar pelo console do hPanel (Ricardo) e rodar `ufw allow 22/tcp`; voltar à Task 5.

- [ ] **Step 4: Instalar o health novo e conferir**

```bash
SSHV 'install -m 755 ~/stack-vps-wip/bin/health.sh /srv/dev/bin/health.sh && /srv/dev/bin/health.sh'
```

Esperado: `ok tailscale na tailnet`, `ok cloudflared ativo (reserva)`, `ok docker`, `FALHA backup nunca rodou` (esperado até a fase 2), `ok disco`.

---

## Fase 0 — scripts

### Task 8: Backup (`14-backup.sh` + `lib/restic-env.sh`)

**Files:**
- Create: `scripts/lib/restic-env.sh`, `scripts/14-backup.sh`, `tests/test-14-backup.sh`

**Interfaces:**
- Consumes: `tests/lib.sh`.
- Produces:
  - `scripts/lib/restic-env.sh` (para `source`): carrega `${STACK_ENV:-$STACK_ROOT/srv/dev/secrets/.env}` se não vazio; exige `CLOUDFLARE_ACCOUNT_ID`, `R2_ACCESS_KEY_ID`, `R2_SECRET_ACCESS_KEY`, `RESTIC_PASSWORD`; exporta `RESTIC_REPOSITORY`, `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, `AWS_DEFAULT_REGION=auto`; define os arrays `BACKUP_PATHS` e `BACKUP_EXCLUDES`, prefixados por `STACK_ROOT` (vazio em produção).
  - `scripts/14-backup.sh`: sem argumentos; sai ≠ 0 em qualquer falha; grava `$STACK_ROOT/srv/dev/state/.last-backup` só no sucesso.

- [ ] **Step 1: Escrever o teste**

`tests/test-14-backup.sh`:

```bash
#!/usr/bin/env bash
# shellcheck source=tests/lib.sh
. "$(dirname "$0")/lib.sh"
S=$RAIZ_REPO/scripts/14-backup.sh
echo "14-backup"

prepara() { # raiz falsa com o que o backup espera
  export STACK_ROOT=$T/raiz; unset STACK_ENV
  mkdir -p "$STACK_ROOT"/srv/dev/{state,data,secrets} "$STACK_ROOT"/home/dev/.claude
  echo "X=1" > "$STACK_ROOT/srv/dev/secrets/.env"
  export CLOUDFLARE_ACCOUNT_ID=acc R2_ACCESS_KEY_ID=k R2_SECRET_ACCESS_KEY=s RESTIC_PASSWORD=p
  stub chown
}
restic_stub() { # restic que falha no subcomando $1 (ou em nenhum)
  cat > "$STUBS/restic" <<EOF
#!/usr/bin/env bash
echo "restic \$* repo=\$RESTIC_REPOSITORY" >> "\$STUB_LOG"
[[ \$1 == "$1" ]] && exit 1
exit 0
EOF
  chmod +x "$STUBS/restic"; }

novo_tmp; prepara; restic_stub nenhum
bash "$S" >/dev/null 2>&1; afirma_rc $? 0 "sucesso"
[[ -f $STACK_ROOT/srv/dev/state/.last-backup ]]; afirma $? "sucesso grava .last-backup"
afirma_log "repo=s3:https://acc.r2.cloudflarestorage.com/stack-vps-backup" "repositorio no R2 da conta"
afirma_log "restic forget --keep-daily 7 --keep-weekly 4 --keep-monthly 6 --prune" "retencao do spec"
afirma_log "/home/dev/.claude/.credentials.json" "credencial do Claude excluida"
afirma_log "/srv/dev/state" "state no backup"

novo_tmp; prepara; restic_stub backup
bash "$S" >/dev/null 2>&1; afirma_rc $? 1 "falha no backup: sai com erro"
[[ ! -e $STACK_ROOT/srv/dev/state/.last-backup ]]; afirma $? "falha no backup: sem .last-backup"
nega_log "restic forget" "falha no backup: nao poda"

novo_tmp; prepara; restic_stub nenhum; unset RESTIC_PASSWORD
bash "$S" >/dev/null 2>&1; afirma_rc $? 1 "sem RESTIC_PASSWORD: recusa"
nega_log "restic" "sem senha: restic nao roda"
fim
```

- [ ] **Step 2: Rodar e ver falhar**

```bash
TESTAR
```

Esperado: `14-backup` com `FALHA` (script inexistente).

- [ ] **Step 3: Escrever `scripts/lib/restic-env.sh`**

```bash
# Ambiente do restic: .env da VPS ou, na VPS recem-formatada, o que ja estiver exportado.
# Fonte: . scripts/lib/restic-env.sh   (STACK_ROOT so existe nos testes)
# shellcheck shell=bash disable=SC2034  # BACKUP_* usados por 14 e 15
R=${STACK_ROOT:-}
ENVF=${STACK_ENV:-$R/srv/dev/secrets/.env}
# shellcheck source=/dev/null
if [[ -s $ENVF ]]; then set -a; . "$ENVF"; set +a; fi

: "${CLOUDFLARE_ACCOUNT_ID:?falta CLOUDFLARE_ACCOUNT_ID}"
: "${R2_ACCESS_KEY_ID:?falta R2_ACCESS_KEY_ID}"
: "${R2_SECRET_ACCESS_KEY:?falta R2_SECRET_ACCESS_KEY}"
: "${RESTIC_PASSWORD:?falta RESTIC_PASSWORD}"

export RESTIC_REPOSITORY="s3:https://${CLOUDFLARE_ACCOUNT_ID}.r2.cloudflarestorage.com/stack-vps-backup"
export AWS_ACCESS_KEY_ID=$R2_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY=$R2_SECRET_ACCESS_KEY
export AWS_DEFAULT_REGION=auto RESTIC_PASSWORD

# Repositorios ficam de fora: a verdade e o GitHub. Identidade do Tailscale tambem: o no novo
# entra antes do restore. Plugins do Claude sao reinstalados pelo 04.
BACKUP_PATHS=("$R/srv/dev/state" "$R/srv/dev/data" "$R/srv/dev/secrets/.env"
              "$R/etc/cloudflared/credentials.json" "$R/home/dev/.claude" "$R/home/dev/.codex")
BACKUP_EXCLUDES=("$R/home/dev/.claude/.credentials.json" "$R/home/dev/.codex/auth.json"
                 "$R/home/dev/.claude/plugins" "node_modules")
```

- [ ] **Step 4: Escrever `scripts/14-backup.sh`**

```bash
#!/usr/bin/env bash
# Backup restic -> R2 (bucket stack-vps-backup). Roda como root, pelo timer diario.
# Grava state/.last-backup so se backup, poda e (aos domingos) verificacao passarem.
set -euo pipefail
[[ $EUID -eq 0 || ${STACK_TESTE:-} == 1 ]] || { echo "rode como root"; exit 1; }
# shellcheck source=scripts/lib/restic-env.sh
. "$(dirname "$(readlink -f "$0")")/lib/restic-env.sh"
STAMP=${STACK_ROOT:-}/srv/dev/state/.last-backup

restic cat config >/dev/null 2>&1 || restic init

paths=(); for p in "${BACKUP_PATHS[@]}"; do [[ -e $p ]] && paths+=("$p"); done
(( ${#paths[@]} )) || { echo "nenhum caminho do backup existe"; exit 1; }
excl=(); for e in "${BACKUP_EXCLUDES[@]}"; do excl+=(--exclude "$e"); done

restic backup --one-file-system "${excl[@]}" "${paths[@]}"
restic forget --keep-daily 7 --keep-weekly 4 --keep-monthly 6 --prune
if [[ $(date +%u) == 7 ]]; then restic check --read-data-subset=5%; fi

touch "$STAMP"; chown dev:dev "$STAMP" 2>/dev/null || true
echo "backup ok: $(date -Is)"
```

- [ ] **Step 5: Rodar e ver passar**

```bash
TESTAR
```

Esperado: `14-backup` com 11 `ok`.

- [ ] **Step 6: Commit**

```bash
git add scripts/lib/restic-env.sh scripts/14-backup.sh tests/test-14-backup.sh tests/run.sh
git commit -m "feat: backup restic no R2 com retencao e marca de ultimo backup"
```

---

### Task 9: Restore (`15-restore.sh`)

**Files:**
- Create: `scripts/15-restore.sh`, `tests/test-15-restore.sh`

**Interfaces:**
- Consumes: `scripts/lib/restic-env.sh` (`BACKUP_PATHS`, variáveis do restic) — Task 8.
- Produces: `sudo ./15-restore.sh [--destino DIR] [--forcar]`; padrão `--destino /`. Recusa (rc 1, restic não roda) se algum arquivo **não vazio** existir sob `DIR/<caminho do backup>`, salvo `--forcar`. Com destino `/`, reaplica dono e modo.

- [ ] **Step 1: Escrever o teste**

`tests/test-15-restore.sh`:

```bash
#!/usr/bin/env bash
# shellcheck source=tests/lib.sh
. "$(dirname "$0")/lib.sh"
S=$RAIZ_REPO/scripts/15-restore.sh
echo "15-restore"

prepara() {
  unset STACK_ROOT
  export CLOUDFLARE_ACCOUNT_ID=acc R2_ACCESS_KEY_ID=k R2_SECRET_ACCESS_KEY=s RESTIC_PASSWORD=p
  D=$T/dest; mkdir -p "$D"; stub restic; stub chown; stub chmod
}

novo_tmp; prepara
mkdir -p "$D/srv/dev/state"; echo conteudo > "$D/srv/dev/state/inventario.md"
bash "$S" --destino "$D" >/dev/null 2>&1; afirma_rc $? 1 "destino com dado: recusa"
nega_log "restic restore" "destino com dado: restic nao roda"

novo_tmp; prepara
mkdir -p "$D/srv/dev/state"; echo conteudo > "$D/srv/dev/state/inventario.md"
bash "$S" --destino "$D" --forcar >/dev/null 2>&1; afirma_rc $? 0 "com --forcar: restaura"

novo_tmp; prepara   # VPS recem-formatada: o 02 criou .env vazio e state/reviews vazio
mkdir -p "$D/srv/dev/secrets" "$D/srv/dev/state/reviews"; : > "$D/srv/dev/secrets/.env"
bash "$S" --destino "$D" >/dev/null 2>&1; afirma_rc $? 0 "VPS recem-formatada: restaura"
afirma_log "restic restore latest --target $D" "restaura o ultimo snapshot no destino"
afirma_log "--include /srv/dev/secrets/.env" "inclui o .env"
afirma_log "--include /etc/cloudflared/credentials.json" "inclui a credencial do tunnel"
nega_log "chown" "destino de teste: nao mexe em dono"

novo_tmp; prepara
bash "$S" --qualquer >/dev/null 2>&1; afirma_rc $? 1 "argumento desconhecido: recusa"
fim
```

- [ ] **Step 2: Rodar e ver falhar**

```bash
TESTAR
```

Esperado: `15-restore` com `FALHA`.

- [ ] **Step 3: Escrever `scripts/15-restore.sh`**

```bash
#!/usr/bin/env bash
# Restaura do restic os caminhos do backup. Uso: sudo ./15-restore.sh [--destino DIR] [--forcar]
# Na VPS recem-formatada o .env ainda nao existe: antes, exporte CLOUDFLARE_ACCOUNT_ID,
# R2_ACCESS_KEY_ID, R2_SECRET_ACCESS_KEY e RESTIC_PASSWORD (as tres ultimas do gerenciador de senhas).
set -euo pipefail
[[ $EUID -eq 0 || ${STACK_TESTE:-} == 1 ]] || { echo "rode como root"; exit 1; }
DEST=/; FORCAR=0
while (($#)); do
  case $1 in
    --destino) DEST=${2:?informe o diretorio}; shift 2 ;;
    --forcar)  FORCAR=1; shift ;;
    *) echo "uso: $0 [--destino DIR] [--forcar]"; exit 1 ;;
  esac
done
# shellcheck source=scripts/lib/restic-env.sh
. "$(dirname "$(readlink -f "$0")")/lib/restic-env.sh"

# Ocupado = algum arquivo nao vazio onde o backup vai escrever. O .env vazio que o 02 cria nao conta.
ocupado() {
  local p
  for p in "${BACKUP_PATHS[@]}"; do
    [[ -n $(find "$DEST/${p#/}" -type f -size +0 -print -quit 2>/dev/null) ]] && return 0
  done
  return 1
}
if ocupado && (( ! FORCAR )); then
  echo "destino $DEST ja tem dados nos caminhos do backup; use --forcar para sobrescrever"; exit 1
fi

inc=(); for p in "${BACKUP_PATHS[@]}"; do inc+=(--include "$p"); done
restic restore latest --target "$DEST" "${inc[@]}"

if [[ $DEST == / ]]; then
  for d in /srv/dev/state /srv/dev/data /home/dev/.claude /home/dev/.codex; do
    [[ -e $d ]] && chown -R dev:dev "$d"
  done
  [[ -f /srv/dev/secrets/.env ]] && { chown dev:dev /srv/dev/secrets/.env; chmod 600 /srv/dev/secrets/.env; }
  [[ -f /etc/cloudflared/credentials.json ]] && { chown root:root /etc/cloudflared/credentials.json; chmod 600 /etc/cloudflared/credentials.json; }
fi
echo "restore ok em $DEST"
```

- [ ] **Step 4: Rodar e ver passar**

```bash
TESTAR
```

Esperado: `15-restore` com 9 `ok`.

- [ ] **Step 5: Commit**

```bash
git add scripts/15-restore.sh tests/test-15-restore.sh
git commit -m "feat: restore do restic que recusa sobrescrever VPS com dados"
```

---

### Task 10: Serviços instalados por script (`05-servicos.sh`, timer do backup)

**Files:**
- Create: `systemd/stack-backup.service`, `systemd/stack-backup.timer`
- Modify: `scripts/05-servicos.sh`

**Interfaces:**
- Consumes: `scripts/14-backup.sh`, `scripts/15-restore.sh`, `scripts/lib/restic-env.sh`.
- Produces: `/usr/local/lib/stack-vps/{14-backup.sh,15-restore.sh,lib/restic-env.sh}`; `/srv/dev/bin/{health.sh,08..12-*.sh,weekly-review.sh,playwright.yml}`; crontab do `dev` com a rotina semanal; `stack-backup.timer` ativo.

- [ ] **Step 1: Escrever as unidades systemd**

`systemd/stack-backup.service`:

```ini
[Unit]
Description=Backup restic da VPS para o R2
Wants=network-online.target
After=network-online.target

[Service]
Type=oneshot
ExecStart=/usr/local/lib/stack-vps/14-backup.sh
Nice=10
IOSchedulingClass=idle
```

`systemd/stack-backup.timer`:

```ini
[Unit]
Description=Backup diario da VPS (03:00 de Brasilia)

[Timer]
OnCalendar=*-*-* 06:00:00 UTC
RandomizedDelaySec=10m
Persistent=true

[Install]
WantedBy=timers.target
```

- [ ] **Step 2: Acrescentar ao `scripts/05-servicos.sh`**

Trocar o comentário do topo:

```bash
# Servicos de host: tmux persistente, scripts em /srv/dev/bin, rotina semanal e backup diario.
```

e inserir antes do `echo "tmux-dev: ..."` final:

```bash
REPO=$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)

# scripts de rotina do dev
install -d -m 755 -o dev -g dev /srv/dev/bin
install -m 755 -o dev -g dev "$REPO"/bin/health.sh \
  "$REPO"/scripts/{08-clonar-repos,09-clonar-escopo,10-inventario,11-state,12-push-state}.sh /srv/dev/bin/
install -m 755 -o dev -g dev "$REPO"/scripts/13-weekly-review.sh /srv/dev/bin/weekly-review.sh
install -m 644 -o dev -g dev "$REPO"/compose/playwright.yml /srv/dev/bin/

# rotina semanal (segunda 07:00 UTC), no crontab do dev
CRON='0 7 * * 1 /srv/dev/bin/weekly-review.sh >> /srv/dev/state/weekly.log 2>&1'
{ crontab -u dev -l 2>/dev/null | grep -v 'weekly-review.sh' || true; echo "$CRON"; } | crontab -u dev -

# backup e restore fora do /srv/dev/repos: o timer nao pode depender de um clone
install -d -m 755 /usr/local/lib/stack-vps/lib
install -m 755 "$REPO"/scripts/14-backup.sh "$REPO"/scripts/15-restore.sh /usr/local/lib/stack-vps/
install -m 644 "$REPO"/scripts/lib/restic-env.sh /usr/local/lib/stack-vps/lib/
install -m 644 "$REPO"/systemd/stack-backup.service "$REPO"/systemd/stack-backup.timer /etc/systemd/system/
systemctl daemon-reload
systemctl enable --now stack-backup.timer
echo "backup: $(systemctl list-timers stack-backup.timer --no-legend | awk '{print $1, $2, $3}')"
```

- [ ] **Step 3: Shellcheck e verificação das unidades**

```bash
TESTAR
SSHV 'systemd-analyze verify ~/stack-vps-wip/systemd/stack-backup.service ~/stack-vps-wip/systemd/stack-backup.timer 2>&1 | grep -v "14-backup.sh" || true'
```

Esperado: `TESTAR` com código 0; `systemd-analyze` sem erro além do aviso de que `/usr/local/lib/stack-vps/14-backup.sh` ainda não existe.

- [ ] **Step 4: Commit**

```bash
git add systemd/ scripts/05-servicos.sh
git commit -m "feat: 05 instala scripts de rotina, cron semanal e timer do backup"
```

(O `05` só roda na VPS na fase 2, depois que o R2 existir — Task 15.)

---

### Task 11: Envio do laptop (`20-laptop-github.sh`)

**Files:**
- Create: `scripts/20-laptop-github.sh`, `tests/test-20-laptop-github.sh`

**Interfaces:**
- Consumes: `tests/lib.sh`.
- Produces: `20-laptop-github.sh <tsv> [--simular]`. TSV com cabeçalho `origem caminho dono repo arvore acao` (tab). Escreve `<tsv sem .tsv>.resultado.tsv` com linhas `STATUS<TAB>acao<TAB>dono/repo<TAB>detalhe`, STATUS ∈ `OK|PENDENTE|SIMULA`; e, fora do modo simulado, `<tsv sem .tsv>.escopo-novos.tsv` com `dono<TAB>repo<TAB>arvore<TAB>repo` para cada repo enviado ou criado.

- [ ] **Step 1: Escrever o teste**

`tests/test-20-laptop-github.sh`:

```bash
#!/usr/bin/env bash
# shellcheck source=tests/lib.sh
. "$(dirname "$0")/lib.sh"
S=$RAIZ_REPO/scripts/20-laptop-github.sh
echo "20-laptop-github"
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t

prepara() {
  B="$T/Área de Trabalho"; mkdir -p "$B"           # espaco e acento, como no OneDrive
  TSV=$T/migracao.tsv; printf 'origem\tcaminho\tdono\trepo\tarvore\tacao\r\n' > "$TSV"
  stub gitleaks; stub gh
}
linha() { printf 'windows\t%s\t%s\t%s\tapps\t%s\r\n' "$1" "$2" "$3" "$4" >> "$TSV"; }  # CRLF de proposito
remoto() { # remoto/<nome>.git com um commit base e clone local em "$B/<pasta>"
  git init -q --bare -b main "$T/remoto/$1.git"
  git clone -q "$T/remoto/$1.git" "$B/$2" 2>/dev/null
  git -C "$B/$2" commit -q --allow-empty -m base; git -C "$B/$2" push -q origin main 2>/dev/null; }
cabeca() { git --git-dir="$T/remoto/$1.git" rev-parse main; }
res() { cat "${TSV%.tsv}.resultado.tsv"; }

# fast-forward: sobe
novo_tmp; prepara; remoto ff "proj ff"
echo a > "$B/proj ff/a.txt"; git -C "$B/proj ff" add a.txt; git -C "$B/proj ff" commit -qm a
linha "$B/proj ff" resper1965 ff push
bash "$S" "$TSV" >/dev/null 2>&1
[[ $(cabeca ff) == $(git -C "$B/proj ff" rev-parse main) ]]; afirma $? "fast-forward: remoto recebe o commit"
res | grep -q $'^OK\tpush\tresper1965/ff'; afirma $? "fast-forward: OK no resultado"
grep -q $'^resper1965\tff\tapps\tff$' "${TSV%.tsv}.escopo-novos.tsv"; afirma $? "fast-forward: entra no escopo novo"

# divergente: nao sobe
novo_tmp; prepara; remoto dv dv
git clone -q "$T/remoto/dv.git" "$T/outro" 2>/dev/null
git -C "$T/outro" commit -q --allow-empty -m remoto; git -C "$T/outro" push -q origin main 2>/dev/null
antes=$(cabeca dv)
git -C "$B/dv" commit -q --allow-empty -m local
linha "$B/dv" resper1965 dv push
bash "$S" "$TSV" >/dev/null 2>&1
[[ $(cabeca dv) == "$antes" ]]; afirma $? "divergente: remoto intocado"
res | grep -q $'^PENDENTE\tpush\tresper1965/dv\tmain divergiu'; afirma $? "divergente: PENDENTE"

# extensao bloqueada: nao sobe
novo_tmp; prepara; remoto pdf pdf
antes=$(cabeca pdf)
echo x > "$B/pdf/laudo.PDF"; git -C "$B/pdf" add .; git -C "$B/pdf" commit -qm laudo
linha "$B/pdf" forense-io pdf push
bash "$S" "$TSV" >/dev/null 2>&1
[[ $(cabeca pdf) == "$antes" ]]; afirma $? "pdf: remoto intocado"
res | grep -q 'extensao: laudo.PDF'; afirma $? "pdf: motivo no resultado"

# gitleaks aponta segredo: nao sobe
novo_tmp; prepara; remoto sg sg; stub gitleaks 1
antes=$(cabeca sg)
git -C "$B/sg" commit -q --allow-empty -m x
linha "$B/sg" resper1965 sg push
bash "$S" "$TSV" >/dev/null 2>&1
[[ $(cabeca sg) == "$antes" ]]; afirma $? "segredo: remoto intocado"
res | grep -q 'segredo apontado pelo gitleaks'; afirma $? "segredo: motivo no resultado"

# simulacao: nada sobe
novo_tmp; prepara; remoto sim sim
antes=$(cabeca sim)
git -C "$B/sim" commit -q --allow-empty -m x
linha "$B/sim" resper1965 sim push
bash "$S" "$TSV" --simular >/dev/null 2>&1
[[ $(cabeca sim) == "$antes" ]]; afirma $? "simular: remoto intocado"
res | grep -q $'^SIMULA\tpush'; afirma $? "simular: SIMULA no resultado"

# criar: pasta sem git vira repo privado
novo_tmp; prepara
mkdir -p "$B/novo proj"; echo 'print(1)' > "$B/novo proj/main.py"
linha "$B/novo proj" bekaa-trusted-advisors novo criar
bash "$S" "$TSV" >/dev/null 2>&1
afirma_log "gh repo create bekaa-trusted-advisors/novo --private --source $B/novo proj" "criar: gh com --private"
git -C "$B/novo proj" rev-parse -q --verify HEAD >/dev/null; afirma $? "criar: commit inicial feito"

# criar com planilha: nada acontece na pasta
novo_tmp; prepara
mkdir -p "$B/prop"; echo x > "$B/prop/precos.xlsx"
linha "$B/prop" resper1965 prop criar
bash "$S" "$TSV" >/dev/null 2>&1
[[ ! -d $B/prop/.git ]]; afirma $? "criar bloqueado: pasta sem .git"
nega_log "gh repo create" "criar bloqueado: gh nao chamado"

# fica: ignorado
novo_tmp; prepara
mkdir -p "$B/lixo"; linha "$B/lixo" resper1965 lixo fica
bash "$S" "$TSV" >/dev/null 2>&1
[[ ! -s ${TSV%.tsv}.resultado.tsv ]]; afirma $? "fica: nada no resultado"
fim
```

- [ ] **Step 2: Rodar e ver falhar**

```bash
TESTAR
```

Esperado: `20-laptop-github` com `FALHA` (script inexistente).

- [ ] **Step 3: Escrever `scripts/20-laptop-github.sh`**

```bash
#!/usr/bin/env bash
# Envia ao GitHub o trabalho do laptop conforme o TSV de decisao (docs/migracao-laptop.tsv).
# Roda no WSL. Nunca usa force: branch divergente, segredo ou arquivo bloqueado vira PENDENTE.
# Uso: 20-laptop-github.sh <tsv> [--simular]
# TSV (tab, com cabecalho): origem caminho dono repo arvore acao   — acao: push | criar | fica
set -uo pipefail
TSV=${1:?uso: $0 <tsv> [--simular]}
SIMULAR=0; [[ ${2:-} == --simular ]] && SIMULAR=1
RES=${TSV%.tsv}.resultado.tsv
NOVOS=${TSV%.tsv}.escopo-novos.tsv
EXT_BLOQ='\.(pst|e01|dd|zip|xlsx|csv|pdf)$'
MAX=$((50 * 1024 * 1024))

for c in git gitleaks; do command -v "$c" >/dev/null || { echo "falta $c"; exit 1; }; done
: > "$RES"; (( SIMULAR )) || : > "$NOVOS"

registra() { printf '%s\t%s\t%s/%s\t%s\n' "$1" "$2" "$3" "$4" "$5" | tee -a "$RES"; }
novo_escopo() { (( SIMULAR )) || printf '%s\t%s\t%s\t%s\n' "$1" "$2" "$3" "$2" >> "$NOVOS"; }

# Le caminhos no stdin e imprime o primeiro motivo de bloqueio. Com $2 (ref), mede o tamanho no git.
bloqueio() {
  local base=$1 ref=${2:-} f s
  while IFS= read -r f; do
    [[ -z $f ]] && continue
    if [[ ${f,,} =~ $EXT_BLOQ ]]; then echo "extensao: $f"; return 0; fi
    if [[ -n $ref ]]; then s=$(git -C "$base" cat-file -s "$ref:$f" 2>/dev/null || echo 0)
    else s=$(stat -c %s "$base/$f" 2>/dev/null || echo 0); fi
    if (( s > MAX )); then echo "acima de 50MB: $f"; return 0; fi
  done
  return 0
}

sujo() { [[ -n $(git -C "$1" status --porcelain 2>/dev/null) ]] && echo " (ha alteracoes nao commitadas, ficaram no laptop)"; }

faz_push() {
  local d=$1 dono=$2 repo=$3 arvore=$4 b ahead behind motivo enviou=0
  local -a range
  git -C "$d" rev-parse --git-dir >/dev/null 2>&1 || { registra PENDENTE push "$dono" "$repo" "nao e repositorio git"; return; }
  git -C "$d" fetch -q origin </dev/null 2>/dev/null || { registra PENDENTE push "$dono" "$repo" "fetch falhou"; return; }
  while IFS= read -r -u 4 b; do
    if git -C "$d" rev-parse -q --verify "refs/remotes/origin/$b" >/dev/null; then
      behind=$(git -C "$d" rev-list --count "$b..origin/$b")
      ahead=$(git -C "$d" rev-list --count "origin/$b..$b")
      (( ahead == 0 )) && continue
      if (( behind > 0 )); then registra PENDENTE push "$dono" "$repo" "$b divergiu ($ahead a frente, $behind atras)"; continue; fi
      range=("origin/$b..$b")
    else
      range=("$b" --not --remotes=origin)
      ahead=$(git -C "$d" rev-list --count "${range[@]}")
      (( ahead == 0 )) && continue
    fi
    motivo=$(git -C "$d" log --name-only --format= "${range[@]}" | sort -u | bloqueio "$d" "$b")
    if [[ -n $motivo ]]; then registra PENDENTE push "$dono" "$repo" "$b $motivo"; continue; fi
    if ! gitleaks detect --source "$d" --no-banner --redact --log-opts="${range[*]}" >/dev/null 2>&1 </dev/null; then
      registra PENDENTE push "$dono" "$repo" "$b segredo apontado pelo gitleaks"; continue; fi
    if (( SIMULAR )); then registra SIMULA push "$dono" "$repo" "$b: $ahead commit(s)$(sujo "$d")"; continue; fi
    if git -C "$d" push -q origin "refs/heads/$b:refs/heads/$b" </dev/null 2>/dev/null; then
      registra OK push "$dono" "$repo" "$b: $ahead commit(s)$(sujo "$d")"; enviou=1
    else registra PENDENTE push "$dono" "$repo" "$b push recusado"; fi
  done 4< <(git -C "$d" for-each-ref --format='%(refname:short)' refs/heads)
  (( enviou )) && novo_escopo "$dono" "$repo" "$arvore"
  return 0
}

faz_criar() {
  local d=$1 dono=$2 repo=$3 arvore=$4 motivo eh_git=0
  [[ -d $d ]] || { registra PENDENTE criar "$dono" "$repo" "pasta nao existe"; return; }
  git -C "$d" rev-parse --git-dir >/dev/null 2>&1 && eh_git=1
  if (( eh_git )) && git -C "$d" remote get-url origin >/dev/null 2>&1; then
    registra PENDENTE criar "$dono" "$repo" "ja tem remoto: use push"; return; fi
  if (( eh_git )); then motivo=$(git -C "$d" ls-files -co --exclude-standard | bloqueio "$d")
  else motivo=$(cd "$d" && find . \( -name .git -o -name node_modules \) -prune -o -type f -print | sed 's|^\./||' | bloqueio "$d"); fi
  if [[ -n $motivo ]]; then registra PENDENTE criar "$dono" "$repo" "$motivo"; return; fi
  local -a gl=(detect --source "$d" --no-banner --redact); (( eh_git )) || gl+=(--no-git)
  gitleaks "${gl[@]}" >/dev/null 2>&1 </dev/null || { registra PENDENTE criar "$dono" "$repo" "segredo apontado pelo gitleaks"; return; }
  if (( SIMULAR )); then registra SIMULA criar "$dono" "$repo" "repo privado novo"; return; fi
  command -v gh >/dev/null || { registra PENDENTE criar "$dono" "$repo" "falta gh"; return; }
  (( eh_git )) || git -C "$d" init -q -b main
  if ! git -C "$d" rev-parse -q --verify HEAD >/dev/null; then
    git -C "$d" add -A && git -C "$d" commit -q -m "chore: importacao inicial do laptop"
  fi
  if gh repo create "$dono/$repo" --private --source "$d" --remote origin --push >/dev/null 2>&1 </dev/null; then
    registra OK criar "$dono" "$repo" "repo privado criado$(sujo "$d")"; novo_escopo "$dono" "$repo" "$arvore"
  else registra PENDENTE criar "$dono" "$repo" "gh repo create falhou"; fi
}

while IFS=$'\t' read -r -u 3 origem caminho dono repo arvore acao; do
  acao=${acao%$'\r'}
  [[ -z $origem || $origem == origem ]] && continue
  case $acao in
    push)  faz_push  "$caminho" "$dono" "$repo" "$arvore" ;;
    criar) faz_criar "$caminho" "$dono" "$repo" "$arvore" ;;
    fica)  ;;
    *) registra PENDENTE "$acao" "$dono" "$repo" "acao desconhecida" ;;
  esac
done 3< "$TSV"

echo
echo "OK: $(grep -c '^OK' "$RES") | PENDENTE: $(grep -c '^PENDENTE' "$RES") | SIMULA: $(grep -c '^SIMULA' "$RES")"
echo "resultado: $RES"
```

- [ ] **Step 4: Rodar e ver passar**

```bash
TESTAR
```

Esperado: `20-laptop-github` com 16 `ok`. Se o caso `criar` falhar por `--source` com espaço no log, conferir que o stub registra os argumentos separados por espaço (é o esperado: `--source $B/novo proj`).

- [ ] **Step 5: Commit**

```bash
git add scripts/20-laptop-github.sh tests/test-20-laptop-github.sh
git commit -m "feat: envio do laptop ao GitHub sem force, com bloqueio de segredo e documento"
```

---

### Task 12: Documentação e regra do Docker

**Files:**
- Create: `.env.example`
- Modify: `README.md`, `docs/srv-dev-README.md`, `docs/CLAUDE.md`, `docs/AGENTS.md`

- [ ] **Step 1: `.env.example`**

```
# Nomes das chaves de /srv/dev/secrets/.env (modo 600, dono dev). Valores nunca entram no Git.
GITHUB_TOKEN=
CLOUDFLARE_API_TOKEN=
CLOUDFLARE_ACCOUNT_ID=
HOSTINGER_API=
COMPOSIO_API_KEY=
SERPAPI_API_KEY=
FEATHERLESS_API_KEY=
# backup — as tres tambem ficam no gerenciador de senhas: sem elas nao ha restore
R2_ACCESS_KEY_ID=
R2_SECRET_ACCESS_KEY=
RESTIC_PASSWORD=
```

O `.gitignore` tem `*.env` e `.env`; `.env.example` não casa com nenhum dos dois. Conferir:

```bash
git check-ignore -v .env.example || echo "nao ignorado"
```

Esperado: `nao ignorado`.

- [ ] **Step 2: `README.md`**

```markdown
# stack-vps

Provisionamento da VPS de desenvolvimento (Hostinger KVM 8, Ubuntu 24.04 + Docker).
Fonte da verdade do ambiente: recriar a VPS é rodar os scripts desta pasta na ordem e restaurar o backup.

## Ordem (VPS recém-formatada, como root)

| # | Script | O que faz |
|---|---|---|
| 01 | `TS_AUTHKEY=… ./scripts/01-baseline.sh "<chave-ed25519>"` | usuário dev, sshd, fail2ban, Tailscale (`01b`) |
| 02 | `./scripts/02-layout.sh` | árvore `/srv/dev` |
| 03 | `./scripts/03-tooling.sh` | ferramentas, Node via mise |
| 05 | `./scripts/05-servicos.sh` | tmux, scripts de rotina, cron semanal, timer do backup |
| 15 | `./scripts/15-restore.sh` | `.env`, credencial do tunnel, `state/`, `data/`, config dos agentes |
| 06 | `./scripts/06-tunnel.sh <e-mail>` | Cloudflare Tunnel de reserva (`ssh stack-cf`) |
| 07 | `./scripts/07-firewall.sh` | UFW: 22 só pela tailnet |
| 04 | `sudo -u dev ./scripts/04-agents.sh` | Claude Code, Codex, plugins, MCP |
| 09 | `sudo -u dev ./scripts/09-clonar-escopo.sh /srv/dev/state/escopo-auditoria.tsv` | clones do escopo |

Roteiro completo em `docs/srv-dev-README.md`. Testes: `bash tests/run.sh` (precisa de `shellcheck`).

## Convenção

Todo script é idempotente: rodar de novo não quebra o que já existe.
Nada de segredo aqui — segredo vive em `/srv/dev/secrets/.env` (modo 600) na VPS; os nomes estão em `.env.example`.
```

- [ ] **Step 3: `docs/srv-dev-README.md`** — substituir as seções "Recuperar do zero" e "Pendente" por:

````markdown
## Acesso

`ssh stack` pela tailnet (principal), `ssh stack-cf` pelo Cloudflare Tunnel (reserva), console do
hPanel em emergência. Nenhuma porta responde no IP público. Configuração do laptop em
`ssh-config-wsl.md`.

## Recuperar do zero

Fora da VPS, antes de começar: as três chaves do backup (`R2_ACCESS_KEY_ID`, `R2_SECRET_ACCESS_KEY`,
`RESTIC_PASSWORD`) no gerenciador de senhas, uma auth key nova do Tailscale e o nó antigo `stack`
removido do painel do Tailscale.

Numa VPS Ubuntu 24.04 recém-criada, como root pelo IP:

```sh
git clone https://github.com/resper1965/stack-vps /tmp/stack-vps && cd /tmp/stack-vps
read -rsp "auth key do Tailscale: " TS_AUTHKEY; echo; export TS_AUTHKEY
./scripts/01-baseline.sh "<chave-publica-ed25519>"      # daqui em diante: ssh stack
./scripts/02-layout.sh
mv /tmp/stack-vps /srv/dev/repos/infra/stack-vps && chown -R dev:dev /srv/dev/repos/infra/stack-vps
cd /srv/dev/repos/infra/stack-vps
./scripts/03-tooling.sh
./scripts/05-servicos.sh
export CLOUDFLARE_ACCOUNT_ID=<id da conta>
read -rsp "R2_ACCESS_KEY_ID: " R2_ACCESS_KEY_ID; echo
read -rsp "R2_SECRET_ACCESS_KEY: " R2_SECRET_ACCESS_KEY; echo
read -rsp "RESTIC_PASSWORD: " RESTIC_PASSWORD; echo
export R2_ACCESS_KEY_ID R2_SECRET_ACCESS_KEY RESTIC_PASSWORD
./scripts/15-restore.sh
./scripts/06-tunnel.sh <e-mail-da-politica>
./scripts/07-firewall.sh
sudo -u dev ./scripts/04-agents.sh                      # depois: login do claude e do codex
sudo -u dev ./scripts/09-clonar-escopo.sh /srv/dev/state/escopo-auditoria.tsv
/srv/dev/bin/health.sh
```

No painel do Tailscale, desative a expiração de chave do nó `stack` novo.

## Backup

`stack-backup.timer` roda `/usr/local/lib/stack-vps/14-backup.sh` todo dia às 03:00 de Brasília:
restic no bucket R2 `stack-vps-backup`, retenção 7 diários / 4 semanais / 6 mensais, verificação
de 5% dos dados aos domingos. O `health.sh` acusa se o último backup tiver mais de 36h.
````

Na seção "Árvore" do mesmo arquivo, nada muda. Na seção "Regras que valem para os agentes", acrescentar:

```markdown
- Docker publica porta só em `127.0.0.1` ou no IP da tailnet (`-p 127.0.0.1:3000:3000`): porta publicada ignora o UFW.
```

- [ ] **Step 4: `docs/CLAUDE.md` e `docs/AGENTS.md`**

Na seção "## 2. Escopo e permissões" dos dois arquivos (são cópias), acrescentar ao fim da lista:

```markdown
- Docker publica porta só em `127.0.0.1` ou no IP da tailnet (`-p 127.0.0.1:3000:3000`).
  Porta publicada pelo Docker ignora o UFW e fica aberta na internet.
```

Conferir que continuam idênticos:

```bash
diff docs/CLAUDE.md docs/AGENTS.md && echo iguais
```

- [ ] **Step 5: Commit**

```bash
git add .env.example README.md docs/srv-dev-README.md docs/CLAUDE.md docs/AGENTS.md
git commit -m "docs: ordem completa de instalacao, recuperacao do zero e regra de porta do Docker"
```

---

## Fase 1 — laptop → GitHub

### Task 13: Levantamento e TSV de decisão

**Portão:** o Ricardo revisa e aprova `docs/migracao-laptop.tsv`.

**Files:**
- Create: `docs/migracao-laptop.tsv`

- [ ] **Step 1: Levantar as pastas no WSL**

Gravar como `$SCRATCH/levantamento.sh` e rodar no WSL:

```bash
#!/usr/bin/env bash
# caminho, git?, remoto, commits fora do remoto, arquivos sujos — uma linha por pasta candidata
DEV="/mnt/c/Users/resper/OneDrive/Área de Trabalho/DESENVOLVIMENTO"
{ for d in /home/resper/*/; do echo "wsl	${d%/}"; done
  for d in "$DEV"/*/ "$DEV"/*/*/; do echo "windows	${d%/}"; done; } |
while IFS=$'\t' read -r o d; do
  if git -C "$d" rev-parse --show-toplevel 2>/dev/null | grep -qxF "$d"; then
    r=$(git -C "$d" remote get-url origin 2>/dev/null || echo "-")
    u=$(git -C "$d" log --branches --not --remotes --oneline 2>/dev/null | wc -l)
    s=$(git -C "$d" status --porcelain 2>/dev/null | wc -l)
    printf '%s\t%s\tgit\t%s\t%s\t%s\n' "$o" "$d" "$r" "$u" "$s"
  elif [[ $(dirname "$d") == "$DEV" || $(dirname "$d") == /home/resper ]]; then
    printf '%s\t%s\tsem-git\t-\t-\t-\n' "$o" "$d"
  fi
done
```

```bash
wsl -e bash "$(wsl -e wslpath -a "$(cygpath -w "$SCRATCH/levantamento.sh")")" > "$SCRATCH/levantamento.tsv"
```

Esperado: algumas centenas de linhas; nenhuma mensagem de erro de permissão bloqueante.

- [ ] **Step 2: Montar `docs/migracao-laptop.tsv`**

Cruzar `$SCRATCH/levantamento.tsv` com as categorias do `CONSOLIDACAO-2026-09-16.md`:

- Pasta git com remoto e commits fora do remoto → `push`, `dono`/`repo` tirados da URL do remoto.
- Pasta git com remoto e 0 commits fora → não entra (já está no GitHub).
- Pasta sem remoto (git ou não) em categoria keeper → `criar`, dono pelo mapa do spec (bekaa-apps → `bekaa-trusted-advisors`; forense → `forense-io`; demais → `resper1965`), `repo` em minúsculas sem espaço nem acento.
- LIXO e "?" → `fica`.
- `arvore`: `agents` para agentes, `orm` para ORM/bekaa-apps, `infra` para infraestrutura, `apps` para o resto.
- Repo cujo `dono/repo` já está em `/srv/dev/state/escopo-auditoria.tsv` → mantém a ação, e anota na revisão que o clone já existe na VPS.

Cabeçalho: `origem	caminho	dono	repo	arvore	acao`.

- [ ] **Step 3: Apresentar ao Ricardo e esperar a aprovação**

Mostrar no chat um resumo por ação e por dono (contagens) e a lista completa de `criar` e de `fica`. Só seguir com aprovação explícita. Correções dele entram no TSV.

- [ ] **Step 4: Commit**

O TSV tem nomes de pasta e de repo, sem conteúdo de cliente.

```bash
git add docs/migracao-laptop.tsv
git commit -m "docs: decisao por pasta da migracao do laptop"
```

---

### Task 14: Envio do laptop

**Portão:** o Ricardo revisa a saída do `--simular`; `gh auth status` dele cobre os três donos.

- [ ] **Step 1: Ferramentas no WSL**

```bash
wsl -e bash -lc 'command -v gh gitleaks git; gitleaks version 2>/dev/null; gh auth status 2>&1 | head -5'
```

Faltando o `gitleaks`, instalar a 8.18.4 (tem o subcomando `detect` que o script usa):

```bash
wsl -e bash -lc 'mkdir -p ~/.local/bin && curl -fsSL https://github.com/gitleaks/gitleaks/releases/download/v8.18.4/gitleaks_8.18.4_linux_x64.tar.gz | tar -xz -C ~/.local/bin gitleaks && ~/.local/bin/gitleaks version'
```

Faltando o `gh`, o Ricardo roda no WSL `sudo apt install -y gh` e `gh auth login` (GitHub.com → HTTPS → navegador). O token precisa criar repositório em `resper1965`, `bekaa-trusted-advisors` e `forense-io`:

```bash
wsl -e bash -lc 'for o in bekaa-trusted-advisors forense-io; do gh api "orgs/$o/memberships/$(gh api user -q .login)" -q "\"$o: \" + .role"; done'
```

Esperado: `admin` ou `member` com permissão de criar repo nas duas.

- [ ] **Step 2: Simulação**

```bash
wsl -e bash -lc "cd \"$REPO_WSL\" && bash scripts/20-laptop-github.sh docs/migracao-laptop.tsv --simular"
```

Mostrar ao Ricardo o `docs/migracao-laptop.resultado.tsv`: cada `PENDENTE` com o motivo. Pendências de extensão em forense/propostas são o comportamento esperado (documento de cliente fica no laptop). Aprovação explícita antes do Step 3.

- [ ] **Step 3: Execução real**

```bash
wsl -e bash -lc "cd \"$REPO_WSL\" && bash scripts/20-laptop-github.sh docs/migracao-laptop.tsv"
```

Esperado: `OK: N | PENDENTE: M | SIMULA: 0`.

- [ ] **Step 4: Rodar de novo para provar que nada ficou para trás**

Mesmo comando do Step 3. Esperado: todo item `push` que deu OK some (0 commits à frente); os `criar` que deram OK viram `PENDENTE ... ja tem remoto: use push`; restam só as pendências já conhecidas.

- [ ] **Step 5: Acrescentar os repos novos ao escopo da VPS**

```bash
SSHV 'cat > /tmp/escopo-novos.tsv' < docs/migracao-laptop.escopo-novos.tsv
SSHV 'bash -s' <<'EOF'
cd /srv/dev/state && cp escopo-auditoria.tsv "escopo-auditoria.tsv.bak-$(date +%F)"
awk -F'\t' -v OFS='\t' 'NR==FNR { v[$1"/"$2]=1; d[$4]=1; next }
  !(($1"/"$2) in v) { if ($4 in d) $4=$1"--"$4; print; v[$1"/"$2]=1; d[$4]=1 }' \
  escopo-auditoria.tsv /tmp/escopo-novos.tsv > /tmp/acrescentar.tsv
cat /tmp/acrescentar.tsv >> escopo-auditoria.tsv
echo "acrescentados: $(wc -l < /tmp/acrescentar.tsv)"; rm /tmp/escopo-novos.tsv /tmp/acrescentar.tsv
EOF
```

(Repo já no escopo não duplica; pasta homônima de outro dono vira `dono--repo`, como no escopo atual.)

- [ ] **Step 6: Clonar na VPS e commitar o resultado**

```bash
SSHV 'bash /srv/dev/bin/09-clonar-escopo.sh /srv/dev/state/escopo-auditoria.tsv'
git add docs/migracao-laptop.resultado.tsv
git commit -m "docs: resultado do envio do laptop ao GitHub"
```

Esperado no `09`: `falhas: 0`. O `escopo-novos.tsv` não é commitado (já está no escopo da VPS):

```bash
echo 'docs/migracao-laptop.escopo-novos.tsv' >> .gitignore && git add .gitignore && git commit -m "chore: ignora o arquivo intermediario do escopo"
```

---

## Fase 2 — backup

### Task 15: R2, chaves e `.env`

**Portão:** o Ricardo cria o token R2, guarda as três chaves no gerenciador de senhas e confirma.

- [ ] **Step 1: Criar o bucket (com confirmação)**

Pedir confirmação ao Ricardo: "vou criar o bucket R2 `stack-vps-backup` na conta Cloudflare". Com o sim, usar a ferramenta `mcp__claude_ai_Cloudflare_Developer_Platform__r2_bucket_create` com `name: stack-vps-backup`. Conferir com `r2_bucket_get`.

- [ ] **Step 2: Ricardo cria o token R2**

Passo a passo para ele: painel da Cloudflare → **R2 Object Storage** → **Manage API tokens** → **Create Account API token** → Permissions **Object Read & Write** → **Apply to specific buckets only** → `stack-vps-backup` → TTL **Forever** → **Create**. Copiar **Access Key ID** e **Secret Access Key** direto para o gerenciador de senhas. Gerar no próprio gerenciador uma senha de 32+ caracteres para `RESTIC_PASSWORD`.

- [ ] **Step 3: Ricardo coloca as chaves no `.env` e corrige as duas falhas conhecidas**

Comando para ele colar no PowerShell (pede as três sem eco; remove a linha duplicada de `CLOUDFLARE_API_TOKEN` mantendo a última, que é a que vale hoje quando o arquivo é carregado; corrige o nome da chave do Featherless):

```powershell
ssh -t stack 'f=/srv/dev/secrets/.env; cp $f $f.bak-$(date +%F);
for k in R2_ACCESS_KEY_ID R2_SECRET_ACCESS_KEY RESTIC_PASSWORD; do read -rsp "$k: " v; echo; sed -i "/^$k=/d" $f; printf "%s=%s\n" "$k" "$v" >> $f; done;
last=$(grep "^CLOUDFLARE_API_TOKEN=" $f | tail -1); sed -i "/^CLOUDFLARE_API_TOKEN=/d" $f; echo "$last" >> $f;
sed -i "s/^FEARTHERLESS_API_KEY=/FEATHERLESS_API_KEY=/" $f; chmod 600 $f; grep -o "^[A-Z_0-9]*=" $f'
```

Esperado: a lista de nomes, sem duplicata, com as três chaves novas e `FEATHERLESS_API_KEY=`.

Antes, conferir se algo usa o nome antigo:

```bash
SSHV 'grep -rl FEARTHERLESS /srv/dev/repos /home/dev/.claude* /home/dev/.codex 2>/dev/null | head'
```

Se aparecer arquivo, ajustar o nome lá também (ou manter as duas chaves e registrar o motivo).

- [ ] **Step 4: Confirmação explícita**

Perguntar ao Ricardo: "as três chaves (`R2_ACCESS_KEY_ID`, `R2_SECRET_ACCESS_KEY`, `RESTIC_PASSWORD`) estão no gerenciador de senhas?" Sem o sim, a fase 2 não avança.

---

### Task 16: Primeiro backup, restore de teste e conferência dos clones

- [ ] **Step 1: Instalar os serviços na VPS atual**

```bash
SSHV 'sudo bash ~/stack-vps-wip/scripts/05-servicos.sh'
```

Esperado: `backup: <data> <hora> UTC ...` e `tmux-dev: active`. O cron do dev continua com uma única linha do `weekly-review.sh`:

```bash
SSHV 'crontab -l | grep -c weekly-review.sh'
```

Esperado: `1`.

- [ ] **Step 2: Primeiro backup**

```bash
SSHV 'sudo /usr/local/lib/stack-vps/14-backup.sh 2>&1 | tail -5; sudo -E bash -c ". /usr/local/lib/stack-vps/lib/restic-env.sh && restic snapshots --compact" '
```

Esperado: `backup ok: ...` e um snapshot listado com os seis caminhos.

- [ ] **Step 3: Restore de teste e comparação**

```bash
SSHV 'sudo rm -rf /tmp/teste-restore && sudo /usr/local/lib/stack-vps/15-restore.sh --destino /tmp/teste-restore &&
  for p in /srv/dev/state /srv/dev/secrets/.env /etc/cloudflared/credentials.json /home/dev/.codex; do
    sudo diff -rq --exclude=.last-backup "$p" "/tmp/teste-restore$p" >/dev/null && echo "igual: $p" || echo "DIFERENTE: $p"; done;
  sudo diff -rq --exclude=.credentials.json --exclude=plugins --exclude=node_modules /home/dev/.claude /tmp/teste-restore/home/dev/.claude >/dev/null && echo "igual: ~/.claude" || echo "DIFERENTE: ~/.claude";
  sudo du -sh /tmp/teste-restore/srv/dev/data; sudo rm -rf /tmp/teste-restore'
```

Esperado: todas as linhas `igual:` e o tamanho de `data` ≈ 207M (o conteúdo de `data/` é comparado só por tamanho, sem abrir). `~/.claude` pode diferir em arquivos que o Claude escreveu entre o backup e o diff (sessão ativa); nesse caso rodar o diff com `-r` sem `-q` e conferir que só mudaram arquivos de sessão/log.

- [ ] **Step 4: Conferir os 53 commits fora do `origin`**

```bash
SSHV 'for d in /srv/dev/repos/*/*/; do git -C "$d" fetch -q origin 2>/dev/null; u=$(git -C "$d" log --branches --not --remotes --oneline 2>/dev/null | wc -l); [ "$u" -gt 0 ] && echo "$d $u $(git -C "$d" branch --format="%(refname:short)" | tr "\n" " ")"; done'
```

Esperado: lista vazia (eram as `chore/inventario-*` já enviadas por URL). Para o que sobrar, enviar a branch:

```bash
D=/srv/dev/repos/apps/exemplo DONO=resper1965 REPO=exemplo BR=chore/inventario-2026-09-16   # valores da linha listada
SSHV "set -a; . /srv/dev/secrets/.env; set +a; git -C $D push -q \"https://x-access-token:\${GITHUB_TOKEN}@github.com/$DONO/$REPO.git\" $BR && git -C $D fetch -q origin"
```

e repetir o comando de conferência até a lista vazia. Branch `main`/`master` à frente do remoto não é enviada: listar para o Ricardo.

- [ ] **Step 5: Health**

```bash
SSHV '/srv/dev/bin/health.sh'
```

Esperado: tudo `ok`, incluindo `ultimo backup ha 0h`.

---

## Fase 3 — janela

### Task 17: Integrar na `main` e marcar a janela

**Portão:** o Ricardo aprova o PR e escolhe o dia (terça a sexta).

- [ ] **Step 1: Rodar a suíte inteira uma última vez**

```bash
TESTAR
```

Esperado: código 0.

- [ ] **Step 2: Enviar a branch e abrir o PR**

Com confirmação do Ricardo para o push:

```bash
git push -u origin feat/migracao-vps
gh pr create --base main --title "feat: migracao e instalacao definitiva da VPS" --body-file - <<'EOF'
Implementa o spec docs/superpowers/specs/2026-10-05-migracao-vps-design.md.

- Tailscale como acesso principal (01b), tunnel de reserva (06), UFW so na tailnet (07)
- Backup e restore restic no R2 (14, 15) com timer diario instalado pelo 05
- Envio do laptop ao GitHub (20) e decisao por pasta em docs/migracao-laptop.tsv
- Testes: bash tests/run.sh (shellcheck + stubs)
EOF
```

- [ ] **Step 3: Ricardo faz o merge**

Depois do merge, conferir:

```bash
git fetch origin && git log --oneline -1 origin/main
```

- [ ] **Step 4: Ricardo escolhe a data da janela**

Terça a sexta, 2 horas. Registrar no chat.

---

### Task 18: Janela — reinstalação e reconstrução

**Portão a cada passo marcado (R):** ação do Ricardo.

- [ ] **Step 1: Backup final**

```bash
SSHV 'sudo /usr/local/lib/stack-vps/14-backup.sh | tail -1; sudo -E bash -c ". /usr/local/lib/stack-vps/lib/restic-env.sh && restic snapshots --latest 1 --compact"'
```

Esperado: snapshot com horário dos últimos minutos. Anotar o `CLOUDFLARE_ACCOUNT_ID` (não é segredo) para o Step 7:

```bash
SSHV 'grep ^CLOUDFLARE_ACCOUNT_ID= /srv/dev/secrets/.env | cut -d= -f2'
```

- [ ] **Step 2 (R): Preparar as contas**

O Ricardo, nesta ordem:
1. Gera uma auth key nova no Tailscale (como na Task 5).
2. No hPanel: **Snapshot** → **Create snapshot**. Esperar concluir.
3. No painel do Tailscale: remove o nó `stack` (menu **…** → **Remove**).
4. No hPanel: **OS & Panel** → **Operating System** → Ubuntu 24.04 (imagem com Docker, a mesma de hoje) → reinstalar, cadastrando a chave pública `id_ed25519_stackvps.pub` para o root.

A partir do item 3 a VPS está inacessível pela tailnet até o Step 4.

- [ ] **Step 3: Entrar como root pelo IP**

```bash
ssh-keygen -R 148.230.77.242
/c/Windows/System32/OpenSSH/ssh.exe -o StrictHostKeyChecking=accept-new -i ~/.ssh/id_ed25519_stackvps root@148.230.77.242 'lsb_release -ds; command -v docker'
```

Esperado: `Ubuntu 24.04.x LTS` e o caminho do docker.

- [ ] **Step 4 (R): Baseline com Tailscale**

O Ricardo roda no PowerShell (a auth key é pedida sem eco):

```powershell
$pub = Get-Content $env:USERPROFILE\.ssh\id_ed25519_stackvps.pub
ssh -t -i $env:USERPROFILE\.ssh\id_ed25519_stackvps root@148.230.77.242 "git clone -q https://github.com/resper1965/stack-vps /tmp/stack-vps && cd /tmp/stack-vps && read -rsp 'auth key: ' k && echo && TS_AUTHKEY=`$k ./scripts/01-baseline.sh '$pub'"
```

Esperado: `tailscale: 100.x.y.z ...` e `baseline ok`. Em seguida o Ricardo desativa a expiração de chave do nó `stack` novo no painel.

Validar:

```bash
ssh-keygen -R stack 2>/dev/null; VPS_HOST=dev@stack
/c/Windows/System32/OpenSSH/ssh.exe -o StrictHostKeyChecking=accept-new -i ~/.ssh/id_ed25519_stackvps dev@stack 'hostname; sudo -n true && echo sudo-ok'
```

Esperado: `stack` e `sudo-ok`. Daqui em diante tudo por `SSHV`.

- [ ] **Step 5: Layout e mover o clone**

```bash
SSHV 'sudo /tmp/stack-vps/scripts/02-layout.sh >/dev/null && sudo mv /tmp/stack-vps /srv/dev/repos/infra/stack-vps && sudo chown -R dev:dev /srv/dev/repos/infra/stack-vps && ls /srv/dev'
```

Esperado: `bin data repos secrets skills state`.

- [ ] **Step 6: Ferramentas e serviços**

```bash
SSHV 'cd /srv/dev/repos/infra/stack-vps && sudo ./scripts/03-tooling.sh | tail -1 && sudo ./scripts/05-servicos.sh | tail -2'
```

Esperado: versões do node e do docker; `backup: ...` e `tmux-dev: active`.

- [ ] **Step 7 (R): Restore**

O Ricardo roda no PowerShell, com o `CLOUDFLARE_ACCOUNT_ID` anotado no Step 1 no lugar de `ID_DA_CONTA`:

```powershell
ssh -t stack 'export CLOUDFLARE_ACCOUNT_ID=ID_DA_CONTA; for k in R2_ACCESS_KEY_ID R2_SECRET_ACCESS_KEY RESTIC_PASSWORD; do read -rsp "$k: " v; echo; export "$k=$v"; done; sudo --preserve-env=CLOUDFLARE_ACCOUNT_ID,R2_ACCESS_KEY_ID,R2_SECRET_ACCESS_KEY,RESTIC_PASSWORD /usr/local/lib/stack-vps/15-restore.sh'
```

Esperado: `restore ok em /`. Conferir:

```bash
SSHV 'grep -o "^[A-Z_0-9]*=" /srv/dev/secrets/.env | wc -l; stat -c "%a %U" /srv/dev/secrets/.env; sudo stat -c "%a %U" /etc/cloudflared/credentials.json; ls /srv/dev/state | head -3'
```

Esperado: `10` chaves; `600 dev`; `600 root`; arquivos do `state`.

- [ ] **Step 8: Tunnel de reserva e firewall**

```bash
SSHV 'cd /srv/dev/repos/infra/stack-vps && sudo ./scripts/06-tunnel.sh resper@bekaa.eu | tail -3'
wsl -e bash -lc 'timeout 30 ssh stack-cf hostname'
SSHV 'cd /srv/dev/repos/infra/stack-vps && sudo ./scripts/07-firewall.sh | head -6'
/c/Windows/System32/OpenSSH/ssh.exe -o BatchMode=yes -o ConnectTimeout=8 -i ~/.ssh/id_ed25519_stackvps dev@148.230.77.242 hostname; echo "rc=$?"
```

Esperado: `cloudflared: ativo`; `stack`; regra `22/tcp on tailscale0`; `rc=255` com timeout.

O e-mail da política de Access é o mesmo usado em 2026-09 (`resper@bekaa.eu`); confirmar com o Ricardo antes de rodar.

- [ ] **Step 9 (R): Agentes**

```bash
SSHV 'cd /srv/dev/repos/infra/stack-vps && bash ./scripts/04-agents.sh | tail -3'
```

Esperado: versões do claude e do codex. O Ricardo então faz, em `ssh stack`, `claude` (login pela URL) e `codex login`.

- [ ] **Step 10: Clones e health**

```bash
SSHV 'bash /srv/dev/bin/09-clonar-escopo.sh /srv/dev/state/escopo-auditoria.tsv; /srv/dev/bin/health.sh'
```

Esperado: `falhas: 0`; health todo `ok` (o backup aparece com a idade do snapshot restaurado, < 36h).

**Desfazer:** falha em qualquer step que não se resolva em 30 minutos → o Ricardo restaura o snapshot no hPanel e remove o nó novo do Tailscale; a VPS volta ao estado do Step 1 (com a 22 já fechada na tailnet antiga — o nó antigo foi removido, então ele gera nova auth key e roda a Task 5 de novo).

---

## Fase 4 — fechamento

### Task 19: Critérios de aceite

- [ ] **Step 1: IP público fechado**

```powershell
Test-NetConnection 148.230.77.242 -Port 22 -InformationLevel Quiet -WarningAction SilentlyContinue
```

Esperado: `False`.

- [ ] **Step 2: Dois caminhos e VS Code**

```bash
SSHV hostname
wsl -e bash -lc 'timeout 30 ssh stack-cf hostname'
```

Esperado: `stack` nos dois. O Ricardo abre o VS Code → Remote-SSH → `stack` e confirma que abre `/srv/dev`.

- [ ] **Step 3: Nó sem expiração**

O Ricardo confere no painel do Tailscale que o nó `stack` mostra **Expiry disabled**.

- [ ] **Step 4: Rotina semanal com os repos do laptop**

```bash
SSHV '/srv/dev/bin/weekly-review.sh --now; tail -3 /srv/dev/state/weekly.log; python3 -c "import json;d=json.load(open(\"/srv/dev/state/dashboard.json\"));print(len(d.get(\"projetos\",d)))"'
```

Esperado: relatório do dia em `/srv/dev/state/review-<data>.md` e contagem de projetos maior que a de 28/09 (inclui os vindos do laptop).

- [ ] **Step 5: Backup automático do dia seguinte**

No dia seguinte à janela:

```bash
SSHV 'systemctl list-timers stack-backup.timer --no-legend; sudo journalctl -u stack-backup --since yesterday --no-pager | tail -3; /srv/dev/bin/health.sh | grep -A1 backup'
```

Esperado: `backup ok: ...` no journal com horário ≈ 06:00 UTC e `ok ultimo backup ha <24h`.

- [ ] **Step 6: Descartar o snapshot da Hostinger**

Sete dias depois da janela, com o Step 5 verde em todos os dias (`journalctl -u stack-backup --since "-7 days" | grep -c "backup ok"` = 7), o Ricardo apaga o snapshot no hPanel.

- [ ] **Step 7: Encerrar a consolidação**

Atualizar `CONSOLIDACAO-2026-09-16.md` marcando como concluídos o push dos repos, o restic e "Claude Code / Codex no VPS"; o arquivo segue fora do Git, como hoje, salvo decisão contrária do Ricardo.
