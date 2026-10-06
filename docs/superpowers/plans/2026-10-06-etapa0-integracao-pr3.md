# Etapa 0 — integrar o PR #3 no modelo agente/dev

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Trazer para a branch `feat/migracao-vps` tudo o que o PR #3 (30/09) entregou — Antigravity CLI, OpenRig, papéis, OpenRouter no Codex, Postgres de teste, verticais, `projetos.env`, duas contas Claude, skills —, rodando como `agente`, e concluir o PR #4.

**Architecture:** Merge de `origin/main` em `feat/migracao-vps`. Os scripts do PR #3 são renumerados de 22 a 29 (os 14–21 já são da migração e estão aplicados) e passam a exigir o usuário `agente`. Decisões do Ricardo de 30/09 registradas no PR #3 prevalecem sobre o desenho de 05/10 onde conflitam.

**Tech Stack:** bash, git, Node 24 (mise), Claude Code, Codex, Antigravity CLI (`agy`), OpenRig, Docker rootless.

**Specs:** `docs/superpowers/specs/2026-10-05-ambiente-alvo-design.md`; corpo do PR #3 (`gh pr view 3`).

## Global Constraints

- Decisões de 30/09 que prevalecem: `secrets/projetos.env` é **um arquivo só** para todos os projetos; contas Claude **bekaa** (padrão, `~/.claude`) e **ionic** (`~/.claude-ionic`, vertical ionic); Node **24** (o `lts` vira 26 em out/2026 e quebra o OpenRig); **material de caso forense não entra na VPS** (CLAUDE.md §9).
- Decisões de 05–06/10 que prevalecem: agentes e scripts de trabalho rodam como `agente`; `dev` só administra e não roda git em `/srv/dev/repos`; segredos de infra em `admin.env` (só `dev`), do agente em `agente.env`.
- `projetos.env`: 640 `dev:agente`, carregado no `.bashrc` do `agente` (não do `dev`).
- `/srv/dev/bin` é de root: o que o `agente` instala para si vai para `~agente/.local/bin`.
- Numeração: 14→22 (openrig), 15→23 (papeis), 16→24 (modelos), 17→25 (testes), 18→26 (verticais), 19→27 (secrets), 20→28 (contas-claude), 21→29 (skills).
- Commits em português, conventional commits, trailer de coautoria.

---

### Task 1: Merge e conflitos de texto

**Files:** `README.md`, `docs/CLAUDE.md`, `docs/AGENTS.md`, `scripts/04-agents.sh`, `scripts/03-tooling.sh`

- [ ] **Step 1:** `git merge --no-ff origin/main` na `feat/migracao-vps`. Expected: conflito em README.md, docs/AGENTS.md, docs/CLAUDE.md, scripts/04-agents.sh.
- [ ] **Step 2: `04-agents.sh`** — manter a checagem `[[ $(id -un) == agente ]]` e o `agente.env` da migração; acrescentar, do PR #3, a instalação do `agy` com seus plugins, a verificação do superpowers nos três harnesses (sem `|| true`) e o bloco que libera a escrita dos agentes em `/srv/dev/state`.
- [ ] **Step 3: `03-tooling.sh`** — ficar com a versão da migração (instala Docker, cloudflared, shellcheck) com `node@24` no lugar de `node@lts`. Em `scripts/16-agente.sh`, a linha `mise use -g node@lts` passa a `node@24`.
- [ ] **Step 4: `docs/CLAUDE.md` = `docs/AGENTS.md`** — manter a versão da migração (§2 com agente/dev, Docker em 127.0.0.1) e acrescentar do PR #3: "ponytail fica ligado por padrão" (§1), a linha do `projetos.env` reescrita para o agente ("Chave de projeto fica em `/srv/dev/secrets/projetos.env`, já carregada no shell do agente: use a variável, nunca copie o valor para `.env` de repositório nem o imprima. `admin.env` é só dos scripts de infra."), e as seções §8 (serviços de teste) e §9 (forense) inteiras. `diff` dos dois → iguais.
- [ ] **Step 5: `README.md`** — tabela de ordem da migração + seção "Scripts de trabalho (como agente)" listando 22–29 com uma linha cada, e os textos do PR #3 (OpenRig, modelos, verticais, contas, skills) com a numeração e o usuário novos.
- [ ] **Step 6:** `bash -n` em todos os scripts; commit `chore: integra o PR #3 (agy, OpenRig, verticais, contas, skills) na migracao`.

### Task 2: Renumerar e adaptar os scripts do PR #3 para o `agente`

**Files:** `scripts/{14..21}-*.sh` do PR #3 → `scripts/{22..29}-*.sh`; `bin/rig-dupla`

- [ ] **Step 1: Renomear com histórico**

```bash
git mv scripts/14-openrig.sh scripts/22-openrig.sh
git mv scripts/15-papeis.sh scripts/23-papeis.sh
git mv scripts/16-modelos.sh scripts/24-modelos.sh
git mv scripts/17-testes.sh scripts/25-testes.sh
git mv scripts/18-verticais.sh scripts/26-verticais.sh
git mv scripts/19-secrets.sh scripts/27-secrets.sh
git mv scripts/20-contas-claude.sh scripts/28-contas-claude.sh
git mv scripts/21-skills.sh scripts/29-skills.sh
```

