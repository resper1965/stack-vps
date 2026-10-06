# Migração e instalação definitiva da VPS

Data: 05/10/2026. Decisões tomadas com o Ricardo na sessão de brainstorming do mesmo dia.

## Objetivo

A VPS `stack` (Hostinger KVM 8, 148.230.77.242) vira o único ambiente de desenvolvimento e o laptop
passa a ser só terminal. "Definitivo" quer dizer três coisas, e as três precisam ser provadas:

1. **Recriável.** Uma VPS formatada volta ao estado de trabalho só com os scripts deste repositório
   mais o backup no R2.
2. **Completa.** Todo trabalho que hoje existe só no laptop (WSL e `DESENVOLVIMENTO`) está no GitHub
   e clonado na VPS.
3. **Fechada.** Nenhuma porta da VPS responde na internet; o acesso é pela tailnet, com o Cloudflare
   Tunnel de reserva.

## Decisões

| # | Decisão | Alternativa descartada |
|---|---|---|
| 1 | Reinstalar a VPS atual do zero e reconstruir só pelos scripts | manter a VPS e só fechar lacunas; VPS nova em paralelo |
| 2 | Fases, acesso e laptop primeiro, formatação em janela única de ~2h | formatar já e corrigir no caminho |
| 3 | Backup com restic no R2, usado na migração e na rotina diária | `scp` para o laptop e restic depois |
| 4 | Pasta sem remoto vira repo **privado** no dono da categoria | tudo em `resper1965`; `rsync` direto |
| 5 | Push direto na `main` apenas em fast-forward, **exceção única da migração** | branch `chore/migracao-laptop` + merge manual |
| 6 | Laptop não é reorganizado; a organização final existe só na VPS | espelhar as categorias no WSL e no `DESENVOLVIMENTO` |
| 7 | Nada é apagado: LIXO e pastas "?" ficam no laptop | — |
| 8 | Tailscale é o acesso principal e entra **antes** de tudo, na VPS atual | fechar a 22 só no fim da migração |
| 9 | Cloudflare Tunnel continua, como segundo caminho de SSH | desativar tunnel, DNS e Access |

## Estado medido em 05/10/2026

- Ubuntu 24.04.4, 8 vCPU, 31 GB de RAM, no ar há 19 dias. `cloudflared`, `docker` e `tmux-dev` ativos.
- **Tailscale não está instalado na VPS.** A tailnet já tem o laptop (`35p34`), `gabi`, `pve` e o
  Android `esper`.
- O acesso pelo tunnel (`ssh stack`) travou na sessão de 05/10, e a regra do UFW diz "revisar quando o
  tunnel voltar". O tunnel está instável e precisa de diagnóstico.
- UFW ativo com a 22 liberada para qualquer origem (IPv4 e IPv6); o sshd escuta em `0.0.0.0:22`.
- 116 clones em `/srv/dev/repos` (apps 88, orm 15, agents 7, infra 6). Nenhum com alteração local.
  53 aparecem com 1 commit fora do `origin` — provavelmente as branches `chore/inventario-*`, que o
  `12-push-state.sh` envia por URL e por isso não atualizam `origin/*`. A fase 2 confere.
- Só existem na VPS: `state/` (96 KB), `data/` (207 MB), `secrets/.env` (8 chaves, nenhuma do R2),
  `/etc/cloudflared/credentials.json`, `~/.claude` e `~/.codex`.
- Nenhum container e nenhum volume Docker.

Divergências entre o ambiente e os scripts:

- Claude e Codex estão em `/usr/local/bin`; o `04-agents.sh` instala via npm do mise.
- O cron semanal (`0 7 * * 1 weekly-review.sh`) e a cópia dos scripts para `/srv/dev/bin` foram
  feitos à mão.
- O `06-tunnel.sh` reaproveita o tunnel `stack-vps` existente, mas a credencial só é gravada na
  criação: numa VPS formatada o `cloudflared` não sobe.
- O `.env` tem `CLOUDFLARE_API_TOKEN` duplicado e a chave `FEARTHERLESS_API_KEY` com o nome errado.
- O `health.sh` confere `state/.last-backup`, que nada grava.
- O README cita só os scripts 01 e 02; o `srv-dev-README` repete à mão o sudoers que o `01` já faz.

