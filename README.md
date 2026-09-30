# stack-vps

Provisionamento da VPS de desenvolvimento (Hostinger KVM 8, Ubuntu 24.04 + Docker).
Fonte da verdade do ambiente: recriar a VPS é rodar os scripts desta pasta na ordem.

## Ordem

```sh
sudo ./scripts/01-baseline.sh "<chave-publica-ed25519>"
sudo ./scripts/02-layout.sh
```

Etapas seguintes (tunnel, firewall, tooling, agentes) entram conforme validadas.

## OpenRig (opcional)

`scripts/14-openrig.sh`, como `dev`, depois do `04-agents.sh`. Instala o
[OpenRig](https://github.com/mvschwarz/openrig) e o comando `rig-dupla`, que sobe principal e
revisor do projeto com os papéis do `STATE.md`. O revisor grava o parecer em `state/reviews`,
que a rotina semanal já lê. O `04-agents.sh` libera a escrita dos agentes em `/srv/dev/state`.
Como funciona, com diagramas: [`docs/openrig.md`](docs/openrig.md).

Desvios do padrão do OpenRig, para não colidir com o `CLAUDE.md` e o `04-agents.sh`:

- estado em `/srv/dev/state/openrig`, e não em `~/.openrig`;
- kernel desligado (`OPENRIG_NO_KERNEL=1`), porque ele sobe agentes próprios com a config padrão;
- hooks do Codex desligados: o daemon não reescreve `~/.codex/config.toml`
  (em troca, o painel do OpenRig não mostra a atividade de seat em Codex);
- os perfis não recebem `acceptEdits` via settings nem os MCPs Exa/Context7.

O que continua valendo: o seat Claude é lançado com `--permission-mode acceptEdits`
(postura `floor` do OpenRig), o Codex com `-s workspace-write`, e o daemon grava
confiança do workspace em `~/.claude.json` e a skill `openrig-skills` em `~/.claude/skills`.
Requer Node 22 ou 24; o `03-tooling.sh` fixa `node@24`.

## Convencao

Todo script e idempotente: rodar de novo nao quebra o que ja existe.
Nada de segredo aqui — segredo vive em `/srv/dev/secrets/.env` (modo 600) na VPS.

## Modelos extras e banco de teste

- `scripts/16-modelos.sh` (como `dev`): `codex -p openrouter [-m fornecedor/modelo]` usa o OpenRouter;
  `codex` sem `-p` segue na assinatura ChatGPT Pro. Chave `OPENROUTER_API_KEY` em `secrets/.env`,
  lida só na chamada. Featherless não entra: o Codex só fala a Responses API, que ela não tem.
- `scripts/17-testes.sh` (como `dev`): instala `compose/postgres.yml` em `/srv/dev/bin`.
  Postgres descartável, em memória, só em `127.0.0.1`. Regra de uso no `CLAUDE.md` §8.

## Verticais e secrets

- `scripts/18-verticais.sh` (como `dev`): lê `docs/verticais.tsv` e monta
  `/srv/dev/verticais/<vertical>/<divisão>/<projeto>` como atalho para o clone, mais um
  `<vertical>.code-workspace` para abrir a vertical inteira no VS Code. Os clones não saem do lugar.
  Verticais: pessoal, ness, ionic, bekaa, forense. Divisões: app, agents, knowledge, e ainda
  orm (pessoal, bekaa) ou compliance (ness, ionic, forense), e cases (forense).
- `scripts/19-secrets.sh` (como `dev`): `secrets/projetos.env` é um arquivo só, compartilhado por
  todos os projetos, carregado em todo shell do `dev`. Tokens de infra seguem em `secrets/.env`.

## Duas contas Claude

`scripts/20-contas-claude.sh` (como `dev`): conta bekaa em `~/.claude` (padrão) e conta ionic em
`~/.claude-ionic`, com os mesmos plugins, skills e settings. `claude` num projeto da vertical ionic
usa a conta ionic sozinho; `claude-bekaa` e `claude-ionic` forçam. A extensão do VS Code ignora
`CLAUDE_CONFIG_DIR` e usa sempre a bekaa: para ionic, rode `claude` no terminal do VS Code.

## Skills e modos padrão

Três harnesses de agente, todos no usuário `dev`: Claude Code, Codex e Antigravity CLI (`agy`, que o
`04` instala; login headless copiando `~/.gemini/antigravity-cli/antigravity-oauth-token` de uma máquina
já logada). superpowers e ponytail vêm do `04` nos três.

`scripts/21-skills.sh` (como `dev`, depois do `04` e do `20`): skills oficiais de Cloudflare, Supabase,
Vercel e GitHub (`awesome-copilot`: issues, release, actions) nos três, via `npx skills@1.7.0`.
ponytail fica em `full` por padrão: no Claude por plugin com hook, no Codex por instrução em
`~/.codex/AGENTS.md`, no `agy` por regra `always_on` em `~/.gemini/config/rules/`.
Nível: `~/.config/ponytail/config.json`; na sessão, `/ponytail off`.
O OpenRig só conhece Claude Code e Codex: o `agy` fica fora do `rig-dupla`.
