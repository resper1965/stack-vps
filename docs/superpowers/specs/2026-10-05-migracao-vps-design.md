# Migração e instalação definitiva da VPS

Data: 05/10/2026. Decisões tomadas com o Ricardo na sessão de brainstorming do mesmo dia.

## Objetivo

A VPS `stack` (Hostinger KVM 8, 148.230.77.242) vira o único ambiente de desenvolvimento e o laptop
passa a ser só terminal. "Definitivo" quer dizer duas coisas, e as duas precisam ser provadas:

1. **Recriável.** Uma VPS formatada volta ao estado de trabalho só com os scripts deste repositório
   mais o backup no R2.
2. **Completa.** Todo trabalho que hoje existe só no laptop (WSL e `DESENVOLVIMENTO`) está no GitHub
   e clonado na VPS.

## Decisões

| # | Decisão | Alternativa descartada |
|---|---|---|
| 1 | Reinstalar a VPS atual do zero e reconstruir só pelos scripts | manter a VPS e só fechar lacunas; VPS nova em paralelo |
| 2 | Fases, laptop primeiro, formatação em janela única de ~2h | formatar já e corrigir no caminho |
| 3 | Backup com restic no R2, usado na migração e na rotina diária | `scp` para o laptop e restic depois |
| 4 | Pasta sem remoto vira repo **privado** no dono da categoria | tudo em `resper1965`; `rsync` direto |
| 5 | Push direto na `main` apenas em fast-forward, **exceção única da migração** | branch `chore/migracao-laptop` + merge manual |
| 6 | Laptop não é reorganizado; a organização final existe só na VPS | espelhar as categorias no WSL e no `DESENVOLVIMENTO` |
| 7 | Nada é apagado: LIXO e pastas "?" ficam no laptop | — |

## Estado medido em 05/10/2026

- Ubuntu 24.04.4, 8 vCPU, 31 GB de RAM, no ar há 19 dias. `cloudflared`, `docker` e `tmux-dev` ativos.
- 116 clones em `/srv/dev/repos` (apps 88, orm 15, agents 7, infra 6). Nenhum com alteração local.
  53 aparecem com 1 commit fora do `origin` — provavelmente as branches `chore/inventario-*`, que o
  `12-push-state.sh` envia por URL e por isso não atualizam `origin/*`. A fase 2 confere.
- Só existem na VPS: `state/` (96 KB), `data/` (207 MB), `secrets/.env` (8 chaves, nenhuma do R2),
  `/etc/cloudflared/credentials.json`, `~/.claude` e `~/.codex`.
- Nenhum container e nenhum volume Docker.
- Porta 22 aberta para a internet; o UFW nunca foi fechado.

Divergências entre o ambiente e os scripts:

- Claude e Codex estão em `/usr/local/bin`; o `04-agents.sh` instala via npm do mise.
- O cron semanal (`0 7 * * 1 weekly-review.sh`) e a cópia dos scripts para `/srv/dev/bin` foram
  feitos à mão.
- O `06-tunnel.sh` reaproveita o tunnel `stack-vps` existente, mas a credencial só é gravada na
  criação: numa VPS formatada o `cloudflared` não sobe.
- O `.env` tem `CLOUDFLARE_API_TOKEN` duplicado e a chave `FEARTHERLESS_API_KEY` com o nome errado.
- O `health.sh` confere `state/.last-backup`, que nada grava.
- O README cita só os scripts 01 e 02; o `srv-dev-README` repete à mão o sudoers que o `01` já faz.

## Fases

Cada fase tem um critério de saída. Nenhuma começa sem que a anterior o cumpra.

| Fase | Conteúdo | Critério de saída |
|---|---|---|
| 0. Scripts | Corrigir as divergências; criar `14-backup.sh`, `15-restore.sh`, `20-laptop-github.sh`, `.env.example`; README com a ordem completa | diff revisado e aprovado pelo Ricardo; `shellcheck` limpo |
| 1. Laptop → GitHub | TSV de decisão revisado; push e criação de repos; escopo atualizado | todo item `push`/`criar` sem commit pendente, ou na lista de pendências com motivo |
| 2. Backup | Bucket e token R2; backup da VPS atual; restore de teste; conferência dos 53 commits | `diff -r` do restore de teste sem diferença; as 3 chaves guardadas no gerenciador de senhas |
| 3. Janela | Snapshot, reinstalação, scripts, restore, clones, logins | `health.sh` todo `ok`; `ssh stack` pelo tunnel |
| 4. Fechamento | Fechar a 22; rotina semanal; backup automático | critérios de aceite abaixo |

