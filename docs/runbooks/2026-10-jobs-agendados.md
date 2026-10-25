# Jobs agendados na VPS (outubro de 2026)

> **Nada deste runbook foi executado.** Spec: `docs/superpowers/specs/2026-10-25-jobs-agendados-design.md`; fichas dos workflows originais:
> `docs/superpowers/specs/2026-10-25-jobs-agendados-levantamento.md`. Todos os jobs entregues estão **desligados** (`HABILITADO=nao`).
> Os jobs só **leem** os projetos (clone raso apagado ao final) e gravam resultado na VPS. Nenhum job altera repositório, abre PR ou issue.
> **Regras de execução:** um comando por vez, cada um com aprovação do dono; nenhum valor de segredo passa pela conversa, por argv ou por log.
> Acesso: `ssh stack` (usuário `dev`, sudo sem senha). Comandos do `agente`: `sudo -u agente -H bash -c 'cd ~ && <cmd>'`.

## Aviso do backup do n.360-alternative

O job `n360-alt-backup` grava **só em `/srv/dev/backups/n360-alt/`, no próprio disco da VPS**. **Não há cópia fora da VPS** (restic/R2 está
adiado a pedido do dono). Se a VPS ou o disco se perder, os dumps se perdem junto, e o banco de produção do n.360-alternative não tem outro
backup. A validação é **estrutural** (`pg_restore -l` sobre o dump decifrado), não uma restauração em Postgres efêmero. A passphrase
(`BACKUP_PASSPHRASE`) existe apenas em `/srv/dev/secrets/jobs/n360-alt-backup.env`: sem ela os dumps não abrem. Guarde-a também fora da VPS
(gerenciador de senhas do dono). Retenção: 14 dumps (14 dias, um por dia).

## Os jobs

| Job | Agenda (UTC) | Segredos (`SEGREDOS` → chaves) | Antes de ligar |
|---|---|---|---|
| `dns-repair-dnscheck` | diária 10:00 | `dns-repair` → `CLOUDFLARE_API_TOKEN`, `HOSTINGER_API` (opcional) | token Cloudflare somente leitura de DNS |
| `varredura-be-secure` | seg 06:00 | nenhum | ferramentas instaladas (passo 1) |
| `varredura-n-discovery` | ter 03:00 | nenhum | idem |
| `varredura-ntransfer` | dom 00:00 | nenhum | idem |
| `varredura-site-sabrina` | seg 01:30 | nenhum | idem |
| `varredura-aegis-itms` | qua 02:00 | nenhum | idem |
| `n360-alt-backup` | diária 06:17 | `n360-alt-backup` → `DATABASE_URL`, `BACKUP_PASSPHRASE` | conexão direta ou de sessão (não pooler em modo transação), ler o aviso acima |

**Pendentes (sem `.job` ainda, o parser exige o script existente):** `n360-alt-vigilancia` (npm audit + typecheck + test contra Postgres 17 em
container) e `docvault-e2e` (Playwright em container; depende da decisão sobre RAM e testes contra produção, D6). Entram em outra rodada.

Se o repositório de uma varredura for público (decisão D1 do spec), basta religar o CodeQL no GitHub e dispensar o job.

## Como ligar um job (passo a passo)

1. **Código no servidor** (PR do stack-vps mergeado e `/opt/stack-vps` atualizado). Confira: `ls /opt/stack-vps/jobs/`.
2. **Pastas e unidades base** (como `dev`): `sudo /opt/stack-vps/scripts/45-jobs.sh --listar` mostra o estado de cada `.job` (`INVALIDO` aqui
   recusa tudo). A instalação (passo 6) cria `/srv/dev/jobs`, `/srv/dev/state/jobs`, `/srv/dev/backups` e `/srv/dev/secrets/jobs`.
3. **Ferramentas** (só para as varreduras), como `agente`:
   `sudo -u agente -H bash -c 'cd ~ && /opt/stack-vps/scripts/46-ferramentas-varredura.sh'`
   Instala semgrep (pipx, versão fixa), gitleaks e osv-scanner (versões fixas, SHA-256 conferido contra valor fixado no script; divergiu = não instala).
