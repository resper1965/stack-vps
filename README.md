# stack-vps

Provisionamento da VPS de desenvolvimento (Hostinger KVM 8, Ubuntu 24.04).
Fonte da verdade do ambiente: recriar a VPS é rodar os scripts desta pasta na ordem e devolver os segredos.

## Base (VPS recém-formatada, como root)

| # | Script | O que faz |
|---|---|---|
| 01 | `TS_AUTHKEY=… ./scripts/01-baseline.sh "<chave-ed25519>"` | hostname, usuário dev, sshd, fail2ban, Tailscale (`01b`) |
| 02 | `./scripts/02-layout.sh` | árvore `/srv/dev`, segredos em níveis (`admin.env`, `agente.env`, `projetos.env`) |
| 03 | `./scripts/03-tooling.sh` | ferramentas, Docker, cloudflared, Node 24 via mise |
| 05 | `./scripts/05-servicos.sh` | tmux, scripts de rotina, `postgres.yml`, timers de health (e de backup, se houver chave R2) |
| 15 | `./scripts/15-restore.sh` | restore do restic (quando o backup estiver ligado) |
| 06 | `./scripts/06-tunnel.sh <e-mail>` | Cloudflare Tunnel de reserva (`ssh stack-cf`) |
| 07 | `./scripts/07-firewall.sh` | UFW: 22 só pela tailnet, UDP do Tailscale |
| 16 | `./scripts/16-agente.sh` | usuário `agente` (estação de trabalho), Docker rootless, `ia`/`iax`, rotina semanal |
| 04 | `sudo -u agente -H ./scripts/04-agents.sh` | Claude Code, Codex, Antigravity CLI (`agy`), plugins, MCP |
| 09 | `sudo -u agente -H ./scripts/09-clonar-escopo.sh /srv/dev/state/escopo-auditoria.tsv` | clones do escopo |

Rode sempre de um clone com dono root (`/opt/stack-vps`), nunca do clone de trabalho em `repos/`.
Roteiro completo em `docs/srv-dev-README.md`; acesso do laptop em `docs/ssh-config.md`.
Testes: `bash tests/run.sh` (precisa de `shellcheck`).

## Scripts de trabalho (como `agente`, depois do 04)

`sudo -u agente -H /opt/stack-vps/scripts/NN-….sh`

| # | Script | O que faz |
|---|---|---|
| 22 | `22-openrig.sh` | [OpenRig](https://github.com/mvschwarz/openrig) e o comando `rig-dupla` (principal + revisor do `STATE.md`) — ver [`docs/openrig.md`](docs/openrig.md) |
| 23 | `23-papeis.sh [--push]` | preenche principal/revisor nos `STATE.md` (Claude Code principal, Codex revisor); commita em `chore/…` |
| 24 | `24-modelos.sh` | `codex -p openrouter [-m fornecedor/modelo]` pelo OpenRouter; `codex` sem `-p` segue no ChatGPT Pro |
| 25 | `25-testes.sh` | valida o Postgres descartável (`/srv/dev/bin/postgres.yml`, em memória, só `127.0.0.1`) |
| 26 | `26-verticais.sh` | atalhos `/srv/dev/verticais/<vertical>/<divisão>/<projeto>` e um `.code-workspace` por vertical (mapa em `docs/verticais.tsv`) |
| 27 | `27-secrets.sh` | carrega `secrets/projetos.env` (um arquivo para todos os projetos) no shell do agente |
| 28 | `28-contas-claude.sh` | duas contas Claude: bekaa (`~/.claude`, padrão) e ionic (`~/.claude-ionic`, vertical ionic); `claude-bekaa`/`claude-ionic` forçam |
| 29 | `29-skills.sh` | skills de Cloudflare, Supabase, Vercel e GitHub nos três agentes; ponytail em `full` por padrão |

Notas:

- OpenRig: estado em `/srv/dev/state/openrig`, kernel desligado, hooks do Codex desligados; requer Node 22 ou 24
  (por isso o `03` fixa `node@24`). Só conhece Claude Code e Codex: o `agy` fica fora do `rig-dupla`.
- Featherless não entra no Codex: ele só fala a Responses API, que ela não tem.
- A extensão do Claude no VS Code usa sempre a conta padrão (bekaa); para ionic, `claude` no terminal.
- `agy`: login headless copiando `~/.gemini/antigravity-cli/antigravity-oauth-token` de uma máquina já logada.

## Outros

| Script | O que faz |
|---|---|
| `14-backup.sh` / `15-restore.sh` | backup restic no R2 (desligado até a decisão pós-migração) |
| `20-laptop-github.sh` | envia o trabalho do laptop ao GitHub, com bloqueio de segredo e documento de cliente (roda no WSL) |
| `alertar.sh`, `vigia-health.sh` | alertas por ntfy, e-mail e Telegram na mudança de estado do `health.sh` |

## Convenção

Todo script é idempotente: rodar de novo não quebra o que já existe.
Nada de segredo aqui — segredo vive em `/srv/dev/secrets/` na VPS; os nomes estão em `admin.env.example`
e `agente.env.example`.
