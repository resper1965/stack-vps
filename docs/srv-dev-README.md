# /srv/dev

Ambiente unico de desenvolvimento. Todo projeto vive aqui; o laptop e so terminal.

## Arvore

```
/srv/dev/
├── repos/{apps,orm,agents,infra}   clones Git — a verdade e o remoto
├── data/                           volumes e datasets — NUNCA versionado; 750, o agente nao entra
├── state/reviews/                  inventario e pareceres escritos pelos agentes
├── secrets/{admin.env,agente.env,projetos/}   segredos em niveis (ver Agentes)
├── skills/                         skills de ambiente (cloudflare-ness)
└── bin/                            health.sh, playwright.yml
```

## Acesso

`ssh stack` pela tailnet (principal), `ssh stack-cf` pelo Cloudflare Tunnel (reserva), console do
hPanel em emergência. Nenhuma porta responde no IP público. Configuração do laptop em
`ssh-config.md`.

## Recuperar do zero

Fora da VPS, antes de começar: as três chaves do backup (`R2_ACCESS_KEY_ID`, `R2_SECRET_ACCESS_KEY`,
`RESTIC_PASSWORD`) no gerenciador de senhas e o nó antigo `stack` removido do painel do Tailscale.

Numa VPS Ubuntu 24.04 recém-criada, como root pelo IP:

```sh
git clone https://github.com/resper1965/stack-vps /tmp/stack-vps && cd /tmp/stack-vps
./scripts/01-baseline.sh "<chave-publica-ed25519>"
#   sem TS_AUTHKEY o 01b para pedindo a chave: rode "tailscale up --hostname=stack",
#   abra o link de login e rode o 01 de novo. No painel do Tailscale: desative a
#   expiração de chave do nó e fixe o IPv4 em 100.76.167.6 (Edit machine IPv4).
#   Daqui em diante: ssh stack
./scripts/02-layout.sh
mv /tmp/stack-vps /srv/dev/repos/infra/stack-vps && chown -R dev:dev /srv/dev/repos/infra/stack-vps
cd /srv/dev/repos/infra/stack-vps
./scripts/03-tooling.sh
./scripts/05-servicos.sh
export CLOUDFLARE_ACCOUNT_ID=<id da conta>
read -rsp "R2_ACCESS_KEY_ID: " R2_ACCESS_KEY_ID; echo
read -rsp "R2_SECRET_ACCESS_KEY: " R2_SECRET_ACCESS_KEY; echo
read -rsp "RESTIC_PASSWORD: " RESTIC_PASSWORD; echo
export R2_ACCESS_KEY_ID R2_SECRET_ACCESS_KEY RESTIC_PASSWORD
sudo --preserve-env=CLOUDFLARE_ACCOUNT_ID,R2_ACCESS_KEY_ID,R2_SECRET_ACCESS_KEY,RESTIC_PASSWORD ./scripts/15-restore.sh
./scripts/06-tunnel.sh <e-mail-da-politica>
./scripts/07-firewall.sh
./scripts/16-agente.sh
sudo -u agente -H ./scripts/04-agents.sh                # depois: ia e iax, login de cada um
sudo -u dev ./scripts/09-clonar-escopo.sh /srv/dev/state/escopo-auditoria.tsv
/srv/dev/bin/health.sh
```

## Backup

`stack-backup.timer` roda `/usr/local/lib/stack-vps/14-backup.sh` todo dia às 03:00 de Brasília:
restic no bucket R2 `stack-vps-backup`, retenção 7 diários / 4 semanais / 6 mensais, verificação
de 5% dos dados aos domingos. O `health.sh` acusa se o último backup tiver mais de 36h.

## Agentes

Claude Code e Codex rodam como o usuario `agente`, nunca como `dev`. Do terminal do `dev`:
`ia` abre o Claude e `iax` o Codex, no diretorio atual.

| | `dev` | `agente` |
|---|---|---|
| sudo | sim | nao |
| Docker | do sistema | rootless proprio |
| `repos/`, `state/` | escrita | escrita (grupo `devs`) |
| `data/`, `/srv/forense` | sim | nao |
| segredos | `admin.env` | `agente.env` e `projetos/<p>.env` (via `.envrc` + direnv) |

`/srv/dev/secrets/admin.env` (600 dev) guarda o que so humano usa: Cloudflare com escrita,
Hostinger, R2, restic e canais de alerta.

## Alertas

`stack-health.timer` roda o `health.sh` de hora em hora e, so quando o estado muda, avisa por
ntfy (`NTFY_TOPIC`), e-mail (`RESEND_API_KEY`) e Telegram (`TELEGRAM_BOT_TOKEN`, `TELEGRAM_CHAT_ID`),
configurados no `admin.env`. Canal sem valor e pulado. Teste manual:
`sudo /usr/local/lib/stack-vps/alertar.sh "teste" "mensagem"`.

## Regras que valem para os agentes

- `data/` esta fora do escopo: nao ler, nao escrever.
- Escrita livre so em `state/` e em branch nova (`chore/...`). Nada de push em `main`.
- Segredo vem de `secrets/.env` via ambiente do shell, nunca do bloco `env` de `settings.json`.
- API da Hostinger e gateway Composio: leitura livre; qualquer chamada que altere estado para e pergunta antes.
- Docker publica porta só em `127.0.0.1` ou no IP da tailnet (`-p 127.0.0.1:3000:3000`): porta publicada ignora o UFW.
