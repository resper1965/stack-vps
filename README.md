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

`sudo -u agente -H bash -c 'cd ~ && /opt/stack-vps/scripts/NN-….sh'` (a partir do home do agente: ele não lê a pasta do `dev`)

| # | Script | O que faz |
|---|---|---|
| 24 | `24-modelos.sh` | `codex -p openrouter [-m fornecedor/modelo]` pelo OpenRouter; `codex` sem `-p` segue no ChatGPT Pro |
| 25 | `25-testes.sh` | valida o Postgres descartável (`/srv/dev/bin/postgres.yml`, em memória, só `127.0.0.1`) |
| 26 | (aposentado) | atalhos `/srv/dev/verticais/<empresa>/<área>/<projeto>` agora saem da classificação feita no painel do PMO (executor → `pmo-pasta verticais`) |
| 27 | `27-secrets.sh` | carrega `secrets/projetos.env` (um arquivo para todos os projetos) no shell do agente |
| 28 | `28-contas-claude.sh` | duas contas Claude: bekaa (`~/.claude`, padrão) e ionic (`~/.claude-ionic`, vertical ionic); `claude-bekaa`/`claude-ionic` forçam |
| 29 | `29-skills.sh` | skills de Cloudflare, Supabase, Vercel e GitHub nos três agentes; ponytail em `full` por padrão |
| 36 | `36-opencode.sh` | unidade `opencode-web` (OpenCode só em `127.0.0.1:4096`); exige `~/.config/opencode/web.env` 0600 com `OPENCODE_SERVER_PASSWORD`, criado por você — não instala o OpenCode |

Notas:

- Featherless não entra no Codex: ele só fala a Responses API, que ela não tem.
- A extensão do Claude no VS Code usa sempre a conta padrão (bekaa); para ionic, `claude` no terminal.
- `agy`: login headless copiando `~/.gemini/antigravity-cli/antigravity-oauth-token` de uma máquina já logada.

## PMO (como root, depois da base)

| # | Script | O que faz |
|---|---|---|
| 34 | `34-pmo.sh` | painel do PMO em `https://stack.<tailnet>.ts.net:8443` (só tailnet; precisa do 37; nos computadores com o cliente Tailscale (MagicDNS ligado por padrão) abre pelo nome, ver `docs/ssh-config.md`): coleta diária, alarme de esquecidos, descartar/restaurar |
| 37 | `37-tailscale-serve.sh` | publica na tailnet (`tailscale serve`, em segundo plano): OpenCode em `https://stack.<tailnet>.ts.net` e PMO em `:8443`; rode depois do 34 e do 36; exige "HTTPS Certificates" habilitado no admin da tailnet |
| 38 | `38-ci-conta.sh` | conta comum `ci` (home `/srv/ci`, Docker rootless próprio, sem sudo) que será dona dos runners; ainda não instalado na VPS |
| 39 | `39-ci-rede.sh` | isola a conta `ci` da tailnet e do metadata da nuvem (iptables por UID; `--instalar`, `--remover`, `--status`); ainda não instalado na VPS |
| 40 | `40-ci-runners.sh` | supervisor de runners efêmeros do GitHub para organizações (`ci/runners.py`); só habilita com `--habilitar` e com o 39 ativo; ainda não instalado na VPS |


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
