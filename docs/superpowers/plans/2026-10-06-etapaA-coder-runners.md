# Etapa A — Coder Community, sysbox e runners próprios

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Coder Community em `https://coder.ness.com.br` com login GitHub fechado, workspaces `web` em containers sysbox isolados do host e da tailnet, e runners efêmeros do GitHub Actions na VPS.

**Architecture:** Coder (container) + Postgres em `/srv/coder`, publicado só em `127.0.0.1:7080` e exposto pelo tunnel `stack-vps`. Workspaces e runners são containers do Docker do sistema com runtime `sysbox-runc`. Regras na cadeia `DOCKER-USER` impedem containers de alcançar a tailnet e o metadata da nuvem; o UFW já nega containers → host.

**Tech Stack:** Docker 29, sysbox-ce 0.7.1, Coder (imagem `ghcr.io/coder/coder`), PostgreSQL 17, Terraform (embutido no Coder), cloudflared.

**Spec:** `docs/superpowers/specs/2026-10-06-equipe-coder-runners-design.md`

## Global Constraints

- Coder Community, sem licença; cadastro **fechado** (`CODER_OAUTH2_GITHUB_ALLOW_SIGNUPS=false`); usuários criados pelo admin com `--login-type github`.
- Coder publicado só em `127.0.0.1:7080`; acesso externo só pelo tunnel.
- Workspaces e runners com `runtime = sysbox-runc`, nunca `privileged`; nunca montam o `docker.sock` do host.
- Runners: só repositórios **privados**; efêmeros; rótulo `stack`.
- Segredos de infra (OAuth do GitHub, token de runner) em `admin.env`.
- Scripts novos numerados a partir de 30, como root, idempotentes.

## Desvios do spec (rulings, com o porquê)

1. **Sem Cloudflare Access na frente do Coder** — a extensão do VS Code e o `coder ssh` usam a API e não passam pelo login interativo do Access. Controle de entrada: login GitHub com cadastro fechado.
2. **Sem wildcard de apps (`*.coder.ness.com.br`) nesta etapa** — o certificado universal da Cloudflare cobre um nível só; portas abrem pelo VS Code/`coder port-forward`. Reavaliar com Total TLS ou wildcard de primeiro nível.

---

### Task 1: sysbox (`30-sysbox.sh`)
- Baixa `sysbox-ce_0.7.1.linux_amd64.deb` de `https://downloads.nestybox.com/sysbox/releases/v0.7.1/`, confere o SHA-256 `9d6d5484f980d0a17f86c492c1262015c2afb66280bdb97215b79fde6a0261c5`, instala com `apt-get install ./…deb` (o pacote reinicia o Docker; rodar antes de existir container).
- Prova: `docker run --rm --runtime=sysbox-runc alpine id` → `uid=0(root)`; `systemctl is-active sysbox` → `active`.

### Task 2: isolamento de rede dos containers (`31-rede-containers.sh` + unidade systemd)
- `DOCKER-USER`: `-d 100.64.0.0/10 -j DROP` (tailnet), `-d 169.254.169.254 -j DROP` (metadata), antes do `RETURN`; reaplicado por `stack-rede-containers.service` (`After=docker.service`).
- Prova: de um container, `nc -zw3 100.76.167.6 22` e `nc -zw3 172.17.0.1 22` falham; `curl -sI https://github.com` passa.

### Task 3: Coder (`32-coder.sh`, `compose/coder.yml`)
- `compose/coder.yml`: `postgres:17` (volume `/srv/coder/postgres`) e `ghcr.io/coder/coder:latest` com `CODER_ACCESS_URL=https://coder.ness.com.br`, `CODER_HTTP_ADDRESS=0.0.0.0:7080`, `CODER_PG_CONNECTION_URL`, `CODER_OAUTH2_GITHUB_*` lidos de `/srv/coder/coder.env` (600 root, gerado do `admin.env`), porta `127.0.0.1:7080:7080`, `/var/run/docker.sock` montado só no servidor do Coder.
- `32-coder.sh`: gera `/srv/coder/coder.env` (senha do Postgres aleatória na primeira vez), sobe o compose, espera `/healthz`.
- Prova: `curl -s 127.0.0.1:7080/healthz` → `OK`.

### Task 4: tunnel para `coder.ness.com.br`
- `06-tunnel.sh` passa a aceitar hostnames extras em `TUNNEL_EXTRA` (`coder.ness.com.br=http://localhost:7080`) e cria o CNAME proxied na zona do host.
- **Gate (R):** criação do DNS na zona `ness.com.br` — confirmar com o Ricardo.
- Prova: `curl -sI https://coder.ness.com.br/healthz` → `200`.

### Task 5: OAuth do GitHub e primeiro usuário
- **Gate (R):** o Ricardo cria o OAuth App (Settings → Developer settings → OAuth Apps → New): Homepage `https://coder.ness.com.br`, callback `https://coder.ness.com.br/api/v2/users/oauth2/github/callback`; grava `CODER_GITHUB_CLIENT_ID`/`CODER_GITHUB_CLIENT_SECRET` no `admin.env`.
- Primeiro admin: `coder login` com o primeiro usuário (criado na tela inicial), depois `coder users create --login-type github` para o Ricardo.

### Task 6: modelo `web` (`coder/templates/web/`)
- `Dockerfile` (Ubuntu 24.04): mise + Node 24, npm, git, gh, Docker interno (dockerd, funciona com sysbox), Chromium; Claude Code, Codex e Antigravity instalados na imagem.
- `main.tf`: provider docker, `runtime = "sysbox-runc"`, limite 4 vCPU / 6 GB, volume do home por workspace, volume **por pessoa** montado em `~/.claude`, `~/.claude-ionic`, `~/.codex`, `~/.gemini`; módulos `code-server` e `vscode-desktop` do registro do Coder; `coder_agent` com desligamento por ociosidade de 2 h.
- Prova: workspace de teste do Ricardo sobe, `docker run hello-world` dentro dele funciona, `claude --version` responde, e o isolamento da Task 2 vale dentro dele.

### Task 7: runners efêmeros (`33-runners.sh`)
- **Gate (R):** token com `admin:org` (ou `manage_runners:org`) para as organizações; o Ricardo confirma quais organizações e repositórios privados de `resper1965`.
- Contêineres `myoung34/github-runner` com `EPHEMERAL=1`, `RUNNER_SCOPE=org`, `LABELS=stack`, `runtime: sysbox-runc`, `restart: always`, 3 por organização no máximo.
- Prova: workflow de teste num repositório privado com `runs-on: [self-hosted, stack]` passa e o container é recriado depois do job.

### Task 8: docs e PR
- `README.md` (scripts 30–33), `docs/srv-dev-README.md` (Coder: entrada, admin, modelos), ledger; PR `feat/coder-runners` → `main`.
