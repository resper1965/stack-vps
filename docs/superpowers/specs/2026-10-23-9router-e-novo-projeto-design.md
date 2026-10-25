# 9router (duas faixas) e `/novo-projeto` — decisões que fecham as etapas 4 e 6

**Data:** 2026-10-23 · **Estado:** aprovado pelo Ricardo em 2026-10-23 ("sim, siga")
**Complementa** `2026-10-18-lugar-de-trabalho-design.md` (seções 2, 3 e 10), que continua sendo o spec mestre, e
`2026-10-19-ci-sem-creditos-design.md`. Onde divergir, este documento vale para as etapas 4 e 6.

## O que mudou desde o spec mestre

| Tema | Antes | Agora |
|---|---|---|
| 9router | "ou modo duas faixas" (a decidir no spike) | **Obrigatório. Faixa 1 apenas**: só chaves de API (OpenRouter, DeepSeek, Featherless). Assinaturas ficam fora, nos CLIs oficiais |
| `/novo-projeto` | etapa 6 | **Obrigatório**, logo depois do 9router |
| Por quê duas faixas | risco aceito | O spike de 2026-10-18 achou termos restritivos da Anthropic para rotear assinatura por gateway de terceiros, 8 CVEs em 2026 e roteamento de conta automático (não dá escolher conta por requisição). Chave de API não tem nenhum desses problemas |
| Script | `24-modelos.sh` "vira" `24-9router.sh` | `24-modelos.sh` **fica** (é o perfil `codex -p openrouter`, outra coisa); o 9router ganha o script novo `41-9router.sh` (40 é o último do CI) |
| Registro do projeto no PMO | "registra no PMO" | O PMO já descobre projetos pelos repositórios do GitHub e lê o `STATE.md` (`pmo/github.py`, `pmo/regras.py`). Não há registro separado: o `/novo-projeto` escreve um `STATE.md` válido e, com confirmação própria, cria o repositório privado |

## 1. 9router, faixa 1

- **Instalação:** `npm install -g --prefix ~/.local 9router@0.5.104` como `agente` (versão fixa no script; atualizar é trocar
  a constante e rodar de novo). Nunca `latest`.
- **Serviço:** unidade de usuário `9router.service` (padrão do `opencode-web.service`), `PORT=20128`,
  `EnvironmentFile=%h/.config/9router/9router.env` (0600, criado pelo dono, o script só valida e nunca imprime).
  O binário `9router` é um lançador interativo: o `--host` do lançador (padrão `0.0.0.0`) vence o `HOSTNAME` do ambiente e,
  sem TTY, o menu devolve -1 e o processo sai com 0. Por isso o `ExecStart` é
  `9router --host 127.0.0.1 --port 20128 --no-browser --skip-update` (com `--skip-update` e sem TTY ele entra em modo
  bandeja e fica vivo). **Efeito colateral:** a cada start o lançador dá `kill -9` em processos do usuário `agente` cujo
  `ps aux` contenha `next-server`; um `next dev` do agente morre quando o 9router (re)inicia.
  O script **recusa subir** sem `INITIAL_PASSWORD` (≥ 16 caracteres, diferente de `123456`) e sem `JWT_SECRET`.
  A exigência de chave de API **não** é variável de ambiente (`REQUIRE_API_KEY` não existe na 0.5.104): vem de
  `settings.requireApiKey` no banco (padrão `true`, desligável no painel). Quem vigia é o `health.sh` (abaixo).
- **Dados:** `DATA_DIR=%h/.9router` (0700). Tratar `data.sqlite` e `jwt-secret` como segredo (0600), dentro do backup.
- **Tailnet:** painel do 9router só na tailnet, `tailscale serve --https=20128 http://127.0.0.1:20128` no `37-tailscale-serve.sh`.
- **Chave de API:** criada no painel do 9router; guardada em `~/.config/9router/client.env` (0600,
  `NINE_ROUTER_API_KEY=...`, lido pelo drop-in do `opencode-web` via `EnvironmentFile=-`) para o OpenCode e em
  `/srv/dev/secrets/agente.env` para o `bin/modelo`. O `36-opencode.sh` recusa o `client.env` fora de 0600 ou de outro dono.
  O provedor entra com `"models": {}`: o seletor do OpenCode fica vazio até o dono acrescentar os modelos do 9router.
- **Consumidores:** OpenCode (provedor `@ai-sdk/openai-compatible`, `baseURL http://127.0.0.1:20128/v1`, chave
  `{env:NINE_ROUTER_API_KEY}`), `bin/modelo` (novo provedor `9router`) e, depois, projetos de template `agente`.
  O modelo padrão do OpenCode **não** é escolhido por este spec (decisão do Ricardo).
