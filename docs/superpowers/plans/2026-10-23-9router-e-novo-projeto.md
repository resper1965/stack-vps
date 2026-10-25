# 9router (faixa 1) e `/novo-projeto` Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Entregar em código local o 9router (só chaves de API) e o comando `/novo-projeto` com 3 templates, prontos para instalar na VPS com aprovação.

**Architecture:** Script `41-9router.sh` instala e valida uma unidade de usuário do `agente`; OpenCode e `bin/modelo` passam a usar o 9router como provedor OpenAI-compatível. `/novo-projeto` é um comando do OpenCode que chama o gerador `scripts/42-novo-projeto.py`, que copia `templates/<natureza>/`, escreve `STATE.md` e o `.standards.json`.

**Tech Stack:** bash (padrão `normaliza`/`STACK_TESTE` do repositório), Python stdlib, systemd de usuário, tests/run.sh no WSL.

**Spec:** `docs/superpowers/specs/2026-10-23-9router-e-novo-projeto-design.md` (mestre: `2026-10-18-lugar-de-trabalho-design.md`).

## Global Constraints

- Nada na VPS, nada de credencial real, nada de chamada de rede real nos testes; stubs (`STACK_TESTE=1`).
- 9router: versão fixa `0.5.104`; escuta só `127.0.0.1:20128`; `REQUIRE_API_KEY=true`; o script recusa subir sem `INITIAL_PASSWORD` (≥ 16 caracteres e ≠ `123456`) e sem `JWT_SECRET`; arquivo de ambiente 0600; nunca imprimir valores.
- Scripts da VPS seguem o padrão do repositório: fail-closed em caminho ausente, overrides de teste só com `STACK_TESTE=1`, `cd /` antes de `sudo -u`, segredos nunca em argv.
- `STATE.md` no formato lido por `pmo/regras.py`: linhas `**Tipo:** <app|site|agente|dados|infra|documento|conhecimento>`, `**Estágio:** ideia`, `**Próximo passo:** ...`.
- Templates: nenhum cria GitHub Actions, chave, assinatura ou deploy; `ci: local-vps`; sem dado real; sem segredo.
- Commits em português, conventional, trailer `Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>`. Baseline do `tests/run.sh`: só 28 avisos SC2319 antigos.

## Review Focus

- `INITIAL_PASSWORD` fraca/ausente, `REQUIRE_API_KEY` desligado, arquivo de ambiente com modo largo: o script recusa e não imprime o valor.
- Reexecução do `41-9router.sh` e do `36-opencode.sh` não duplica nem destrói o `opencode.json` do dono (merge idempotente, sem escolher modelo padrão).
- `42-novo-projeto.py` em pasta existente não vazia, em `--nome` com `../` ou maiúsculas, e `--destino` desconhecido: recusa sem escrever nada.
- Marcador `{{...}}` esquecido ou segredo literal em qualquer template gerado.
- `health.sh` sem a unidade do 9router instalada não imprime nada (não vira FALHA).

---

### Task 1: Script e unidade do 9router

**Files:**
- Create: `scripts/41-9router.sh`, `9router/9router.service`, `tests/test-41-9router.sh`

**Interfaces:**
- Produces: `scripts/41-9router.sh` (roda como `agente`; env de teste `NR_PREFIX`, `NR_ENV`, `NR_UNIT_DIR`, `NR_NPM` só com `STACK_TESTE=1`); unidade `9router.service` com `EnvironmentFile=%h/.config/9router/9router.env`, `ExecStart=%h/.local/bin/9router`; constante `VERSAO=0.5.104`.

- [ ] **Step 1:** Escrever `tests/test-41-9router.sh` (padrão de `tests/test-health.sh` e do teste do 36, com npm e systemctl stubs). Casos: (a) sem arquivo de ambiente → rc≠0; (b) modo ≠ 0600 → rc≠0; (c) `INITIAL_PASSWORD=123456`, curta (< 16) ou ausente → rc≠0 e o valor nunca aparece na saída; (d) sem `JWT_SECRET` → rc≠0; (e) `REQUIRE_API_KEY` ausente ou ≠ true → rc≠0; (f) tudo certo → npm stub chamado com `9router@0.5.104` e `--prefix`, unidade instalada em `NR_UNIT_DIR`, `systemctl --user enable --now` chamado; (g) rodar duas vezes → mesma unidade, sem erro; (h) não-`agente` sem `STACK_TESTE` → rc≠0.
- [ ] **Step 2:** Rodar o teste (WSL) e ver falhar.
- [ ] **Step 3:** Implementar `scripts/41-9router.sh` e `9router/9router.service` (modelo: `scripts/36-opencode.sh` e `opencode/opencode-web.service`): `Environment=HOSTNAME=127.0.0.1 PORT=20128 DATA_DIR=%h/.9router`, `Restart=on-failure`. Instalar com `npm install -g --prefix "$HOME/.local" 9router@$VERSAO` só se a versão instalada diferir. `chmod 700` no `DATA_DIR`.
- [ ] **Step 4:** Testes e `shellcheck -x -S warning` limpos.
- [ ] **Step 5:** Commit `feat: 9router (faixa 1) com unidade de usuário e recusa de senha fraca`.