4. **Segredos** (só quem tem `SEGREDOS`), como `dev`, num terminal seu:
   `/opt/stack-vps/scripts/43-segredos-guiado.sh job <nome>`
   Pede cada chave com entrada oculta; grava `/srv/dev/secrets/jobs/<arquivo>.env` (0640 `dev:agente`). Recusa sobrescrever sem `--trocar`.
5. **Teste à mão** (mesmo desligado): `sudo -u agente /opt/stack-vps/bin/stack-job <nome>`. Leia `/srv/dev/state/jobs/<nome>.json` (`rc`, `resumo`) e `<nome>.log`.
   `rc 0` = ok; `rc 1` = achado (segredo, vulnerabilidade alta/crítica, divergência de DNS, falha de dump); `rc 2` = erro de execução ou pré-requisito ausente.
   Falha chama o `alertar.sh`.
6. **Ligar:** num PR do stack-vps, troque `HABILITADO=nao` por `HABILITADO=sim` em `jobs/<nome>.job`. Depois do merge e da atualização do servidor:
   `sudo /opt/stack-vps/scripts/45-jobs.sh` (idempotente; gera `stack-job-<nome>.service` e `.timer`).
7. **Conferir:** `systemctl list-timers 'stack-job-*'` e `/opt/stack-vps/bin/stack-doctor` (seção `jobs`).

## Como ver o estado

- `/opt/stack-vps/bin/stack-doctor`: seção `jobs` (definidos, habilitados, timer ativo; desligados aparecem como `pend`).
- `/usr/local/lib/stack-vps/health.sh`: seção `jobs` (último `rc` 0 e fresco conforme a agenda, senão FALHA). O `vigia-health.sh` alerta.
- `/srv/dev/state/jobs/<nome>.json` e `.log`: resultado da última execução (nunca contém o valor de segredo; o log troca os valores carregados por `***`).
- Relatórios das varreduras: `/srv/dev/state/jobs/<nome-curto>.varredura/` (`semgrep.sarif`, `semgrep.json`, `gitleaks.json` redigido, `osv.json`).
  Os relatórios do semgrep podem trazer trechos de código do projeto: a pasta é do `agente` (0750), não a copie para fora.
- DNS: `/srv/dev/state/jobs/dns-repair-dnscheck.saida/dnscheck.txt` (e `wpaudit.txt`).
- Backup: `ls -l /srv/dev/backups/n360-alt/` (como `agente`).
- Logs do systemd: `journalctl -u stack-job-<nome>.service -n 50`.

## Restaurar um backup do n.360-alternative (sempre num banco de teste, nunca por cima da produção)

```sh
# como agente, com BACKUP_PASSPHRASE exportada a partir do arquivo de segredos (sem imprimir)
openssl enc -d -aes-256-cbc -pbkdf2 -iter 600000 -pass env:BACKUP_PASSPHRASE -in /srv/dev/backups/n360-alt/AAAA-MM-DD.dump.enc | pg_restore -l | head
```

Para restaurar de fato, aponte o `pg_restore -d` para um Postgres de teste (ver a ficha 6 do levantamento: papéis `anon`/`authenticated`/`service_role` antes do restore).

## Rollback

- **Desligar um job:** `HABILITADO=nao` no `.job` (PR) e `sudo /opt/stack-vps/scripts/45-jobs.sh` (remove o `.service` e o `.timer`). Emergência, sem PR:
  `sudo systemctl disable --now stack-job-<nome>.timer`; o próximo `45-jobs.sh` reconcilia com o repositório.
- **Parar uma execução em curso:** `sudo systemctl stop stack-job-<nome>.service`.
- **Segredos:** apagar `/srv/dev/secrets/jobs/<arquivo>.env` (como `dev`) e regravar com `43-segredos-guiado.sh job <nome>`; `--trocar` regrava o arquivo inteiro.
  Se um valor vazou, **gire o token na origem** (Cloudflare, banco) antes de qualquer coisa.
- **Ferramentas:** são arquivos em `~agente/.local/bin` e o venv do pipx; para voltar de versão, ajuste o script `46` num PR e rode-o de novo. Para remover:
  `rm ~agente/.local/bin/{gitleaks,osv-scanner}`, `pipx uninstall semgrep` e `rm -r ~agente/.local/share/stack-ferramentas`.
- **Backups:** apagar `/srv/dev/backups/n360-alt/*.dump.enc` é irreversível, e hoje não há outra cópia (ver o aviso no topo).