## Acesso

| Caminho | Uso | Mecanismo |
|---|---|---|
| `ssh stack` | principal: SSH, VS Code Remote-SSH, portas de desenvolvimento (`http://stack:3000`) | OpenSSH pela tailnet (não Tailscale SSH: chaves e VS Code ficam como estão) |
| `ssh stack-cf` | reserva, se a tailnet cair | Cloudflare Tunnel + Access, `ssh.esper.ws` |
| console do hPanel | emergência, se os dois caírem | já existe na Hostinger |

- **UFW**: entrada negada por padrão; a 22 aceita só pelas interfaces `tailscale0` e `lo`. O tunnel
  chega ao sshd por `localhost`, por isso continua funcionando com a 22 pública fechada.
- **Nó `stack`**: entra na tailnet com `--hostname stack` e com **a expiração de chave desativada** no
  painel do Tailscale. Sem isso a VPS sai da tailnet depois de 180 dias.
- **Docker**: porta publicada ignora o UFW. Regra do ambiente: publicar só em `127.0.0.1` ou no IP da
  tailnet (`-p 127.0.0.1:3000:3000`). Vai para o `docs/CLAUDE.md`/`AGENTS.md`.
- **WSL**: em modo NAT o MagicDNS pode não resolver `stack`. A fase 0a confere; se falhar, usa-se o
  modo de rede espelhado do WSL ou o IP `100.x` no `~/.ssh/config`.

## Fases

Cada fase tem um critério de saída. Nenhuma começa sem que a anterior o cumpra.

| Fase | Conteúdo | Critério de saída |
|---|---|---|
| 0a. Acesso | Tailscale na VPS atual; conserto do tunnel; UFW fechado | `ssh stack` e `ssh stack-cf` funcionam; `ssh dev@148.230.77.242` é recusado |
| 0. Scripts | Corrigir as divergências; criar `14-backup.sh`, `15-restore.sh`, `20-laptop-github.sh`, `.env.example`; README com a ordem completa | diff revisado e aprovado pelo Ricardo; `shellcheck` limpo |
| 1. Laptop → GitHub | TSV de decisão revisado; push e criação de repos; escopo atualizado | todo item `push`/`criar` sem commit pendente, ou na lista de pendências com motivo |
| 2. Backup | Bucket e token R2; backup da VPS atual; restore de teste; conferência dos 53 commits | `diff -r` do restore de teste sem diferença; as 3 chaves guardadas no gerenciador de senhas |
| 3. Janela | Snapshot, reinstalação, scripts, restore, clones, logins | `health.sh` todo `ok`; os dois caminhos de acesso funcionando; 22 pública fechada |
| 4. Fechamento | Rotina semanal; backup automático; snapshot descartado | critérios de aceite abaixo |

## Fase 0a — acesso

1. O Ricardo gera no painel do Tailscale uma auth key de uso único.
2. Instalar o Tailscale na VPS atual e entrar com `tailscale up --authkey=… --hostname stack`.
   O Ricardo desativa a expiração de chave do nó no painel.
3. Validar `ssh stack` pelo Windows e pelo WSL.
4. Diagnosticar o tunnel (`journalctl -u cloudflared`, estado do tunnel e do Access na API) e
   corrigir. Validar `ssh stack-cf`.
5. Rodar o `07-firewall.sh` na versão nova (22 só em `tailscale0` e `lo`).
6. Confirmar de fora que `ssh dev@148.230.77.242` é recusado e que os dois caminhos seguem de pé.

Se o passo 6 falhar, entra-se pelo console do hPanel e roda-se `ufw allow 22/tcp`.

## Fase 0 — scripts

- **`01-baseline.sh`**: passa a instalar o Tailscale e a entrar na tailnet com `--hostname stack`. A
  auth key vem da variável `TS_AUTHKEY` no momento da execução, nunca de arquivo.
- **`04-agents.sh`**: fica como fonte única da instalação do Claude e do Codex. Na fase 3 vale o que
  ele instalar; o binário em `/usr/local/bin` não é reproduzido.