### Task 2: Consumidores: OpenCode, `bin/modelo`, serve, health

**Files:**
- Modify: `scripts/36-opencode.sh`, `bin/modelo`, `scripts/37-tailscale-serve.sh`, `bin/health.sh`, `tests/test-modelo.sh`, `tests/test-health.sh`, o teste do 37 (o que existir)
- Create: `opencode/provider-9router.json`

**Interfaces:**
- Consumes: porta 20128 e `NINE_ROUTER_API_KEY` (Task 1, spec).
- Produces: bloco `provider["9router"]` mesclado em `~/.config/opencode/opencode.json` (sem `model`/`small_model`); provedor `9router` em `PROVEDORES` do `bin/modelo` (`NINE_ROUTER_API_KEY`, base `MODELO_BASE_9ROUTER`, padrão `http://127.0.0.1:20128/v1`); serve `--https=20128`; seção `9router` do health.

- [ ] **Step 1:** Testes primeiro. `test-modelo.sh`: apelido com provedor `9router` chama a base do 9router com a chave certa (servidor stub local); os apelidos atuais continuam iguais. `test-health.sh`: sem unidade → sem seção; unidade ativa + HTTP ok → `ok    9router`; unidade inativa ou HTTP falho → `FALHA 9router` e rc 1. `36-opencode.sh`: merge do provedor num `opencode.json` existente preserva as outras chaves e é idempotente; sem `jq`, falha clara. `37`: o stub do `tailscale` registra `serve --bg --https=20128 http://127.0.0.1:20128`.
- [ ] **Step 2:** Rodar e ver falhar.
- [ ] **Step 3:** Implementar. Não trocar linhas de `docs/modelos.tsv` (os nomes de modelo do 9router só se conhecem com ele instalado); apenas permitir a coluna `provedor=9router`.
- [ ] **Step 4:** Tudo verde, shellcheck sem aviso novo.
- [ ] **Step 5:** Commit `feat: OpenCode, modelo e health passam a enxergar o 9router`.

### Task 3: Perfis de padrão e skill de bootstrap

**Files:**
- Modify: `standards/profiles.json`, `standards/README.md`, `scripts/35-projeto-standards.py`, `tests/test-35-projeto-standards.py`, `skills/project-bootstrap/SKILL.md`

**Interfaces:**
- Produces: perfis `gcp`, `vercel`, `cloudflare`, `fora-das-nuvens` (sem `azure`, sem `local`); `35-projeto-standards.py --provider fora-das-nuvens`.

- [ ] **Step 1:** Ajustar o teste: `fora-das-nuvens` aceito; `azure` e `local` recusados; o caso de pasta existente passa a usar um provedor válido e continua recusando.
- [ ] **Step 2:** Rodar e ver falhar.
- [ ] **Step 3:** Implementar; guidance de `fora-das-nuvens`: "qualquer máquina com SSH e Docker; deploy e rollback pelo Kamal; segredos por projeto; sem porta pública sem proxy TLS". Skill: trocar "GCP, Azure, Vercel, Cloudflare ou VPS" por "GCP, Vercel, Cloudflare ou fora das nuvens" e apontar para `/novo-projeto`.
- [ ] **Step 4:** `python3 tests/test-35-projeto-standards.py` e `tests/run.sh` verdes.
- [ ] **Step 5:** Commit `feat: perfis fora-das-nuvens e sem azure no bootstrap`.

### Task 4: Gerador `42-novo-projeto.py`

**Files:**
- Create: `scripts/42-novo-projeto.py`, `tests/test-42-novo-projeto.py`

**Interfaces:**
- Consumes: perfis (Task 3), `scripts/35-projeto-standards.py`.
- Produces: `42-novo-projeto.py <pasta> --natureza {sistema,agente,parecer} --nome <slug> [--destino <perfil> ...] [--apply]`; mapa natureza→Tipo do STATE (`sistema`→`app`, `agente`→`agente`, `parecer`→`documento`); marcadores `{{nome}}`, `{{destino}}`; arquivos `*.tmpl` perdem o sufixo; env `TEMPLATES_DIR` só com `STACK_TESTE=1`. Os testes usam um diretório de templates mínimo criado no próprio teste.

- [ ] **Step 1:** Testes: prévia sem `--apply` não cria nada e imprime `PREVIEW`; `--apply` cria a pasta com os arquivos do template, marcadores trocados, `STATE.md` aceito por `pmo.regras.ler_state` com `tipo`/`estagio=ideia` corretos, `.standards.json` com os destinos; pasta existente e não vazia → rc≠0 sem escrever; `--nome` com `/`, `..`, espaço ou maiúscula → rc≠0; `--destino` desconhecido → rc≠0; natureza desconhecida → rc≠0; marcador `{{x}}` não definido deixado no resultado → rc≠0 sem escrever.
- [ ] **Step 2:** Rodar e ver falhar.
- [ ] **Step 3:** Implementar (stdlib; gera numa pasta temporária no mesmo diretório e renomeia só no fim, para não deixar pasta pela metade).
- [ ] **Step 4:** Verde.
- [ ] **Step 5:** Commit `feat: gerador de projetos novos a partir de templates`.

