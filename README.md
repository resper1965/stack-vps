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

Roteiro completo em `docs/srv-dev-README.md`; acesso do laptop em `docs/ssh-config.md`.
Testes: `bash tests/run.sh` (precisa de `shellcheck`).

## Convenção

Todo script é idempotente: rodar de novo não quebra o que já existe.
Nada de segredo aqui — segredo vive em `/srv/dev/secrets/.env` (modo 600) na VPS; os nomes estão em `.env.example`.
