# Lugar de trabalho — plano de implementação

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or
> superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** transformar a VPS `stack` num lugar único de trabalho (OpenCode na tailnet, com fallback), com o PMO
como controle do ciclo de vida dos projetos espelhado no Linear — etapas 0 a 3 do spec, detalhadas; etapas 4 a 6
como roteiro, cada uma com plano próprio depois.

**Architecture:** reaproveita a base (scripts numerados idempotentes, PMO em Python stdlib, testes bash com stubs e
`unittest`). OpenCode em `127.0.0.1:4096` e PMO num socket Unix, publicados por `tailscale serve`; fallback por
SSH no Cloudflare Tunnel, rota de emergência liga/desliga e API da Hostinger. Linear recebe só o estágio de cada
projeto, em sentido único, por um timer do PMO.

**Tech Stack:** Bash (shellcheck `-S warning`), Python 3 stdlib (`unittest`, `urllib`, `http.server`,
`socketserver`), systemd, Tailscale (`tailscale serve`), cloudflared, OpenCode 2.x, Node 24 (`node:test`), Linear
GraphQL API, API da Hostinger.

**Spec:** `docs/superpowers/specs/2026-10-18-lugar-de-trabalho-design.md`

## Global Constraints

- Uma branch por etapa (`chore/etapa0-sincronizar`, `docs/etapa1-spikes`, `feat/etapa2-lugar-de-trabalho`,
  `feat/etapa3-pmo-linear`), PR para `main`; nunca push direto em `main`. Branch nova **sem upstream** em
  `origin/main`.
- Nada vai à VPS (deploy, `systemctl`, `sudo ./NN-*.sh`, chamada que altera estado em API) sem aprovação explícita
  do Ricardo, pedida com o comando exato e o efeito.
- Antes de cada deploy de etapa: snapshot da `stack` pela API da Hostinger (Task 14), com aprovação.
- Commits em português, conventional (`feat:`, `fix:`, `docs:`, `chore:`, `test:`); código em inglês **ou** no
  padrão já usado no arquivo (o PMO e os scripts usam nomes em português — siga o arquivo).
- Script novo: idempotente, `set -euo pipefail`, passa `shellcheck -x -S warning`, teste em `tests/test-NN-*.sh`
  com `tests/lib.sh` (stubs no PATH, `STACK_TESTE=1`).
- PMO: só biblioteca padrão do Python; arquivos de estado em `/var/lib/pmo` (dono `pmo`, 0700); gravação atômica
  (`tmp` + `os.replace`).
- Segredo nunca em argumento de linha de comando, log, `painel.json` ou Git; passa por arquivo 0600/0640 ou stdin
  (padrão do `alertar.sh`).
- Testes rodam **na VPS ou no WSL** (`bash tests/run.sh`); no Windows o `run.sh` recusa (Task 7).
- Projeto existente nunca recebe bootstrap; repositório de cliente (`nessenergy/alupdatalake`,
  `nessenergy/sitealupar`) nunca é excluído.

## Review Focus

1. **Agente da VPS pedindo ação ao PMO pela tailnet** (`curl https://stack.<tailnet>.ts.net:8443/acao` de dentro
   da `stack`): deve ser recusado. Teste em Task 8 (`test_post_sem_login_tailscale_recusado`).
2. **Duas corridas do espelho do Linear ao mesmo tempo** (timer + execução manual): não pode criar projeto em
   dobro. Teste em Task 19 (`test_segunda_corrida_com_trava_nao_faz_nada`).
3. **Web de emergência esquecida ligada:** deve continuar aparecendo como falha no `health.sh` até ser desligada.
   Teste em Task 12.
4. **OpenCode sem senha** (arquivo ausente ou vazio): o script não pode subir a web. Teste em Task 9.
5. **`health.txt` ausente, vazio ou velho:** o painel continua de pé e mostra "sem dado" com a data. Teste em
   Task 13.

## Mapa de arquivos

| Arquivo | Responsabilidade | Task |
|---|---|---|
| `tests/run.sh` | recusa fora do Linux | 7 |
| `.gitignore` | `__pycache__/` | 7 |
| `pmo/servidor.py` | socket Unix, hosts permitidos, login Tailscale no POST, bloco de saúde | 8, 13 |
| `systemd/pmo-servidor.service` | `RuntimeDirectory=pmo`, socket | 8 |
| `scripts/34-pmo.sh` | `dev` no grupo `pmo`, recusa `agente` no grupo; token e timer do Linear | 8, 19 |
| `scripts/36-opencode.sh` + `opencode/opencode-web.service` | OpenCode fixado, web só em `127.0.0.1` com senha | 9 |
| `scripts/37-tailscale-serve.sh` | publica OpenCode (443) e PMO (8443) na tailnet | 10 |
| `docs/ssh-config.md` | fallback camada 1 | 10 |
| `bin/stack-emergencia` + `scripts/06-tunnel.sh` | fallback camada 2 | 11, 12 |
| `bin/health.sh`, `scripts/vigia-health.sh` | checagens novas; `health.txt` para o painel | 12, 13 |
| `pmo/painel.py`, `pmo/web/app.js` | `ler_saude`, `montar`, bloco Saúde, congelar | 13, 17, 18 |
| `bin/hostinger.sh` | snapshot, métricas, reinício, recuperação | 14 |
| `opencode/plugin/aviso.js` | aviso de agente concluído | 15 |
| remoções (ver Task 16) | OpenRig, sysbox, rede de containers, runners, Continue | 16 |
| `pmo/regras.py` | estágio `congelado` | 17 |
| `pmo/linear.py`, `systemd/pmo-linear.{service,timer}` | espelho PMO → Linear | 18, 19 |
| `docs/spikes/2026-10-*.md` | respostas dos spikes | 1–6 |

---

## Etapa 0 — Sincronizar

### Task 0: Alinhar clones e registrar o que está ativo na VPS

**Files:**
- Modify: `docs/development-hub-continuity.md` (seção nova "Estado em AAAA-MM-DD")

Somente leitura na VPS. Nada é instalado, reiniciado ou apagado.