### Task 5: Templates sistema, agente e parecer

**Files:**
- Create: `templates/sistema/**`, `templates/agente/**`, `templates/parecer/**`, `tests/test-templates.py`

**Interfaces:**
- Consumes: gerador (Task 4); marcadores `{{nome}}`, `{{destino}}`.
- Produces: `sistema` (package.json Hono+TS, `src/index.ts`, teste mínimo, `README.md`, e por destino `wrangler.jsonc` / `vercel.json` / `Dockerfile` (Cloud Run) / `Dockerfile` + `config/deploy.yml` (Kamal); só os arquivos do destino escolhido são copiados), `agente` (TypeScript, cliente OpenAI-compatível lendo `NINE_ROUTER_API_KEY` e base `http://127.0.0.1:20128/v1`, `promptfoo/promptfooconfig.yaml` + `casos/` com um caso que passa por provedor estático), `parecer` (`parecer.md`, `fontes.md` com tabela citação | verificada | fonte, `typst/parecer.typ`, `Makefile` com alvo `pdf`, `.gitignore` do conteúdo; nota de que o conteúdo vai em `/srv/dev/pareceres/<nome>`).

- [ ] **Step 1:** `tests/test-templates.py`: para cada natureza (e cada destino do `sistema`), gerar numa pasta temporária e verificar arquivos esperados; nenhum `{{` sobrando; nenhum padrão de segredo (`sk-`, `AKIA`, `-----BEGIN`); nenhum `.github/workflows`; `STATE.md` válido; `sistema` com destino X contém só o arquivo de deploy de X; `fora-das-nuvens` inclui `config/deploy.yml` com `image` e `servers`. Sem rede: `package.json` é validado com `json.load`, `npm install` não é rodado (dizer isso na saída do teste).
- [ ] **Step 2:** Rodar e ver falhar.
- [ ] **Step 3:** Criar os templates (arquivos pequenos e corretos; o `config/deploy.yml` do Kamal é só arquivo, executado pela imagem oficial do Kamal na máquina de deploy, sem Ruby na `stack`).
- [ ] **Step 4:** Verde.
- [ ] **Step 5:** Commit `feat: templates sistema, agente e parecer`.

### Task 6: Comando `/novo-projeto` e provisionamento

**Files:**
- Create: `opencode/command/novo-projeto.md`
- Modify: `scripts/36-opencode.sh`, `skills/project-bootstrap/SKILL.md`, teste do 36

**Interfaces:**
- Consumes: gerador (Task 4), skill (Task 3).
- Produces: comando que instrui: confirmar que o projeto é novo; perguntar natureza, nome e destino(s) (poucas perguntas); rodar o gerador sem `--apply` e mostrar a prévia; só com "sim" rodar com `--apply`; perguntar à parte se cria repositório privado (`gh repo create --private`), nunca presumir; nunca tocar projeto existente; abrir a sessão na pasta nova. Instalado em `~/.config/opencode/command/novo-projeto.md` pelo 36 (cópia idempotente).

- [ ] **Step 1:** Teste do 36: o comando é instalado, a reexecução é idempotente, e um arquivo existente do dono é substituído só se tiver o marcador `<!-- stack-vps -->` na primeira linha (senão recusa e avisa).
- [ ] **Step 2:** Rodar e ver falhar.
- [ ] **Step 3:** Implementar.
- [ ] **Step 4:** Verde.
- [ ] **Step 5:** Commit `feat: comando /novo-projeto no OpenCode`.

### Task 7: Documentação

**Files:**
- Modify: `README.md`, `docs/AGENTS.md`, `docs/srv-dev-README.md` (se listar serviços)

- [ ] **Step 1:** Linhas dos scripts 41 e 42 no README ("ainda não instalado na VPS"); `docs/AGENTS.md`: modelos pelo 9router (faixa 1: chaves de API), assinaturas pelos CLIs; criação de projeto por `/novo-projeto`; sem prometer nada não instalado.
- [ ] **Step 2:** `tests/run.sh` verde (baseline) e `git diff --check`.
- [ ] **Step 3:** Commit `docs: 9router e /novo-projeto`.

---

## Etapa VPS (depois da revisão final, só com aprovação a cada passo)

Spike curto do 9router (permissão dos arquivos de dados, senha forte, endpoint com chave) → `41-9router.sh` → chaves no 9router → `37` → `36` (comando e provedor) → conferir `health.sh`. Os CLIs `claude`/`codex`/`agy` são instalados e logados pelo dono no `agente`, fora deste plano.
