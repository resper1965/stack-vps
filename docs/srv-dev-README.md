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
mv /tmp/stack-vps /opt/stack-vps && chown -R root:root /opt/stack-vps   # clone de provisionamento, fora do alcance do agente
cd /opt/stack-vps
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
sudo -u agente -H ./scripts/09-clonar-escopo.sh /srv/dev/state/escopo-auditoria.tsv
/srv/dev/bin/health.sh
```

## Backup

`stack-backup.timer` roda `/usr/local/lib/stack-vps/14-backup.sh` todo dia às 03:00 de Brasília:
restic no bucket R2 `stack-vps-backup`, retenção 7 diários / 4 semanais / 6 mensais, verificação
de 5% dos dados aos domingos. O `health.sh` acusa se o último backup tiver mais de 36h.

## Agentes e papéis

Dois usuários, papéis separados:

| | `agente` — estação de trabalho | `dev` — administração |
|---|---|---|
| Quem usa | o Ricardo e os agentes (Claude Code, Codex) | o Ricardo, só para administrar |
| Conexão | `ssh stack-agente` (VS Code aqui) | `ssh stack` |
| sudo | não | sim |
| Docker | rootless próprio | do sistema |
| `repos/`, `state/` | dono | não roda git ali (o git recusa repositório de outro dono) |
| `data/`, `/srv/forense` | sem acesso | sim |
| Segredos | `agente.env`, `projetos/<p>.env` (via `.envrc` + `direnv allow`) | `admin.env` |
| Rotina semanal | crontab do agente | — |

Por que separado: se o `dev` rodasse git num repositório onde o agente escreve, um hook ou um
`.git/config` deixado pelo agente rodaria como `dev` — e o `dev` tem sudo.

Provisionamento (`sudo ./scripts/NN.sh`) roda de um clone do `stack-vps` que o agente não alcança
(`/opt/stack-vps`, dono root), nunca do clone de trabalho em `repos/infra/`.

Do terminal do `dev`, `ia` e `iax` abrem o Claude e o Codex como `agente` no diretório atual.

## Painel do PMO

`https://stack.<tailnet>.ts.net:8443` (só pela tailnet; o `tailscale serve` leva ao socket Unix do PMO). Mostra todos os repositórios dos donos em `pmo/donos.txt`,
descobertos sozinhos todo dia às 06:00 (Brasília), mais as pastas sem git de `/srv/dev/laptop` em
"A destinar".

- **Esquecido**: `em andamento` sem atividade há 14 dias, `em revisão` há 30, ou estágio declarado sem
  próximo passo. Resumo toda segunda às 08:00 (ntfy e e-mail).
- **Tipo e estágio** vêm do `STATE.md` (`**Tipo:**`, `**Estágio:**`, `**Próximo passo:**`); sem eles, o
  painel mostra o estágio sugerido com `~`.
- **Ações**: Arquivar (reversível, Restaurar desfaz), Excluir de vez (digitar o nome; o GitHub guarda
  90 dias, a cópia local 30), Trazer/Descartar para "A destinar", Reanalisar. Repositórios `nessenergy`
  só arquivam. Tudo registrado em `/srv/dev/state/pmo/acoes.log`.
- Excluir no GitHub exige `delete_repo` no token do `admin.env`.

## Alertas

`stack-health.timer` roda o `health.sh` de hora em hora e, so quando o estado muda, avisa por
ntfy (`NTFY_TOPIC`), e-mail (`RESEND_API_KEY`) e Telegram (`TELEGRAM_BOT_TOKEN`, `TELEGRAM_CHAT_ID`),
configurados no `admin.env`. Canal sem valor e pulado. O `health.sh` tem uma seção do 9router, que só aparece se a unidade existir. Teste manual:
`sudo /usr/local/lib/stack-vps/alertar.sh "teste" "mensagem"`.

## Antes de cada deploy de etapa

