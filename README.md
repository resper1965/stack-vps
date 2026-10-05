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
| 15 | `./scripts/15-restore.sh` | segredos, credencial do tunnel, `state/`, `data/`, `forense/`, config dos agentes |
| 06 | `./scripts/06-tunnel.sh <e-mail>` | Cloudflare Tunnel de reserva (`ssh stack-cf`) |
| 07 | `./scripts/07-firewall.sh` | UFW: 22 só pela tailnet |
| 16 | `./scripts/16-agente.sh` | usuário `agente` sem sudo, Docker rootless, `ia`/`iax` |
| 04 | `sudo -u agente -H ./scripts/04-agents.sh` | Claude Code, Codex, plugins, MCP (no `agente`) |
| 09 | `sudo -u agente -H ./scripts/09-clonar-escopo.sh /srv/dev/state/escopo-auditoria.tsv` | clones do escopo (dono: agente) |

Rode sempre de um clone com dono root (`/opt/stack-vps`), nunca do clone de trabalho em `repos/`.
Roteiro completo em `docs/srv-dev-README.md`; acesso do laptop em `docs/ssh-config.md`.
Testes: `bash tests/run.sh` (precisa de `shellcheck`).

## Convenção

Todo script é idempotente: rodar de novo não quebra o que já existe.
Nada de segredo aqui — segredo vive em `/srv/dev/secrets/` na VPS; os nomes estão em `admin.env.example` e `agente.env.example`.