- **`05-servicos.sh`**: passa a copiar `bin/health.sh`, `compose/playwright.yml` e os scripts 08–13 para
  `/srv/dev/bin` (o 13 como `weekly-review.sh`), instalar o cron semanal e o timer do backup.
- **`06-tunnel.sh`**: se o tunnel existe e falta `/etc/cloudflared/credentials.json`, para com a
  mensagem "rode 15-restore.sh antes". Nunca cria um segundo tunnel. Incorpora o conserto da fase 0a.
- **`07-firewall.sh`**: troca o `--fechar-22` por regra fixa — 22 só em `tailscale0` e `lo` — e recusa
  rodar se o `tailscaled` não estiver ativo com IP atribuído, para não trancar a VPS.
- **`14-backup.sh`** e **`15-restore.sh`**: ver seção Backup.
- **`20-laptop-github.sh`**: ver seção Laptop.
- **`bin/health.sh`**: confere `tailscaled` e `cloudflared`, além do que já confere.
- **`.env.example`**: só os nomes das chaves, incluindo `R2_ACCESS_KEY_ID`, `R2_SECRET_ACCESS_KEY` e
  `RESTIC_PASSWORD`. O `.env` real é corrigido na fase 2 (duplicata removida e nome da chave acertado).
- **README**, **`docs/srv-dev-README.md`** e **`docs/ssh-config-wsl.md`**: ordem 01 → 15, roteiro de
  recuperação do zero sem passo manual duplicado, e os dois blocos de `~/.ssh/config` (`stack` e
  `stack-cf`).
- **`docs/CLAUDE.md`** e **`docs/AGENTS.md`**: regra de publicação de porta do Docker.

## Backup

- **Repositório**: restic em `s3:https://<CLOUDFLARE_ACCOUNT_ID>.r2.cloudflarestorage.com/stack-vps-backup`.
  O token R2 tem leitura e escrita **só nesse bucket**.
- **Entra**: `/srv/dev/state`, `/srv/dev/data`, `/srv/dev/secrets/.env`,
  `/etc/cloudflared/credentials.json`, `/home/dev/.claude`, `/home/dev/.codex`.
- **Sai**: `.credentials.json` e `auth.json` dos agentes (o login é refeito), `node_modules`, caches,
  `/srv/dev/repos` (a verdade é o GitHub) e `/var/lib/tailscale`. A identidade do nó não é restaurada:
  na janela o `01` entra na tailnet antes do restore, e trazer a identidade antiga depois criaria dois
  nós disputando o mesmo nome.
- **Chaves**: `R2_ACCESS_KEY_ID`, `R2_SECRET_ACCESS_KEY` e `RESTIC_PASSWORD` ficam no `.env` **e** no
  gerenciador de senhas do Ricardo. O `.env` está dentro do backup que ele destrava; sem a cópia
  externa não existe restore. A fase 2 só termina com a confirmação de que as três foram guardadas.
  A auth key do Tailscale não é guardada: é de uso único e gerada na hora.
- **`14-backup.sh`** (root): `restic backup` dos caminhos acima e
  `forget --keep-daily 7 --keep-weekly 4 --keep-monthly 6 --prune`. Grava `/srv/dev/state/.last-backup`
  só se tudo passar. Aos domingos roda também `restic check --read-data-subset=5%`. Timer systemd
  diário às 06:00 UTC (03:00 de Brasília).
- **`15-restore.sh`** (root): `restic restore latest` dos mesmos caminhos e reaplica dono e permissão
  (`.env` 600 dev:dev; `credentials.json` 600 root). Recusa destino que não esteja vazio, salvo com
  `--forcar`. `--destino <dir>` restaura em outro lugar, para teste.

## Laptop → GitHub

- **`docs/migracao-laptop.tsv`**: uma linha por pasta, com as colunas `origem` (wsl|windows),
  `caminho`, `dono`, `repo`, `arvore` (apps|orm|agents|infra) e `acao` (push|criar|fica). Gerado a
  partir de `CONSOLIDACAO-2026-09-16.md` e **revisado pelo Ricardo antes de qualquer envio**.
  LIXO e "?" entram como `fica`.
- **Mapeamento de dono para `criar`**: bekaa-apps → `bekaa-trusted-advisors`; forense → `forense-io`;
  ionic-health, ness-desenvolvimento, comercial-ness, agentes e pessoal → `resper1965`, salvo
  indicação contrária na revisão do TSV.
