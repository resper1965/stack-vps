# stack-vps

Provisionamento da VPS de desenvolvimento (Hostinger KVM 8, Ubuntu 24.04 + Docker).
Fonte da verdade do ambiente: recriar a VPS é rodar os scripts desta pasta na ordem.

## Ordem

```sh
sudo ./scripts/01-baseline.sh "<chave-publica-ed25519>"
sudo ./scripts/02-layout.sh
```

Etapas seguintes (tunnel, firewall, tooling, agentes) entram conforme validadas.

## OpenRig (opcional)

`scripts/14-openrig.sh`, como `dev`, depois do `04-agents.sh`. Instala o
[OpenRig](https://github.com/mvschwarz/openrig) e gera a spec `dupla`: principal em
Claude Code e revisor em Codex, sob tmux. Não sobe equipe; o script imprime o comando.

Desvios do padrão do OpenRig, para não colidir com o `CLAUDE.md` e o `04-agents.sh`:

- estado em `/srv/dev/state/openrig`, e não em `~/.openrig`;
- kernel desligado (`OPENRIG_NO_KERNEL=1`), porque ele sobe agentes próprios com a config padrão;
- hooks do Codex desligados: o daemon não reescreve `~/.codex/config.toml`
  (em troca, o painel não mostra a atividade do revisor);
- os perfis não recebem `acceptEdits` via settings nem os MCPs Exa/Context7.

O que continua valendo: o seat Claude é lançado com `--permission-mode acceptEdits`
(postura `floor` do OpenRig), o Codex com `-s workspace-write`, e o daemon grava
confiança do workspace em `~/.claude.json` e a skill `openrig-skills` em `~/.claude/skills`.
Requer Node 22 ou 24; o `03-tooling.sh` fixa `node@24`.

## Convencao

Todo script e idempotente: rodar de novo nao quebra o que ja existe.
Nada de segredo aqui — segredo vive em `/srv/dev/secrets/.env` (modo 600) na VPS.
