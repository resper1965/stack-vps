# Spike API da Hostinger (2026-10-18)

Só documentação pública: especificação OpenAPI 2.1.0 do repositório https://github.com/hostinger/api (`openapi.json`) e https://docs.hostinger.com/api-reference/overview. **Nenhuma chamada foi feita** e nenhum token foi usado; a listagem da VM e das métricas reais ficou **não verificada, exige credencial** (comandos abaixo).

Base: `https://developers.hostinger.com`. Autenticação: `Authorization: Bearer <token>` (esquema `apiToken`, http bearer). Token gerado no hPanel, em API. Em `bin/hostinger.sh` o token vem do `admin.env` e nunca vai para argumento de linha de comando ou log.

| Pergunta | Resposta | Evidência |
|---|---|---|
| Listar VMs e achar o id | `GET /api/vps/v1/virtual-machines` devolve lista com `id`, `hostname`, `state` (`running`, `stopped`, `recovery`, `restoring`, ...), `actions_lock` (`unlocked`/`locked`), `plan`, `cpus`, `memory`, `disk`, `bandwidth`, `ipv4`, `ipv6`, `template`, `created_at`. Detalhe de uma: `GET /api/vps/v1/virtual-machines/{virtualMachineId}` (mesmos campos). | openapi.json, operações `VPS_getVirtualMachinesV1`, `VPS_getVirtualMachineDetailsV1` |
| Métricas | `GET /api/vps/v1/virtual-machines/{id}/metrics?date_from=<ISO8601>&date_to=<ISO8601>` (os dois obrigatórios, ex.: `2025-05-01T00:00:00Z`). Resposta: `cpu_usage` (%), `ram_usage` (bytes), `disk_space` (bytes), `outgoing_traffic`, `incoming_traffic` (bytes), `uptime`; cada um é `{ "unit": "...", "usage": { "<unix_ts>": valor } }` e pode ser `null`. Erro de data: 422 com `errors`. | `VPS_getMetricsV1`, schema `VPS.V1.Metrics.MetricsCollection` |
| Criar snapshot | `POST /api/vps/v1/virtual-machines/{id}/snapshot`, sem corpo. **Sobrescreve o snapshot existente.** Resposta é uma ação: `{ id, name, state, created_at, updated_at }` com `state` em `success`, `error`, `delayed`, `sent`, `created`. Acompanhar com `GET .../actions/{actionId}`. | `VPS_createSnapshotV1` |
| Ler o snapshot atual | `GET /api/vps/v1/virtual-machines/{id}/snapshot` devolve `{ id, restore_time, created_at, expires_at }`. | `VPS_getSnapshotV1` |
| Restaurar snapshot | `POST /api/vps/v1/virtual-machines/{id}/snapshot/restore`, sem corpo, resposta de ação (mesmo formato). A VM passa por `restoring`. Destrutivo: volta o disco ao instante do snapshot. | `VPS_restoreSnapshotV1` |
| Reiniciar | `POST /api/vps/v1/virtual-machines/{id}/restart` (para e inicia; se estava parada, inicia). Resposta de ação. | `VPS_restartVirtualMachineV1` |
| Modo de recuperação | Entrar: `POST /api/vps/v1/virtual-machines/{id}/recovery` com corpo JSON `{ "root_password": "<senha temporária>" }` (obrigatório; 422 se faltar). Sobe imagem de recuperação com o disco original montado em `/mnt`. Sair: `DELETE /api/vps/v1/virtual-machines/{id}/recovery` (falha se não estiver em recuperação). Ambos devolvem ação. | `VPS_startRecoveryModeV1`, `VPS_stopRecoveryModeV1` |
| Quantos snapshots a VPS guarda? | **Um só.** O caminho é singular (`/snapshot`) e a doc avisa que criar novo sobrescreve; o campo `expires_at` indica validade, cujo prazo a spec não informa (ver na leitura real). Há também `GET /backups` e `POST /backups/{backupId}/restore` (backups automáticos do plano, outro mecanismo). | `VPS_createSnapshotV1` (descrição), `VPS_getBackupsV1` |
| Códigos de erro | 401 e 500 com `{ message, correlation_id }`; 422 com `errors` por campo. | openapi.json |

## Verificação pendente (exige credencial)

Somente leitura, com o token do `admin.env` carregado no shell, sem eco: `GET /api/vps/v1/virtual-machines` (conferir qual `id` é a `stack`, `state` e `actions_lock`), `GET .../snapshot` (conferir `expires_at`) e `GET .../metrics` com janela de uma hora.

## Decisão

**PROVISÓRIA** (nada chamado). Subcomandos de `bin/hostinger.sh` (Task 14), todos com `Authorization: Bearer`, id da VM em variável de ambiente:

| Subcomando | Método e caminho | Campo lido |
|---|---|---|
| `status` | `GET /api/vps/v1/virtual-machines/{id}` | `state`, `actions_lock` |
| `metricas` | `GET /api/vps/v1/virtual-machines/{id}/metrics?date_from=&date_to=` | `cpu_usage.usage`, `ram_usage.usage`, `disk_space.usage` (último timestamp) |
| `snapshot` | `POST .../snapshot` (avisar que sobrescreve; exigir `--sim`) | `id`, `state` da ação |
| `snapshot-info` | `GET .../snapshot` | `created_at`, `expires_at` |
| `restaurar` | `POST .../snapshot/restore` (exigir confirmação explícita) | `id`, `state` da ação |
| `reiniciar` | `POST .../restart` | `id`, `state` da ação |
| `recuperacao on` / `off` | `POST` (com `root_password` gerada na hora e mostrada uma vez, nunca gravada) / `DELETE .../recovery` | `id`, `state` da ação |
| `acao <id>` | `GET .../actions/{actionId}` | `state` até `success` ou `error` |

Como só existe um snapshot, o fluxo seguro é `snapshot-info` antes de `snapshot` e registrar a data do que será sobrescrito. Limite de taxa não consta na spec; tratar 429 com espera.