- [ ] **Step 1:** no laptop, `git switch main && git pull --ff-only`. Esperado: `main` igual a `origin/main`
  (`git status -sb` sem `behind`).
- [ ] **Step 2:** na VPS, como `dev`, para cada clone (`/opt/stack-vps`, `/srv/dev/projetos/STACK-VPS`):
  `git -C <clone> fetch -q && git -C <clone> status -sb && git -C <clone> log -1 --oneline`. Anote quantos
  commits atrás de `origin/main` e se há mudança local.
- [ ] **Step 3:** compare o instalado com a fonte: `diff -rq /opt/pmo /opt/stack-vps/pmo` e
  `systemctl cat pmo-coleta.service | grep -c ExecStartPre`. Esperado: saber se os PRs #9, #11 e #12 estão de fato
  instalados (1 = coletor de sessões ativo).
- [ ] **Step 4:** liste o que a Task 16 vai remover e ainda roda:
  `systemctl is-active stack-rede-containers; docker ps --format '{{.Names}}' | grep -i runner; dpkg -l sysbox-ce`
  e, como `agente`, `systemctl --user is-active opencode-web; ls ~/.continue 2>/dev/null`.
- [ ] **Step 5:** registre os resultados (sem segredo, sem URL de pareamento) na seção nova do
  `docs/development-hub-continuity.md`, com a data.
- [ ] **Step 6:** commit na branch `chore/etapa0-sincronizar`:
  `git commit -m "docs: estado da VPS antes do redesenho"`; PR.

---

## Etapa 1 — Spikes (respostas, não código)

Cada spike grava `docs/spikes/2026-10-<dd>-<tema>.md` com uma tabela **Pergunta | Resposta | Evidência (comando
ou link)** e uma linha **Decisão**. Código de spike é descartável e não entra em nenhuma branch de entrega. Tudo na
branch `docs/etapa1-spikes`, um commit por spike (`docs: spike <tema>`). Spike que altera algo fora da VPS (criar
conta, gravar em API) pede aprovação antes.

### Task 1: Spike 9router

- [ ] Instale numa pasta descartável, como `agente`, a versão estável atual (`npx 9router@<versão>` ou clone do
  `decolua/9router`), só em `127.0.0.1`.
- [ ] Responda: (1) duas contas Claude (bekaa e ionic) convivem e podem ser escolhidas por requisição?
  (2) ChatGPT e Antigravity funcionam por OAuth? (3) existe senha padrão no código quando a variável não está
  definida? (cite arquivo e linha) (4) onde e com que permissão ficam os tokens OAuth? (5) o que os termos de
  Anthropic, OpenAI e Google dizem sobre uso de assinatura via gateway de terceiros (link)?
- [ ] **Decisão:** "gateway único" se 1, 2 e 4 forem sim/seguros; senão "duas faixas" (assinaturas nos CLIs,
  chaves no 9router). Registre a variável de senha e o comando exato de subir em modo serviço.

### Task 2: Spike Kamal