## Fase 0 — scripts

- **`04-agents.sh`**: fica como fonte única da instalação do Claude e do Codex. Na fase 3 vale o que
  ele instalar; o binário em `/usr/local/bin` não é reproduzido.
- **`05-servicos.sh`**: passa a copiar `bin/health.sh`, `compose/playwright.yml` e os scripts 08–13 para
  `/srv/dev/bin` (o 13 como `weekly-review.sh`), instalar o cron semanal e o timer do backup.
- **`06-tunnel.sh`**: se o tunnel existe e falta `/etc/cloudflared/credentials.json`, para com a
  mensagem "rode 15-restore.sh antes". Nunca cria um segundo tunnel.
- **`14-backup.sh`** e **`15-restore.sh`**: ver seção Backup.
- **`20-laptop-github.sh`**: ver seção Laptop.
- **`.env.example`**: só os nomes das chaves, incluindo `R2_ACCESS_KEY_ID`, `R2_SECRET_ACCESS_KEY` e
  `RESTIC_PASSWORD`. O `.env` real é corrigido na fase 2 (duplicata removida e nome da chave acertado).
- **README** e **`docs/srv-dev-README.md`**: ordem 01 → 15 e o roteiro de recuperação do zero, sem
  passo manual duplicado.

## Backup

- **Repositório**: restic em `s3:https://<CLOUDFLARE_ACCOUNT_ID>.r2.cloudflarestorage.com/stack-vps-backup`.
  O token R2 tem leitura e escrita **só nesse bucket**.
- **Entra**: `/srv/dev/state`, `/srv/dev/data`, `/srv/dev/secrets/.env`,
  `/etc/cloudflared/credentials.json`, `/home/dev/.claude`, `/home/dev/.codex`.
- **Sai**: `.credentials.json` e `auth.json` dos agentes (o login é refeito), `node_modules`, caches,
  e `/srv/dev/repos` (a verdade é o GitHub).
- **Chaves**: `R2_ACCESS_KEY_ID`, `R2_SECRET_ACCESS_KEY` e `RESTIC_PASSWORD` ficam no `.env` **e** no
  gerenciador de senhas do Ricardo. O `.env` está dentro do backup que ele destrava; sem a cópia
  externa não existe restore. A fase 2 só termina com a confirmação de que as três foram guardadas.
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
2. O Ricardo tira o snapshot e reinstala o Ubuntu 24.04 pelo hPanel. Ações destrutivas na conta
   dele não são feitas por API.
3. Remover a entrada antiga do `known_hosts`; entrar como root pelo IP.
4. Clonar `resper1965/stack-vps`; rodar 01 → 02 → 03 → 05.
5. O Ricardo informa as 3 chaves na sessão e roda-se o `15-restore.sh`.
6. Rodar o `06` e testar `ssh stack` pelo tunnel, com a 22 ainda aberta.
7. Rodar o `04` como dev; o Ricardo faz o login do Claude e do Codex.
8. Rodar o `09` com o escopo atualizado.
9. Rodar o `health.sh`: tudo `ok`.

**Desfazer**: falha até o passo 9 que não se resolva em 30 minutos leva à restauração do snapshot da
Hostinger. O backup no R2 não é tocado pela janela.

## Critérios de aceite (fase 4)

- O `07-firewall.sh --fechar-22` foi aplicado e `ssh dev@148.230.77.242` é recusado.
- `ssh stack` e o VS Code Remote-SSH funcionam pelo tunnel.
- `weekly-review.sh --now` gera o relatório e o `dashboard.json`, já com os repos vindos do laptop.
- O backup do dia seguinte aparece sozinho em `restic snapshots`, e o `health.sh` mostra a idade dele.
- O snapshot da Hostinger só é apagado após 7 dias de rotina sem falha.

## Testes

- `shellcheck` em todos os scripts.
- O `14` roda de verdade na VPS atual. O `15` roda com `--destino /tmp/teste-restore` e o resultado é
  comparado ao original com `diff -r`.
- O `20` roda em `--simular` e a saída é revisada antes da execução real.
- Os scripts 01–07 não têm ensaio fora da janela; a rede de segurança deles é o snapshot.

## Fora do escopo

- Apagar qualquer pasta ou repositório.
- Corrigir `origin/HEAD` fora da `main` e migrar `master` → `main` (seguem a regra de "quando for tocado").
- Política de CI.
- Mover documento de cliente para o GitHub.