```sh
sudo bash /opt/stack-vps/bin/hostinger.sh metricas        # confere a credencial, só leitura
sudo bash /opt/stack-vps/bin/hostinger.sh snapshot --sim
```

O `hostinger.sh` só é instalado em `/usr/local/bin` pelo `05-servicos.sh`, que roda depois: no primeiro deploy
chame-o pelo caminho do clone (`/opt/stack-vps/bin/`) e **antes de qualquer script do deploy**. A Hostinger
guarda UM snapshot por VM: o novo substitui o existente (o comando mostra a data do atual antes de criar).
Sem `--sim`, só mostra o que faria. Credenciais (`HOSTINGER_API_TOKEN`, `HOSTINGER_VM_ID`) no `admin.env`.

### Chaves do `admin.env` usadas pelo PMO

| Chave | Obrigatória | Formato e uso |
|---|---|---|
| `GITHUB_TOKEN` | sim | token com `delete_repo`; o `34-pmo.sh` o grava em `/etc/pmo/token` |
| `PMO_HOSTS` | sim | `stack.<tailnet>.ts.net:8443,localhost:8080`: `Host` aceito, **com a porta**; o primeiro vira a URL do resumo semanal |
| `PMO_LOGINS` | sim | login(s) da tailnet do dono (`Tailscale-User-Login`), separados por vírgula |
| `PMO_ATALHO_OPENCODE` | não | `https://stack.<tailnet>.ts.net/`: botão "Abrir OpenCode" do painel |
| `LINEAR_API_KEY`, `LINEAR_TEAM_KEY` | não | espelho do Linear; sem as duas o `34-pmo.sh` o pula |
| `HOSTINGER_API_TOKEN`, `HOSTINGER_VM_ID` | para snapshot | `bin/hostinger.sh` |

O `34-pmo.sh` confere `PMO_HOSTS`, `PMO_LOGINS`, `GITHUB_TOKEN` e o IP da tailnet (`tailscale ip -4`) antes de
escrever qualquer coisa e lista tudo o que faltar numa só mensagem. Ele grava também os IPs do próprio nó
(`PMO_IPS_PROPRIOS`): o servidor recusa ação cuja origem seja o próprio nó, para o agente não agir pela URL da
tailnet de dentro da VPS.

### Acesso do notebook ao painel

`*.ts.net` resolve por MagicDNS, que já funciona no notebook Windows do dono (cliente Tailscale com "Use Tailscale
DNS settings" ligado, o padrão); não precisa de nenhuma ação lá. No WSL2 (modo NAT) o resolvedor do Windows
normalmente não é visto: use o IP `100.76.167.6` ou uma linha em `/etc/hosts` do WSL
(`100.76.167.6 stack.<tailnet>.ts.net`). Outros aparelhos precisam do cliente Tailscale com essa opção ligada e do
MagicDNS habilitado no admin da tailnet (já está). E, no admin da tailnet, habilitar **HTTPS Certificates** (aba DNS):
sem isso o `37-tailscale-serve.sh` falha.

Fallback, camada 3 (acesso perdido pela tailnet e pelo tunnel): `sudo hostinger.sh reiniciar --sim`; se
não voltar, `sudo hostinger.sh recuperacao --sim` (imprime uma senha root temporária, uma única vez).

## Regras que valem para os agentes

- `data/` esta fora do escopo: nao ler, nao escrever.
- Escrita livre so em `state/` e em branch nova (`chore/...`). Nada de push em `main`.
- Segredo vem de `secrets/agente.env` (agente) ou `secrets/admin.env` (dev) via ambiente do shell, nunca do bloco `env` de `settings.json`.
- API da Hostinger e gateway Composio: leitura livre; qualquer chamada que altere estado para e pergunta antes.
- Docker publica porta só em `127.0.0.1` ou no IP da tailnet (`-p 127.0.0.1:3000:3000`): porta publicada ignora o UFW.