- **`20-laptop-github.sh`** roda no WSL e lê as pastas do Windows por `/mnt/c/...`. O OneDrive não
  trava leitura, por isso as 15 pastas travadas não bloqueiam a migração.
  - `push`: envia toda branch local à frente do remoto, sem force. Branch divergente não sobe e vai
    para a lista de pendências. Push na `main` em fast-forward é a exceção da decisão 5.
  - `criar`: `git init` se preciso e `gh repo create <dono>/<repo> --private --source . --push`.
  - Antes do primeiro push de cada repo roda `gitleaks` e bloqueia arquivos acima de 50 MB e as
    extensões `.pst .e01 .dd .zip .xlsx .csv .pdf`. Se achar algo, o repo não sobe e vai para a
    lista com o motivo. Em forense e propostas sobe só o código; documento de cliente fica no laptop.
  - `--simular` lista o que faria sem enviar nada. É sempre a primeira execução.
  - Ao final, acrescenta os repos criados ou enviados em `state/escopo-auditoria.tsv`.

## Janela (fase 3)

De terça a sexta (o cron semanal roda na segunda às 07h), com 2 horas reservadas.

1. Rodar o `14-backup.sh`; o `restic snapshots` precisa mostrar o backup dos últimos minutos.
2. O Ricardo remove o nó `stack` no painel do Tailscale, gera uma auth key nova, tira o snapshot e
   reinstala o Ubuntu 24.04 pelo hPanel. Ações destrutivas na conta dele não são feitas por API.
3. Remover a entrada antiga do `known_hosts`; entrar como root pelo IP. A 22 pública fica aberta só
   deste passo até o 7.
4. Clonar `resper1965/stack-vps`; rodar o `01` com `TS_AUTHKEY`. O Ricardo desativa a expiração de
   chave do nó novo. A partir daqui tudo segue por `ssh stack`.
5. Rodar 02 → 03 → 05.
6. O Ricardo informa as 3 chaves na sessão e roda-se o `15-restore.sh`.
7. Rodar o `06` e validar `ssh stack-cf`. Rodar o `07`; `ssh dev@148.230.77.242` precisa ser recusado.
8. Rodar o `04` como dev; o Ricardo faz o login do Claude e do Codex.
9. Rodar o `09` com o escopo atualizado.
10. Rodar o `health.sh`: tudo `ok`.

**Desfazer**: falha até o passo 10 que não se resolva em 30 minutos leva à restauração do snapshot da
Hostinger (e à remoção do nó novo no Tailscale). O backup no R2 não é tocado pela janela.

## Critérios de aceite (fase 4)

- `ssh dev@148.230.77.242` é recusado; nenhuma porta responde no IP público.
- `ssh stack` e `ssh stack-cf` funcionam; o VS Code Remote-SSH funciona por `stack`.
- O nó `stack` aparece no painel do Tailscale com expiração de chave desativada.
- `weekly-review.sh --now` gera o relatório e o `dashboard.json`, já com os repos vindos do laptop.
- O backup do dia seguinte aparece sozinho em `restic snapshots`, e o `health.sh` mostra a idade dele.
- O snapshot da Hostinger só é apagado após 7 dias de rotina sem falha.

## Testes

- `shellcheck` em todos os scripts.
- A fase 0a é o ensaio real do Tailscale, do tunnel e do `07` na VPS atual, com o console do hPanel
  como saída.
- O `14` roda de verdade na VPS atual. O `15` roda com `--destino /tmp/teste-restore` e o resultado é
  comparado ao original com `diff -r`.
- O `20` roda em `--simular` e a saída é revisada antes da execução real.
- Os scripts 01–05 não têm ensaio fora da janela; a rede de segurança deles é o snapshot.

## Fora do escopo

- Apagar qualquer pasta ou repositório.
- Expor serviço publicamente pelo tunnel (preview para cliente etc.).
- Tailscale SSH, ACLs da tailnet e subnet routers.
- Corrigir `origin/HEAD` fora da `main` e migrar `master` → `main` (seguem a regra de "quando for tocado").
- Política de CI.
- Mover documento de cliente para o GitHub.