- [ ] Responda: versão estável atual; imagem Docker oficial e o comando para rodá-lo sem Ruby
  (`docker run ... ghcr.io/basecamp/kamal:<versão>`); como o kamal-proxy emite TLS (Let's Encrypt) e o que fazer
  em servidor de cliente **sem DNS público** (certificado próprio ou TLS desligado atrás de proxy do cliente);
  `kamal rollback` funciona com acessório Postgres?
- [ ] **Decisão:** comando-padrão de deploy e o modelo de `config/deploy.yml` para o template `sistema` (etapa 6).

### Task 3: Spike API da Hostinger

- [ ] Com o token do `admin.env`, **só leitura**: liste a VM e as métricas. Documente (sem executar) os endpoints
  de snapshot, restauração de snapshot, reinício e modo de recuperação, e quantos snapshots a VPS guarda.
- [ ] **Decisão:** comandos de `bin/hostinger.sh` (Task 14) com método, caminho e campo de resposta de cada um.

### Task 4: Spike `tailscale serve`

- [ ] Responda: (1) `tailscale serve` aceita alvo **socket Unix** (`unix:/run/pmo/pmo.sock`)? Sintaxe exata para
  as portas 443 e 8443, em segundo plano e persistente após reboot. (2) Quais cabeçalhos de identidade chegam ao
  serviço (`Tailscale-User-Login`, …) e se o `serve` **sobrescreve** um cabeçalho com esse nome enviado pelo
  cliente. (3) Requisição vinda da própria `stack` (nó com tag ou não) chega com `Tailscale-User-Login`?
- [ ] **Decisão:** se (1) for não ou (2) não for garantido, **pare** e volte ao spec: a Task 8 depende disso.

### Task 5: Spike OpenCode

- [ ] Responda: flags exatas para a web em `127.0.0.1:4096` (`opencode web --hostname … --port …`); variável da
  senha (`OPENCODE_SERVER_PASSWORD` ou outra); como fixar a versão na instalação; nome do evento de plugin quando a
  sessão fica ociosa (`session.idle`?) e os campos que ele traz (id, título, diretório); pasta de plugins
  (`~/.config/opencode/plugin/`) e formato do módulo.
- [ ] **Decisão:** valores usados nas Tasks 9 e 15.

### Task 6: Spike Linear

- [ ] Com a chave pessoal de resper@bekaa.eu, **só leitura**: o workspace aceita status de projeto
  personalizados? Liste `projectStatuses { nodes { id name type } }`. Qual time (`teams { nodes { id key } }`)
  recebe os projetos? Quais limites do plano atual afetam ~100 projetos? Formato do cabeçalho de autenticação.
- [ ] **Decisão:** criar os status personalizados (com aprovação, à mão no Linear) ou usar o mapeamento padrão;
  `LINEAR_TEAM_KEY` a usar.

---

## Etapa 2 — Lugar de trabalho

Branch `feat/etapa2-lugar-de-trabalho`.

### Task 7: Testes só no Linux e higiene

**Files:**
- Modify: `tests/run.sh:1-5`, `.gitignore`
- Test: `tests/test-run.sh`

- [ ] **Step 1:** teste: `tests/test-run.sh` roda `run.sh` com `uname` stubado para `MINGW64_NT` e afirma rc 2 e a
  mensagem `rode na VPS ou no WSL`.
- [ ] **Step 2:** rode `bash tests/test-run.sh`. Esperado: FALHA.
- [ ] **Step 3:** no topo de `tests/run.sh`: `[[ $(uname -s) == Linux ]] || { echo "rode na VPS ou no WSL"; exit 2; }`.
  Acrescente `__pycache__/` ao `.gitignore`.
- [ ] **Step 4:** `bash tests/test-run.sh` passa; `bash tests/run.sh` (WSL) passa inteiro.
- [ ] **Step 5:** `git commit -m "test: run.sh recusa fora do Linux; ignora __pycache__"`.

### Task 8: PMO num socket Unix, só com login da tailnet para agir

**Files:**
- Modify: `pmo/servidor.py` (`criar`, `_host_ok`, `do_POST`, `main`), `systemd/pmo-servidor.service`,
  `scripts/34-pmo.sh`
- Test: `pmo/tests/test_servidor.py`

**Interfaces:**
- Produces: `criar(web, painel, fila, ajustes, *, socket=None, host=None, porta=None, hosts=(), logins=(),
  ips_proprios=(), classes=..., saude=None) -> socketserver.BaseServer` — com `socket` cria servidor HTTP em `AF_UNIX` (0660); sem
  `socket`, TCP como hoje (testes e compatibilidade).
- CLI: `python3 -m pmo.servidor --socket /run/pmo/pmo.sock --hosts stack.<tailnet>.ts.net:8443,localhost:8080
  --logins resper@bekaa.eu --ips-proprios 100.76.167.6,fd7a:...` (os três nomeados são obrigatórios com `--socket`).

Guarda contra o agente (final-review C1): de dentro da VPS o agente alcança a URL da tailnet, o `serve` resolve o
próprio nó e injeta `Tailscale-User-Login` do dono. Em modo socket, todo POST também exige `X-Forwarded-For`
(anexado pelo `serve`); vale o ÚLTIMO elemento, e o pedido é recusado (403, nada na fila) se o cabeçalho faltar ou
esse IP estiver em `ips_proprios` (o `34-pmo.sh` grava os IPs do nó em `PMO_IPS_PROPRIOS`). Alternativa de ACL:
marcar o nó com tag. Portão de verificação no "Deploy da etapa 2".

Regras: GET exige `Host` em `hosts`. POST exige `Host` em `hosts` **e** `Tailscale-User-Login` em `logins` (além
de `X-PMO`, JSON e `Origin` que já existem). No socket, o teste de IP local (`bloquear_local`) sai: quem não está no
grupo `pmo` não conecta. Pelo fallback SSH (camada 1) não há login Tailscale: o painel fica **só leitura**, de
propósito.

- [ ] **Step 1:** testes novos em `test_servidor.py`, com um auxiliar que conecta por socket Unix
  (`http.client.HTTPConnection` com `sock` já conectado):
  - `test_socket_criado_0660` — `stat.S_IMODE(os.stat(sock).st_mode) == 0o660`.
  - `test_get_host_da_lista_200` / `test_get_host_fora_da_lista_403`.
  - `test_post_com_login_permitido_202` — `Tailscale-User-Login: resper@bekaa.eu` → 202 e arquivo na fila.
  - `test_post_sem_login_tailscale_recusado` — sem o cabeçalho → 403, fila vazia (**Review Focus 1**).
  - `test_post_login_fora_da_lista_recusado` → 403.
  - Os testes antigos de CSRF e DNS rebinding continuam passando no modo TCP.
- [ ] **Step 2:** `python3 -m unittest pmo.tests.test_servidor -v`. Esperado: os novos falham.
- [ ] **Step 3:** implemente. Servidor Unix: `class _UnixHTTP(socketserver.ThreadingMixIn,
  socketserver.UnixStreamServer)` com `daemon_threads = True`; remova o socket antigo antes do `bind`;
  `os.chmod(sock, 0o660)` depois. `client_address` em socket Unix é string vazia: nada pode indexá-lo.
- [ ] **Step 4:** testes passam (`python3 -m unittest discover -s pmo/tests -t .`).
- [ ] **Step 5:** `systemd/pmo-servidor.service`: `Group=pmo`, `RuntimeDirectory=pmo`, `RuntimeDirectoryMode=0750`,
  `ExecStart=… -m pmo.servidor --socket /run/pmo/pmo.sock --hosts ${PMO_HOSTS} --logins ${PMO_LOGINS}` com
  `EnvironmentFile=/etc/pmo/servidor.env`. `34-pmo.sh` grava `/etc/pmo/servidor.env` (`PMO_HOSTS`, `PMO_LOGINS` do
  `admin.env`), `usermod -aG pmo dev` e **falha** se `id -nG agente` contiver `pmo`. Atualize `tests/` do 34 se
  existir; senão, `bash -n` e shellcheck.
- [ ] **Step 6:** `git commit -m "feat: PMO em socket Unix; ação só com login da tailnet"`.

### Task 9: OpenCode provisionado pelo repositório

**Files:**
- Create: `scripts/36-opencode.sh`, `opencode/opencode-web.service`
- Test: `tests/test-36-opencode.sh`

**Interfaces:**
- Consumes: spike Task 5 (flags, variável da senha, versão).
- Produces: unidade de usuário `opencode-web.service` do `agente`, escutando só `127.0.0.1:4096`; senha em
  `~/.config/opencode/web.env` (0600, `OPENCODE_SERVER_PASSWORD=`), nunca gerada nem impressa pelo script.

Roda como `agente`: `sudo -u agente -H bash -c 'cd ~ && /opt/stack-vps/scripts/36-opencode.sh'`. Instala a versão
fixada em `OPENCODE_VERSAO` (topo do script), copia a unidade, `systemctl --user daemon-reload`,
`enable --now`. Também instala o plugin da Task 15 quando ele existir (`opencode/plugin/*.js` →
`~/.config/opencode/plugin/`).

- [ ] **Step 1:** testes (stubs de `curl`, `systemctl`, `opencode`):
  - sem `web.env` → rc 1, mensagem `crie ~/.config/opencode/web.env`, `systemctl` não chamado (**Review Focus 4**);
  - `web.env` vazio ou sem `OPENCODE_SERVER_PASSWORD=` não vazio → rc 1;
  - `web.env` com permissão diferente de 0600 → rc 1;
  - caso válido: unidade instalada contém `127.0.0.1` e `4096`, e não contém `0.0.0.0`; `enable --now opencode-web`
    no log; a senha não aparece na saída nem no `STUB_LOG`.
- [ ] **Step 2:** rode; esperado FALHA.
- [ ] **Step 3:** implemente o script e a unidade.
- [ ] **Step 4:** testes passam; shellcheck limpo.
- [ ] **Step 5:** README: linha do 36 na tabela "Scripts de trabalho". `git commit -m "feat: OpenCode web
  provisionado (127.0.0.1, senha obrigatória)"`.

### Task 10: Publicar na tailnet e fallback por SSH (camadas 0 e 1)

**Files:**
- Create: `scripts/37-tailscale-serve.sh`
- Modify: `docs/ssh-config.md`
- Test: `tests/test-37-tailscale-serve.sh`

**Interfaces:**
- Consumes: spike Task 4 (sintaxe); socket da Task 8; porta da Task 9.

Root. Publica `https:443 → http://127.0.0.1:4096` e `https:8443 → unix:/run/pmo/pmo.sock`, em segundo plano e
persistente. Idempotente: reaplicar não duplica.

- [ ] **Step 1:** teste com `tailscale` stubado: os dois comandos `serve` com os alvos exatos no `STUB_LOG`; rodar
  duas vezes não acrescenta terceiro alvo; sem `tailscaled` ativo → rc 1 com mensagem.
- [ ] **Step 2:** rode; FALHA.
- [ ] **Step 3:** implemente.
- [ ] **Step 4:** passa.
- [ ] **Step 5:** `docs/ssh-config.md`: no `Host stack-cf`, `LocalForward 4096 127.0.0.1:4096` e
  `LocalForward 8080 /run/pmo/pmo.sock`, com o aviso "PMO fica só leitura por aqui". Remova o `LocalForward 4096`
  do `Host stack` (a tailnet serve direto).
- [ ] **Step 6:** `git commit -m "feat: OpenCode e PMO na tailnet por tailscale serve; fallback por SSH"`.

### Task 11: Rota de emergência no tunnel (preparação no 06)

**Files:**
- Modify: `scripts/06-tunnel.sh`
- Test: `tests/test-06-tunnel.sh`

O 06 passa a criar, sempre, o DNS `emergencia.esper.ws` e a aplicação de Access dela (`session_duration: "1h"`,
política `so-o-dono` igual à do SSH). **Não** põe a rota no `ingress`: sem a rota, o host responde 404. Rodar o 06
de novo reescreve o `config.yml` — se a emergência estava ligada, ela desliga (lado seguro), e o 06 avisa isso.

- [ ] **Step 1:** teste: com `curl` stubado para tunnel existente e credencial presente, afirma POST de app de
  Access com `emergencia.esper.ws` e `"1h"`; `config.yml` gerado **sem** `emergencia.esper.ws`.
- [ ] **Step 2–4:** FALHA → implemente → passa.
- [ ] **Step 5:** `git commit -m "feat: tunnel prepara host de emergência (sem rota)"`.

### Task 12: `stack-emergencia on|off|status` e checagens no health

**Files:**
- Create: `bin/stack-emergencia`
- Modify: `bin/health.sh`, `scripts/05-servicos.sh` (instala o comando em `/usr/local/bin`)
- Test: `tests/test-stack-emergencia.sh`, `tests/test-health.sh` (novo)

**Interfaces:**
- Produces: `stack-emergencia on|off|status` (root). `on` insere antes de `- service: http_status:404`:
  `- hostname: emergencia.esper.ws` / `service: http://localhost:4096`; `off` remove; ambos reiniciam o
  `cloudflared` e chamam `alertar.sh "stack: emergência LIGADA|desligada" "<quem> em <data>"`. `status` imprime
  `ligada` ou `desligada`. Diretório do cloudflared em `STACK_CF_DIR` (padrão `/etc/cloudflared`).

- [ ] **Step 1:** testes de `stack-emergencia` (config temporária, stubs `systemctl` e alertar via
  `EMERGENCIA_ALERTAR`): `on` insere a rota antes do catch-all; `on` duas vezes não duplica; `off` remove;
  `status` reflete; alerta chamado com `LIGADA` e com `desligada`; argumento inválido → rc 2.
- [ ] **Step 2:** testes de `health.sh` (stubs `systemctl`, `tailscale`, `curl`, `docker`, `df`; arquivos em
  `HEALTH_*` sobrescrevíveis):
  - emergência ligada → linha `FALHA web de emergência ligada` (**Review Focus 3**);
  - `curl` do OpenCode com 200 ou 401 → `ok    opencode web`; outro → `FALHA opencode web`;
  - `curl --unix-socket /run/pmo/pmo.sock` com 200 → `ok    painel do PMO`; falha → `FALHA painel do PMO`.
- [ ] **Step 3:** FALHA → implemente (no `health.sh`, seção `acesso`) → passa.
- [ ] **Step 4:** `git commit -m "feat: stack-emergencia liga/desliga a web de emergência com alerta"`.

### Task 13: Bloco Saúde no PMO

**Files:**
- Modify: `scripts/vigia-health.sh` (grava a saída), `pmo/painel.py`, `pmo/servidor.py`, `pmo/web/app.js`,
  `pmo/web/index.html`
- Test: `tests/test-vigia-health.sh`, `pmo/tests/test_painel.py`, `pmo/tests/test_servidor.py`

**Interfaces:**
- Produces: `vigia-health.sh` grava a saída do `health.sh` em `${VIGIA_SAIDA:-/var/lib/stack-vps/health.txt}`
  (atômico, 0644) a cada corrida.
- Produces: `ler_saude(caminho: str, agora: datetime) -> dict` em `pmo/painel.py`:
  `{"gerado_em": iso|None, "velho": bool, "itens": [{"secao": str, "estado": "ok"|"falha"|"pend", "texto": str}]}`;
  `velho` quando o arquivo tem mais de 90 min (1,5× o período do timer horário do vigia); ausente/ilegível → `{"gerado_em": None, "velho": True, "itens": []}`.
- `servidor.ler_painel` acrescenta `dados["saude"] = ler_saude(saude, agora)` a cada GET (tempo real, sem esperar a
  coleta diária).

- [ ] **Step 1:** testes: `test_vigia_grava_health_txt`; `test_ler_saude_agrupa_por_secao` (entrada com
  `acesso`/`  ok    tailscale…`/`  FALHA cloudflared parado`/`  pend  backup…`); `test_ler_saude_ausente`,
  `test_ler_saude_vazio`, `test_ler_saude_velho` (mtime − 31 min) (**Review Focus 5**);
  `test_painel_json_tem_saude`.
- [ ] **Step 2–4:** FALHA → implemente → passa.
- [ ] **Step 5:** `app.js`: bloco "Saúde" no topo, uma linha por item com o estado; mostra "atualizado há N min" e
  "sem dado" quando `gerado_em` é nulo; dados externos sempre por `textContent` (`el(...)` já faz). Atalhos:
  "Abrir OpenCode" (`https://stack.<tailnet>.ts.net/`, lido de `painel.json` → `atalhos.opencode`, configurado por
  `PMO_ATALHO_OPENCODE` no `servidor.env`).
- [ ] **Step 6:** `git commit -m "feat: bloco de saúde da VPS no PMO"`.

### Task 14: `bin/hostinger.sh` (snapshot, métricas, reinício, recuperação)

**Files:**
- Create: `bin/hostinger.sh`
- Modify: `bin/health.sh` (linha de métricas), `scripts/05-servicos.sh` (instala)
- Test: `tests/test-hostinger.sh`

**Interfaces:**
- Consumes: spike Task 3 (endpoints, campos).
- Produces: `hostinger.sh metricas|snapshot|reiniciar|recuperacao`. Token `HOSTINGER_API_TOKEN` e
  `HOSTINGER_VM_ID` do `admin.env`, passados ao `curl` por `-K -` (stdin). `metricas` imprime
  `  ok    hostinger cpu N% ram N% disco N%` (só leitura, usado pelo `health.sh`). Os três que alteram estado
  exigem `--sim` e, sem ele, imprimem o que fariam e saem com rc 3.

- [ ] **Step 1:** testes (stub `curl` registra stdin): token fora da linha de comando; `snapshot` sem `--sim` → rc 3
  e nenhuma chamada POST; com `--sim` → POST no caminho do spike; `metricas` formata a linha; API com erro →
  `FALHA hostinger indisponível`, rc 1.
- [ ] **Step 2–4:** FALHA → implemente → passa.
- [ ] **Step 5:** `docs/srv-dev-README.md`: "Antes de cada deploy de etapa: `sudo hostinger.sh snapshot --sim`"
  e a camada 3 do fallback (`reiniciar --sim`, `recuperacao --sim`).
- [ ] **Step 6:** `git commit -m "feat: API da Hostinger para snapshot, métricas e recuperação"`.

### Task 15: Aviso de agente concluído

**Files:**
- Create: `opencode/plugin/aviso.js`, `opencode/plugin/aviso.test.mjs`
- Modify: `scripts/36-opencode.sh` (instala o plugin), `scripts/16-agente.sh` (cria
  `/srv/dev/secrets/aviso.env`, 0640 `root:agente`, só com `NTFY_TOPIC` de um tópico próprio `NTFY_TOPIC_AVISO`)

**Interfaces:**
- Consumes: spike Task 5 (nome do evento e campos).
- Produces: plugin que, no evento de sessão ociosa, chama
  `ALERTA_ENV=/srv/dev/secrets/aviso.env /usr/local/lib/stack-vps/alertar.sh "agente terminou" "<projeto>: <título>"`
  **só** se a sessão ficou ocupada por pelo menos `MIN_OCUPADA_S = 120` segundos desde a última mensagem do
  usuário; no máximo um aviso por transição para ocioso. Falha do alerta é engolida (nunca derruba o OpenCode).

- [ ] **Step 1:** `node --test opencode/plugin/aviso.test.mjs`, com o executor de shell injetado:
  ocupada 30 s → nenhum aviso; ocupada 300 s → um aviso com projeto e título; dois eventos ociosos seguidos sem
  nova mensagem → um aviso; executor lança erro → plugin não lança.
- [ ] **Step 2–4:** FALHA → implemente → passa. Acrescente `node --test opencode/plugin/` ao `tests/run.sh`.
- [ ] **Step 5:** `git commit -m "feat: aviso no celular quando o agente termina"`.

### Task 16: Remoções e documentação

**Files:**
- Delete: `scripts/22-openrig.sh`, `scripts/23-papeis.sh`, `scripts/30-sysbox.sh`, `scripts/31-rede-containers.sh`,
  `scripts/33-runners.sh`, `bin/rig-dupla`, `openrig/`, `compose/runners.yml`,
  `systemd/stack-rede-containers.service`, `tests/test-31-rede-containers.sh`, `docs/openrig.md`
- Modify: `README.md`, `scripts/29-skills.sh:81-88` (tira o Continue), `docs/AGENTS.md` (tira Continue e OpenRig;
  `modelo` fica), `pmo/web/manual.html` (seções de OpenRig, sysbox, runners, Continue),
  `docs/pmo-ux-ui-handoff.md` (aviso no topo: "Substituído por `docs/superpowers/specs/2026-10-18-lugar-de-trabalho-design.md`"),
  `docs/development-hub-continuity.md` (aponta o spec novo)
- Create: `docs/runbooks/2026-10-remocoes-vps.md`

`24-modelos.sh`, `bin/modelo` e `docs/modelos.tsv` **ficam** até a etapa 4.

- [ ] **Step 1:** `git grep -nE "22-openrig|23-papeis|30-sysbox|31-rede-containers|33-runners|rig-dupla|openrig|sysbox|rede-containers|runners\.yml|continue\.continue|~/.continue"`
  — anote cada ocorrência fora de `docs/superpowers/` (histórico fica).
- [ ] **Step 2:** apague e edite até o mesmo `git grep` não achar nada fora de `docs/superpowers/` e do runbook.
- [ ] **Step 3:** `bash tests/run.sh` (WSL) passa.
- [ ] **Step 4:** runbook da VPS (executar só com aprovação, como root, um bloco por item, cada um com o comando de
  conferência): parar e desabilitar `stack-rede-containers`; remover containers e imagens de runner; remover o
  pacote sysbox; remover `~/.continue` e a extensão do VS Code do `agente`; remover o estado do OpenRig em
  `/srv/dev/state/openrig`. Antes de tudo: `sudo bash /opt/stack-vps/bin/hostinger.sh metricas` e então `... snapshot --sim` (o `hostinger.sh` só entra no PATH depois do `05-servicos.sh`).
- [ ] **Step 5:** `git commit -m "chore: remove OpenRig, sysbox, rede de containers, runners e Continue"`.

**Pré-requisitos do deploy da etapa 2 (uma vez, pelo dono):**
- `admin.env` com `PMO_HOSTS` (`stack.<tailnet>.ts.net:8443,localhost:8080`, porta inclusa), `PMO_LOGINS`,
  `GITHUB_TOKEN`, `HOSTINGER_API_TOKEN`, `HOSTINGER_VM_ID` (e, opcionais, `PMO_ATALHO_OPENCODE`, `LINEAR_*`); formatos em
  `admin.env.example` e na tabela de `docs/srv-dev-README.md`. O `34-pmo.sh` aborta antes de escrever se faltar algo.
- "HTTPS Certificates" habilitado no admin da tailnet (aba DNS); sem isso o `37-tailscale-serve.sh` falha.
- No notebook do dono, `*.ts.net` não resolve (sem MagicDNS): linha `100.76.167.6 stack.<tailnet>.ts.net` no arquivo
  `hosts` do Windows, ou ligar o MagicDNS (`docs/ssh-config.md`).

**PORTÃO OBRIGATÓRIO antes de rodar o `34-pmo.sh` com a nova unidade (com aprovação):** o PMO só aceita ação se o
`tailscale serve` entregar o `X-Forwarded-For`; sem ele, toda ação pelo painel dá 403 (falha fechada).
1. Suba um backend de eco em **socket Unix** (não TCP: o `Host` só muda com alvo `unix:`, e um eco TCP daria falso
   verde), por exemplo (testado com `curl --unix-socket`; sem o `log_message` vazio o handler quebra, pois
   `client_address` é `''` em AF_UNIX, e o curl sai com 52):
   ```python
   import os, socketserver
   from http.server import BaseHTTPRequestHandler
   S = "/tmp/eco.sock"
   if os.path.exists(S): os.unlink(S)
   class H(BaseHTTPRequestHandler):
       def log_message(self, *a): pass
       def do_GET(self):
           b = "".join(f"{k}: {v}\n" for k, v in self.headers.items()).encode()
           self.send_response(200); self.send_header("Content-Length", str(len(b))); self.end_headers(); self.wfile.write(b)
   socketserver.UnixStreamServer(S, H).serve_forever()
   ```
   em `/tmp/eco.sock`, de dono o usuário que o roda.
2. Publique-o com `tailscale serve --bg --https=9443 unix:/tmp/eco.sock` (porta temporária, diferente de 443 e 8443).
3. Requisite `https://stack.<tailnet>.ts.net:9443/` **do notebook** e **de dentro da VPS como `agente`**
   (`sudo -u agente -H curl -s …`). Registre, nos dois casos, quais `Host`, `X-Forwarded-Host`, `X-Forwarded-For` e
   `Tailscale-User-Login` chegam, e com que valores.
4. Critérios: o `Host` chega como `localhost` e o nome real (`stack.<tailnet>.ts.net:9443`) chega em
   `X-Forwarded-Host` (o PMO valida esse cabeçalho no modo socket, e só o aceita quando o `Host` é exatamente `localhost`); do notebook, `X-Forwarded-For` termina no IP
   tailnet do notebook; de dentro da VPS, termina no IP da própria stack (é isso que o PMO recusa). **Se o
   `X-Forwarded-Host` não chegar com o nome real, ou o `X-Forwarded-For` não chegar, PARE e avise o dono antes do
   deploy:** o painel pelo serve fica impossível (falha fechada). Para o `X-Forwarded-For`, a opção (a): marcar o
   nó `stack` com tag no ACL da tailnet (nó com tag não recebe `Tailscale-User-Login`, então o agente na VPS nunca é
   identificado como o dono) e ajustar o desenho; decisão de ACL do dono.
5. Remova: `tailscale serve --https=9443 off` e pare o backend de eco.

**Deploy da etapa 2 (com aprovação):** snapshot (`sudo bash /opt/stack-vps/bin/hostinger.sh metricas`, conferência
de credencial só leitura, e então `sudo bash /opt/stack-vps/bin/hostinger.sh snapshot --sim`; o `hostinger.sh` só
entra no PATH depois do `05-servicos.sh`) → `git pull` em `/opt/stack-vps` → portão acima → `sudo ./34-pmo.sh` →
`sudo ./37-tailscale-serve.sh` → como `agente`, `36-opencode.sh` → `sudo ./05-servicos.sh` → runbook de
remoções → do laptop, abrir `https://stack.<tailnet>.ts.net` e o PMO em `:8443`; ensaio do fallback: derrubar o
`tailscaled` por 2 min (`sudo systemctl stop tailscaled; sleep 120; sudo systemctl start tailscaled` em `tmux`) e
entrar por `ssh stack-cf`; `stack-emergencia on`, abrir de um celular fora da tailnet, `off`.
Prova extra do C1: de dentro da VPS, como `agente`, `curl -s https://stack.<tailnet>.ts.net:8443/acao -H 'X-PMO: 1'
-H 'Content-Type: application/json' -d '{"acao":"arquivar","alvo":"<id de teste>"}'` deve dar 403 e a fila
(`/var/lib/pmo/fila`) deve ficar vazia.
**Rollback:** restaurar o snapshot, ou `git revert` do merge e rodar de novo `34-pmo.sh`, **e depois**
`tailscale serve reset` (ou `tailscale serve --https=8443 off` e `--https=443 off`): a publicação persiste e
continuaria apontando para o socket e para o OpenCode.

---

## Etapa 3 — PMO: ciclo de vida e Linear

Branch `feat/etapa3-pmo-linear`.

### Task 17: Estágio `congelado`

**Files:**
- Modify: `pmo/regras.py` (`ESTAGIOS`, `INATIVOS`, `contar`), `pmo/web/app.js` (`CORES`, botões)
- Test: `pmo/tests/test_regras.py`, `pmo/tests/test_servidor.py`

Congelar é escolha de estágio no PMO (vai para `classes.json`, como o "Marcar como parado" já faz);
descongelar é voltar o estágio a "" (pelo `STATE.md` / sugerido).

- [ ] **Step 1:** testes:
  - `test_congelado_nao_e_esquecido` — `esquecido("congelado", 400, None, False) is None`;
  - `test_aplicar_classes_congelado` — projeto esquecido com classe `estagio: "congelado"` sai do alarme;
  - `test_contar_congelados` — `contar(...)["congelados"] == 1`;
  - `test_classificar_congelado_aceito` (servidor) → 200.
- [ ] **Step 2–4:** FALHA → `ESTAGIOS += ("congelado",)`, `INATIVOS += ("congelado",)`, contador `congelados` →
  passa.
- [ ] **Step 5:** `app.js`: cor de `congelado` em `CORES`; no detalhe, botão "Congelar" (classificar com
  `estagio: "congelado"`) quando não está congelado e "Descongelar" (`estagio: ""`) quando está; contador no topo.
- [ ] **Step 6:** `git commit -m "feat: congelar e descongelar projeto no PMO"`.

### Task 18: Painel final em um lugar só

**Files:**
- Modify: `pmo/painel.py` (nova `montar`), `pmo/servidor.py` (`ler_painel` usa `montar`)
- Test: `pmo/tests/test_painel.py`

**Interfaces:**
- Produces: `montar(dados: dict, ajustes: dict, classes: dict) -> dict` =
  `aplicar_classes(aplicar_ajustes(dados, ajustes), classes)`. É a visão que o servidor mostra e que o Linear
  espelha — os dois não podem divergir.

- [ ] **Step 1:** `test_montar_aplica_ajuste_e_classe` (projeto arquivado por ajuste e com estágio de classe).
- [ ] **Step 2–4:** FALHA → implemente e troque o uso no servidor → toda a suíte passa.
- [ ] **Step 5:** `git commit -m "refactor: montar painel final num lugar só"`.

### Task 19: Espelho PMO → Linear

**Files:**
- Create: `pmo/linear.py`, `pmo/tests/test_linear.py`, `systemd/pmo-linear.service`, `systemd/pmo-linear.timer`
- Modify: `scripts/34-pmo.sh`, `bin/health.sh`
- Test: `pmo/tests/test_linear.py`, `tests/test-health.sh`

**Interfaces:**
- Consumes: `montar` (Task 18); spike Task 6 (status, time, autenticação).
- Produces, em `pmo/linear.py`:
  - `TIPO_DO_ESTAGIO = {"ideia": "backlog", "em andamento": "started", "em revisão": "started", "parado": "paused",
    "congelado": "paused", "entregue": "completed", "encerrado": "completed", "arquivado": "canceled"}`
  - `escolher_status(estagio: str, statuses: list[dict]) -> str` — `statuses` = `[{"id", "name", "type"}]`;
    primeiro o status de **nome** igual ao estágio (sem acento, sem caixa); senão o primeiro do **tipo**
    `TIPO_DO_ESTAGIO[estagio]`; nenhum → `ValueError`.
  - `desejado(painel: dict) -> dict[str, tuple[str, str]]` — `id → (nome, estágio)`; `projetos` usam
    `estagio or estagio_sugerido or "em andamento"`; `arquivados` viram `"arquivado"`; `a_destinar` fica fora.
  - `planejar(desejado: dict, vinculos: dict) -> list[dict]` — `vinculos[id] = {"linear_id": str, "enviado": str}`;
    sem vínculo e estágio ≠ arquivado → `{"op": "criar", "id", "nome", "estagio"}`; com vínculo e
    `enviado != estagio` → `{"op": "atualizar", "id", "linear_id", "estagio"}`; arquivado sem vínculo → nada.
  - `LIMITE_LOTE = 20`; `class LoteGrande(Exception)`; `verificar_lote(ops: list, confirmar_lote: bool) -> None`
    levanta `LoteGrande` se houver mais de 20 `criar` sem `confirmar_lote`.
  - `class Linear` (`token: str`, `post` injetável) com `statuses() -> list[dict]`, `time(key: str) -> str`,
    `criar(nome: str, time_id: str, status_id: str) -> str`, `atualizar(linear_id: str, status_id: str) -> None`.
    `POST https://api.linear.app/graphql`, cabeçalho de autenticação conforme o spike; erro HTTP ou `errors` no
    JSON → `RuntimeError` com a mensagem sem o token. Operações:
    `projectStatuses { nodes { id name type } }`, `teams(filter: {key: {eq: $k}}) { nodes { id } }`,
    `projectCreate(input: {name: $n, teamIds: [$t], statusId: $s}) { project { id } }`,
    `projectUpdate(id: $id, input: {statusId: $s}) { success }`.
  - `sincronizar(api, painel: dict, vinculos_path: str, trava_path: str, previa: bool, confirmar_lote: bool,
    time_key: str) -> list[dict]` — pega `fcntl.flock(LOCK_EX | LOCK_NB)` em `trava_path`; ocupada → retorna `[]`
    sem chamar a API; grava `vinculos_path` (atômico) **depois de cada operação bem-sucedida**; em `previa` só
    retorna as operações.
  - CLI `python3 -m pmo.linear [--previa] [--confirmar-lote]`: token de `/etc/pmo/linear-token`, time de
    `/etc/pmo/linear-team`, painel de `montar(painel.json, ajustes.json, classes.json)`; imprime uma linha por
    operação; exceção → mensagem em stderr e rc 1.

- [ ] **Step 1:** testes em `test_linear.py`:
  - `test_status_por_nome_ignora_acento` — `"em revisão"` acha status `"Em Revisao"`;
  - `test_status_por_tipo` — sem nome igual, `"congelado"` → status `type == "paused"`;
  - `test_status_inexistente_levanta`;
  - `test_desejado_arquivado_e_sugerido`;
  - `test_planejar_cria_atualiza_e_ignora` (sem vínculo cria; mudou atualiza; igual nada; arquivado sem vínculo
    nada; arquivado com vínculo atualiza para `arquivado` uma vez e depois nada);
  - `test_lote_grande_recusado_sem_confirmacao` / `test_lote_grande_com_confirmacao`;
  - `test_previa_nao_chama_escrita` (api falsa registra chamadas);
  - `test_falha_no_meio_guarda_progresso` — 3 criações, a 2ª lança: `linear.json` tem a 1ª;
  - `test_segunda_corrida_com_trava_nao_faz_nada` (trava já presa por outro descritor) (**Review Focus 2**);
  - `test_erro_da_api_sem_token_na_mensagem`.
- [ ] **Step 2:** `python3 -m unittest pmo.tests.test_linear -v`. Esperado: FALHA (módulo não existe).
- [ ] **Step 3:** implemente `pmo/linear.py` (stdlib: `urllib.request`, `json`, `fcntl`, `unicodedata`).
- [ ] **Step 4:** testes passam; suíte inteira passa.
- [ ] **Step 5:** `systemd/pmo-linear.service` (`Type=oneshot`, `User=pmo`, `Environment=PYTHONPATH=/opt`,
  `ExecStart=/usr/bin/python3 -m pmo.linear`) e `pmo-linear.timer` (`OnCalendar=*:0/5`, `Persistent=true`).
  `34-pmo.sh`: se `LINEAR_API_KEY` e `LINEAR_TEAM_KEY` existem no `admin.env`, grava `/etc/pmo/linear-token` e
  `/etc/pmo/linear-team` (0640 `root:pmo`, mesmo padrão do token do GitHub), instala as unidades **sem** habilitar
  o timer (a primeira carga é manual); sem as variáveis, pula com aviso.
- [ ] **Step 6:** `health.sh`: `systemctl is-failed --quiet pmo-linear.service` → `FALHA espelho do Linear`;
  teste em `tests/test-health.sh`.
- [ ] **Step 7:** `git commit -m "feat: espelho do estágio dos projetos no Linear"`.

**Deploy da etapa 3 (com aprovação):** snapshot → `sudo ./34-pmo.sh` → prévia
`sudo -u pmo env PYTHONPATH=/opt python3 -m pmo.linear --previa` (mostrar a lista ao Ricardo) → com aprovação,
`--confirmar-lote` → conferir no Linear → `sudo systemctl enable --now pmo-linear.timer`.
**Rollback:** `systemctl disable --now pmo-linear.timer`; os projetos criados no Linear ficam (apagar é decisão do
Ricardo, à mão).

---

## Etapas 4 a 6 — roteiro (cada uma ganha plano próprio)

### Etapa 4 — 9router (depois do spike da Task 1)

- `scripts/24-modelos.sh` vira `scripts/24-9router.sh` (como `agente`): versão fixada, unidade de usuário
  `9router.service` em `127.0.0.1:20128`, recusa subir sem a senha no ambiente, tokens em 0600.
- OpenCode configurado com o 9router como provedor compatível com OpenAI (no `36-opencode.sh`).
- `bin/modelo` aponta para o 9router; `docs/modelos.tsv` passa a ter nomes de modelo do 9router; teste
  `tests/test-modelo.sh` atualizado; a skill de pentest continua funcionando sem mudança.
- `health.sh`: `ok    9router` / `FALHA 9router`.
- Se o spike decidir "duas faixas": o 9router recebe só OpenRouter, DeepSeek e Featherless; os CLIs ficam com as
  assinaturas; nada mais muda.

### Etapa 5 — `@ness/auth` v1 (repositório próprio)

- Repositório privado `ness-auth`, TypeScript, Hono; publicado no GitHub Packages como `@ness/auth`.
- Extração de `src/sso.ts`, `src/middleware/auth.ts`, `src/routes/auth.ts`, `auth-policy.ts` e
  `secret-crypto.ts` do niso, sem as dependências de domínio (projetos, módulos, trilha → interface `Trilha`
  injetada).
- Interface de armazenamento `AuthStore` com dois adaptadores: D1/KV e Postgres.
- Testes do niso (`sso.test.ts` e os de autenticação) rodando contra os dois adaptadores (miniflare e
  `postgres.yml` descartável).
- Modos por sistema: sem SSO, OIDC do cliente, OIDC do Authentik da ness; login de emergência de administrador.

### Etapa 6 — `/novo-projeto` e templates

- Comando do OpenCode `opencode/command/novo-projeto.md` que conduz a skill `project-bootstrap`.
- `templates/sistema/` (Hono + ness.design + `@ness/auth` opcional; `wrangler.jsonc`, `vercel.json`, Cloud Run,
  `config/deploy.yml` do Kamal), `templates/agente/` (9router + promptfoo com `casos/`), `templates/parecer/`
  (Typst ness.design + `fontes.md`; conteúdo em `/srv/dev/pareceres/<nome>`).
- `standards/profiles.json`: tira `azure`, troca `local` por `fora-das-nuvens`; `scripts/35-projeto-standards.py`
  e seu teste acompanham.
- Teste por template: gera numa pasta temporária, build, roda os testes do projeto gerado.
