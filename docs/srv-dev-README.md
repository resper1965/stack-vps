# /srv/dev

Ambiente unico de desenvolvimento. Todo projeto vive aqui; o laptop e so terminal.

## Arvore

```
/srv/dev/
├── repos/{apps,orm,agents,infra}   clones Git — a verdade e o remoto
├── data/                           volumes e datasets — NUNCA versionado, fora do escopo dos agentes
├── state/reviews/                  inventario e pareceres escritos pelos agentes
├── secrets/.env                    modo 600, dono dev — nada de segredo em repositorio
├── skills/                         skills de ambiente (cloudflare-ness)
└── bin/                            health.sh, playwright.yml
```

## Recuperar do zero

A fonte e `github.com/resper1965/stack-vps`. Numa VPS Ubuntu 24.04 recem-criada, como root:

```sh
git clone https://github.com/resper1965/stack-vps && cd stack-vps
./scripts/01-baseline.sh "<chave-publica-ed25519>"
echo 'dev ALL=(ALL) NOPASSWD:ALL' > /etc/sudoers.d/90-dev && chmod 440 /etc/sudoers.d/90-dev
./scripts/02-layout.sh
./scripts/03-tooling.sh
./scripts/05-servicos.sh
# repor /srv/dev/secrets/.env (nao esta no Git, por definicao), depois:
sudo -u dev ./scripts/04-agents.sh
```

Restaurar `data/`, `state/` e `secrets/` vem do restic no R2 — nao dos scripts.

## Regras que valem para os agentes

- `data/` esta fora do escopo: nao ler, nao escrever.
- Escrita livre so em `state/` e em branch nova (`chore/...`). Nada de push em `main`.
- Segredo vem de `secrets/.env` via ambiente do shell, nunca do bloco `env` de `settings.json`.
- API da Hostinger e gateway Composio: leitura livre; qualquer chamada que altere estado para e pergunta antes.

## Pendente

- Cloudflare Tunnel + Zero Trust (token atual so le)
- UFW fechado e sshd endurecido (dependem do tunnel validado)
- Backup restic para R2
