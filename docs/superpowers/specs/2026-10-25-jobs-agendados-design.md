# Jobs agendados na VPS (substituem os workflows agendados sem créditos do GitHub)

**Data:** 2026-10-25 · **Estado:** aprovado pelo Ricardo em 2026-10-25 ("execute o plano"); decisões abaixo tomadas pela melhor recomendação
**Base:** `2026-10-25-jobs-agendados-levantamento.md` (fichas dos 10 workflows desligados em 19/10) e `2026-10-19-ci-sem-creditos-design.md` (seção 3).

## Regras do dono para este trabalho
- **Não mexer nos projetos.** Nenhum job altera repositório, abre PR ou issue, nem toca workflow. Os jobs só **leem** (clone raso) e gravam resultado na VPS.
- A migração de cada projeto é manual, um a um, com a ajuda do agente. Para isso existem os prompts em `docs/prompts/` (01 CI local, 02 workflow agendado em job, 03 padrão de projeto).

## Decisões (D1 a D7 do levantamento)
| # | Decisão |
|---|---|
| D1 | CodeQL é gratuito só em repositório público: se um dos quatro for público, basta religar o workflow no GitHub e o job de varredura dele é dispensado. Os jobs de varredura entram desligados por padrão |
| D2 | Substituir o CodeQL por **Semgrep + gitleaks + osv-scanner** (e Trivy fs/bandit onde o workflow já usava). Aceita-se taint mais raso e a falta do painel Code scanning. A varredura roda **só no horário agendado** (sem gatilho de push/PR) |
| D3 | DefectDojo **não** é replicado. O resultado de cada job fica em arquivo na VPS e no alerta; se o DefectDojo existir e o dono quiser, um upload entra depois |
| D4 | Canal de alerta = `alertar.sh` (ntfy/Telegram), o mesmo da stack. Falha de job alerta; sucesso fica no status. Nada de issue em repositório |
| D5 | Backup do `n.360-alternative`: `pg_dump` consistente, criptografado com passphrase, **destino local** `/srv/dev/backups/<job>/` com retenção, teste de restauração semanal; cópia fora da VPS (restic/R2) segue adiada pelo dono, e o job registra esse risco no status. O job **só liga** depois que o dono fornecer `DATABASE_URL` e `BACKUP_PASSPHRASE` pelo `43-segredos-guiado.sh job` |
| D6 | Os jobs rodam como `agente`, clonam com o `git-credential-stack` já existente (token somente leitura) para `/srv/dev/jobs/work/<job>` (clone raso novo a cada execução, apagado depois) |
| D7 | `n.discovery` tem dois CodeQL duplicados: vira **um** job de varredura. `be-secure` e `site-sabrina` são pequenos e entram na mesma família de varredura |

## Arquitetura
- **Definição por arquivo:** `jobs/<nome>.job` (pares `CHAVE=valor`, sem shell): `DESCRICAO`, `AGENDA` (OnCalendar do systemd), `COMANDO` (script em `jobs/bin/` com argumentos fixos), `SEGREDOS` (nome do arquivo em `/srv/dev/secrets/jobs/<nome>.env`, opcional), `REPO` (repositório a clonar, opcional), `TIMEOUT_MIN`, `HABILITADO` (`sim` ou `nao`, padrão `nao`).
- **Executor:** `bin/stack-job <nome>` roda como `agente`: lê o `.job` (parse sem `source`/`eval`), clona o `REPO` se houver, carrega os segredos do arquivo 0640 (sem imprimir), roda o comando com timeout, grava `/srv/dev/state/jobs/<nome>.json` (`inicio`, `fim`, `rc`, `resumo`; nunca segredo), e chama o `alertar.sh` em falha. Saída em `/srv/dev/state/jobs/<nome>.log`.
- **Instalador:** `scripts/45-jobs.sh` (root) valida todos os `.job` e gera `stack-job-<nome>.service` e `.timer` do systemd, **somente** para os com `HABILITADO=sim`; remove os de definições que sumiram ou ficaram `nao`. Idempotente.
- **Health e doctor:** seção `jobs` no `health.sh` (cada job habilitado: último `rc` 0 e fresco conforme a agenda, senão FALHA) e no `stack-doctor` (jobs definidos e habilitados; `pend` para os desligados).
- **Ferramentas de varredura:** `scripts/46-ferramentas-varredura.sh` (como `agente`) instala Semgrep (pipx), gitleaks e osv-scanner (binários de release com SHA-256 conferido), versões fixas.
- **Segredos:** `43-segredos-guiado.sh job <nome>` pede cada chave da lista `SEGREDOS` com entrada oculta e grava `/srv/dev/secrets/jobs/<nome>.env` (0640 `dev:agente`).

## Jobs desta rodada
| Job | Estado inicial | Observação |
|---|---|---|
| `dns-repair-dnscheck` | pronto para ligar | trivial; usa `CLOUDFLARE_API_TOKEN` (e `HOSTINGER_API` opcional) |
| `varredura-be-secure`, `varredura-n-discovery`, `varredura-ntransfer`, `varredura-site-sabrina`, `varredura-aegis-itms` | desligados | família `jobs/bin/varredura.sh`; liga um a um pelo dono |
| `n360-alt-backup` | desligado até o dono dar os segredos | D5 |
| `n360-alt-vigilancia` | desligado | `npm audit` + typecheck + test; depende de Postgres em container |
| `docvault-e2e` | desligado | Playwright em container; depende de D6 (RAM) |

## Fora de escopo
Alterar repositórios, religar workflow, DefectDojo, restic/R2, `@ness/auth` (spec próprio).

## Testes
Executor, instalador e health com stubs (`STACK_TESTE=1`). Segredo de sentinela nunca em saída, log, status ou argv. Parse recusa `.job` com chaves desconhecidas, comando fora de `jobs/bin/`, agenda inválida e nome inválido.
