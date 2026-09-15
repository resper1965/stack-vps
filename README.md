# stack-vps

Provisionamento da VPS de desenvolvimento (Hostinger KVM 8, Ubuntu 24.04 + Docker).
Fonte da verdade do ambiente: recriar a VPS é rodar os scripts desta pasta na ordem.

## Ordem

```sh
sudo ./scripts/01-baseline.sh "<chave-publica-ed25519>"
sudo ./scripts/02-layout.sh
```

Etapas seguintes (tunnel, firewall, tooling, agentes) entram conforme validadas.

## Convencao

Todo script e idempotente: rodar de novo nao quebra o que ja existe.
Nada de segredo aqui — segredo vive em `/srv/dev/secrets/.env` (modo 600) na VPS.