- **Faixa 2 (fora do 9router):** `claude`, `codex` e `agy` com login próprio no `agente`; as duas assinaturas Claude em
  pastas de configuração separadas (`CLAUDE_CONFIG_DIR`). Nada disso passa pelo 9router.
- **Saúde:** `bin/health.sh` ganha a seção `9router` (unidade instalada → só HTTP, decidido: `GET /api/health` em
  `127.0.0.1:20128` deve dar 200, pois `GET /` responde 307 para `/dashboard`; e `POST /v1/chat/completions` **sem chave** deve dar 401 (`GET /v1/models` é público),
  senão `FALHA 9router sem exigir chave de API`; sem unidade, nada é impresso).
- **Falha:** 9router fora do ar não impede o trabalho: o OpenCode ainda usa os provedores diretos que já tem.
- **Risco aceito:** 8 CVEs em 2026; mitigação é versão fixa, só `127.0.0.1`/tailnet, chave de API exigida (checada pelo health),
  senha forte. O painel tem túnel cloudflared embutido com `tunnelDashboardAccess` true por padrão: desligar no spike.
  O `ensureSqliteRuntime` pode rodar `npm` no boot.
- **Na VPS (sempre com aprovação):** spike curto antes de ligar — conferir `requireApiKey` no painel, desligar o túnel
  embutido (`tunnelDashboardAccess`), onde ficam os tokens e a permissão deles, se a senha forte
  funciona sem a trava de troca, se o endpoint `/v1/chat/completions` responde com a chave de API.

## 2. `/novo-projeto`

- **Comando do OpenCode** `opencode/command/novo-projeto.md`, provisionado em `~/.config/opencode/command/` pelo
  `36-opencode.sh`. Conduz a skill `project-bootstrap` (natureza → poucas perguntas → prévia → confirmação).
- **Gerador:** `scripts/42-novo-projeto.py <pasta> --natureza sistema|agente|parecer --nome <slug> --destino <perfil> [--destino ...] [--apply]` (`--destino` obrigatório, pelo menos um).
  Sem `--apply` só mostra a prévia (como o `35-projeto-standards.py`). Recusa pasta que exista e não esteja vazia. Copia
  `templates/<natureza>/` (não gera por IA), troca os marcadores `{{nome}}`/`{{destino}}`, escreve `STATE.md` válido
  (`tipo`, `estágio: ideia`, `próximo passo`) e chama o `35-projeto-standards.py` para o `.standards.json`.
  Criar o repositório privado no GitHub **não** é feito pelo gerador: é uma confirmação separada do comando.
- **Templates:** `sistema` (Hono + TypeScript, `skills/ness-design`, um arquivo de deploy por destino:
  `wrangler.jsonc`, `vercel.json`, `Dockerfile` para Cloud Run, `Dockerfile` + `config/deploy.yml` do Kamal), `agente`
  (TypeScript, 9router via `NINE_ROUTER_API_KEY`, `promptfoo` com `casos/` e um caso que passa), `parecer` (Markdown → Typst →
  PDF/DOCX, `fontes.md` com citação verificada/não verificada; **conteúdo fora do Git**, em `/srv/dev/pareceres/<nome>`).
- **Padrões:** `ci: local-vps`; nenhum template cria GitHub Actions, chave ou deploy. `@ness/auth` é opcional e entra depois
  (etapa 5); o template `sistema` deixa só o ponto de extensão documentado.
- **`standards/profiles.json`:** remove `azure`; `local` vira `fora-das-nuvens` (guidance: qualquer máquina com SSH e Docker,
  deploy e rollback pelo Kamal). O `35-projeto-standards.py`, seu teste, a skill e `standards/README.md` acompanham.
- **Fora do escopo desta rodada:** `@ness/auth`, SSO, Authentik; criar repositório no GitHub automaticamente.

## 3. Testes

Cada artefato novo tem teste no `tests/run.sh` (WSL): scripts da VPS por stubs (`STACK_TESTE=1`, padrão do repositório);
cada template é gerado numa pasta temporária e validado (arquivos esperados, marcadores todos trocados, `STATE.md` aceito por
`pmo.regras`, nenhum segredo). Build/test do projeto gerado entra onde a ferramenta existe no ambiente de teste; onde não existir,
o teste verifica a estrutura e diz isso na saída.

## 4. Ordem

1. 9router (script, unidade, OpenCode, `modelo`, health, serve) — código local, sem VPS.
2. `/novo-projeto` (profiles, gerador, comando, 3 templates) — código local.
3. Instalação na VPS (9router depois do spike; comando no OpenCode) — passo a passo, com aprovação.
