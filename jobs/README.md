# Jobs agendados

Cada `jobs/<nome>.job` define um job que roda na VPS como `agente`, pelo systemd. Nome em `[a-z0-9-]+`.
O formato é `CHAVE=valor`, uma por linha, sem shell (nada de `$`, aspas ou crase; `#` abre comentário).

| Chave | Obrigatória | Conteúdo |
|---|---|---|
| `DESCRICAO` | sim | texto livre (sem `$`, crase, `\` nem `%`) |
| `AGENDA` | sim | `OnCalendar` do systemd (`systemd-analyze calendar` valida) |
| `COMANDO` | sim | `jobs/bin/<script>` com argumentos fixos, sem `..` |
| `TIMEOUT_MIN` | sim | de 1 a 1440 minutos |
| `CHAVES` | não | com `SEGREDOS`: nomes das variáveis do arquivo, separados por vírgula; sufixo `?` marca a opcional. Só o `43-segredos-guiado.sh job <nome>` lê |
| `REPO` | não | `dono/nome`: clone raso (somente leitura) em `/srv/dev/jobs/work/<nome>`, apagado ao final; é o diretório do comando |
| `SEGREDOS` | não | nome (sem `.env`) do arquivo `/srv/dev/secrets/jobs/<nome>.env` (0640, dono `dev`), só no ambiente do comando |
| `HABILITADO` | não | `sim` ou `nao` (padrão `nao`) |

Chave desconhecida, repetida ou linha fora do formato recusa o job, e um job inválido recusa a instalação de todos.

```
# Varredura semanal do repositório X (exemplo; o nome do arquivo é o nome do job)
DESCRICAO=Varredura semanal do repositorio X
AGENDA=Mon *-*-* 03:00:00
COMANDO=jobs/bin/exemplo.sh
TIMEOUT_MIN=30
REPO=resper1965/projeto-x
SEGREDOS=varredura-x
HABILITADO=nao
```

Instalar e ligar: `sudo scripts/45-jobs.sh` (`--listar` só mostra o estado). Resultado em `/srv/dev/state/jobs/<nome>.json` e `.log`;
falha (`rc != 0`) chama o `alertar.sh`. `bin/stack-job <nome>` roda um job na hora, mesmo desligado.

## Jobs entregues (todos `HABILITADO=nao`)

| Job | Script | Notas |
|---|---|---|
| `dns-repair-dnscheck` | `jobs/bin/dnscheck.sh` | `dnscheck.py --all` e, com `HOSTINGER_API`, `wpaudit.py`; rc 1 = divergência |
| `varredura-be-secure`, `-n-discovery`, `-ntransfer`, `-site-sabrina`, `-aegis-itms` | `jobs/bin/varredura.sh` | semgrep + gitleaks (redigido) + osv-scanner; ferramentas pelo `scripts/46-ferramentas-varredura.sh` |
| `n360-alt-backup` | `jobs/bin/backup-n360.sh` | dump cifrado local, retenção 14; **sem cópia fora da VPS (restic/R2 adiado)** |

Pendentes (sem `.job`, o parser exige o script existente): `n360-alt-vigilancia`, `docvault-e2e`.
Segredos: `scripts/43-segredos-guiado.sh job <nome>`. Passo a passo: `docs/runbooks/2026-10-jobs-agendados.md`.