(Os nomes 14–16 e 20 da migração já existem: o merge do Task 1 traz os do PR #3 com os mesmos números; renomear os do PR #3 **antes** de resolver qualquer colisão de arquivo — se o git marcar conflito add/add, `git show origin/main:scripts/14-openrig.sh > scripts/22-openrig.sh` e assim por diante.)

- [ ] **Step 2: Usuário** — em todos os 22–29: `[[ $(id -un) == dev ]] || { echo "rode como dev"; exit 1; }` → `[[ $(id -un) == agente ]] || { echo "rode como agente: sudo -u agente -H $0"; exit 1; }`; comentários "Roda COMO dev" → "Roda COMO agente".
- [ ] **Step 3: Segredos**
  - `23-papeis.sh`: `. /srv/dev/secrets/.env` → `. /srv/dev/secrets/agente.env`.
  - `24-modelos.sh`: a chave do OpenRouter é de projeto → `OPENROUTER_API_KEY` em `/srv/dev/secrets/projetos.env`; o `args` do `[model_providers.openrouter.auth]` passa a `". /srv/dev/secrets/projetos.env && printf %s \"$OPENROUTER_API_KEY\""` e a checagem final idem.
  - `27-secrets.sh`: o arquivo nasce `install -m 640 -o dev -g agente`, mas quem roda é o `agente`, que não cria em `secrets/` → o **arquivo passa a ser criado pelo `02-layout.sh`** (junto do `agente.env`, 640 `dev:agente`), e o 27 só instala o bloco de leitura no `.bashrc` do agente e conta as chaves. Remover do 27 o `install`/`chmod`.
- [ ] **Step 4: Caminhos que viraram de root**
  - `22-openrig.sh`: `install -m 755 "$R/bin/rig-dupla" /srv/dev/bin/rig-dupla` → `install -m 755 "$R/bin/rig-dupla" ~/.local/bin/rig-dupla` e remover o `ln -sfn`.
  - `25-testes.sh`: `install ... /srv/dev/bin/postgres.yml` → instalado pelo `05-servicos.sh` (root) em `/srv/dev/bin/postgres.yml`; o 25 só valida com `docker compose -f /srv/dev/bin/postgres.yml config -q` usando o Docker rootless (`DOCKER_HOST` do `.bashrc`); trocar a checagem `id -nG | grep -qw docker` por `docker info >/dev/null 2>&1 || { echo "docker rootless do agente parado: rode 16-agente.sh"; exit 1; }`. No `05-servicos.sh`, acrescentar `install -m 644 -o root -g root "$REPO"/compose/postgres.yml /srv/dev/bin/`.
- [ ] **Step 5: Referências cruzadas** — `grep -rn '1[4-9]-\|2[01]-\|scripts 08-15' scripts bin docs/*.md README.md` e corrigir menções aos números antigos dos scripts do PR #3 (ex.: "depois do 04 e do 20" no 29 → "depois do 04 e do 28"; "18-verticais.sh" no 28 → "26-verticais.sh").
- [ ] **Step 6:** `TESTAR` (shellcheck inclui os novos) → Expected: rc 0. Commit `refactor: scripts do PR #3 renumerados (22-29) e rodando como agente`.

### Task 3: Spec do ambiente-alvo alinhado às decisões de 30/09

**Files:** `docs/superpowers/specs/2026-10-05-ambiente-alvo-design.md`

- [ ] **Step 1:** Seção "Frente B — forense": substituir o container com evidências em `/srv/forense` por: "Na VPS entram só repositórios de código e método e o repositório `casos`; material de caso fica na estação forense (CLAUDE.md §9, decisão de 30/09). O container de ferramentas, se usado, analisa só dados sintéticos ou públicos." `/srv/forense` permanece criado e vazio.
- [ ] **Step 2:** Seção Segredos: `projetos/<p>.env` → `projetos.env` único (decisão de 30/09), 640 `dev:agente`.
- [ ] **Step 3:** Seção 1: "três agentes: Claude Code (contas bekaa e ionic), Codex (ChatGPT Pro; OpenRouter por `-p openrouter`), Antigravity CLI".
- [ ] **Step 4:** Commit `docs: ambiente-alvo segue as decisoes de 30/09 (forense, projetos.env, agy)`.

### Task 4: Aplicar na VPS e provar

- [ ] **Step 1:** Push da branch; na VPS `sudo git -C /opt/stack-vps pull -q` (dono root: o `dev` só lê pelo `sudo`).
- [ ] **Step 2:** `sudo bash /opt/stack-vps/scripts/02-layout.sh && sudo bash /opt/stack-vps/scripts/05-servicos.sh` (cria `projetos.env`, instala `postgres.yml`).
- [ ] **Step 3:** Como agente, na ordem: `04` (agy), `27`, `28`, `29`, `24`, `25`, `26`, `22`:

```bash
for s in 04-agents 27-secrets 28-contas-claude 29-skills 24-modelos 25-testes 26-verticais 22-openrig; do
  echo "== $s"; sudo -u agente -H bash /opt/stack-vps/scripts/$s.sh 2>&1 | tail -3
done
```

Expected: cada um termina sem `ERRO`; `29` lista as skills; `22` imprime a versão do `rig`.
- [ ] **Step 4:** Provas como agente: `agy --version`, `claude-ionic --version`, `rig --version`, `PG_PORTA=5433 docker compose -p teste -f /srv/dev/bin/postgres.yml up -d --wait && docker compose -p teste -f /srv/dev/bin/postgres.yml down` → ok; e de novo o `ataque.sh` (isolamento) → só `ok`.
- [ ] **Step 5:** `23-papeis.sh` **não** roda nesta etapa (faz commit em todos os repositórios do escopo; fica para quando o Ricardo pedir).

### Task 5: Concluir o PR #4

- [ ] **Step 1:** `TESTAR` → rc 0; push.
- [ ] **Step 2:** `gh pr merge 4 --merge`; `git switch main && git pull --ff-only`. Expected: PR `MERGED`.
- [ ] **Step 3:** Na VPS, `/opt/stack-vps` passa a seguir a `main`: `sudo git -C /opt/stack-vps switch main && sudo git -C /opt/stack-vps pull -q`.
