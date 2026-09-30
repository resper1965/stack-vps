# OpenRig na VPS

O OpenRig faz dois agentes trabalharem como equipe num projeto: cada um numa sessão tmux,
com endereço fixo e fila de tarefas. Aqui ele só **executa o processo que já existe**
(`CLAUDE.md` §3): quem é principal e quem é revisor vem do `STATE.md`, o parecer vai para
`/srv/dev/state/reviews` e o painel semanal lê de lá.

## Peças

```mermaid
flowchart LR
  voce([Você]) -->|rig-dupla / rig send| cli[CLI rig]
  state[STATE.md do projeto] -->|papéis| cli
  cli --> daemon[Daemon OpenRig<br/>/srv/dev/state/openrig]
  daemon --> p[principal<br/>tmux]
  daemon --> r[revisor<br/>tmux]
  p -->|pede revisão do SHA| r
  p --> repo[Repositório<br/>branch chore/...]
  r --> rev[(state/reviews/<br/>projeto-data.md)]
  rev --> painel[13-weekly-review<br/>dashboard.json · painel]
```

- **`rig-dupla`**: lê o `STATE.md`, monta o rig do projeto e sobe. Recusa `main`/`master` e papel `A DEFINIR`.
- **Daemon**: guarda estado e fila. Sobe sozinho no primeiro `rig up`.
- **Seats**: `dev-principal@<projeto>` e `dev-revisor@<projeto>` (ponto no nome vira hífen: `n.pentest` → `n-pentest`).

## Uma tarefa, do pedido ao painel

```mermaid
sequenceDiagram
  actor V as Você
  participant P as principal
  participant R as revisor
  participant S as /srv/dev/state
  V->>P: rig send dev-principal@projeto "faça X"
  P->>P: implementa na branch chore/...
  P->>R: revise o commit <sha>
  R->>R: ponytail-review + ponytail-audit
  R->>S: reviews/projeto-AAAA-MM-DD.md
  R-->>P: veredito + caminho
  P->>P: atualiza STATE.md
  P-->>V: o que mudou, como testar, parecer
  Note over S: rotina semanal lê STATE.md e o último parecer
```

O merge é sempre seu. Ninguém faz push em `main`.

## O que cada script faz

```mermaid
flowchart TD
  a[04-agents.sh<br/>Claude e Codex podem escrever em /srv/dev/state] --> b
  b[14-openrig.sh<br/>instala o CLI, copia os agentes,<br/>tira acceptEdits/Exa/Context7,<br/>anexa as regras do ambiente ao papel] --> c
  c[rig-dupla, por projeto<br/>STATE.md → rig.yaml → rig up]
```

As regras anexadas ficam em `openrig/principal.md` e `openrig/revisor.md`. Editar lá e rodar o `14` de novo.

## Ligado e desligado

| Item | Estado | Por quê |
|---|---|---|
| Papéis pelo `STATE.md` | ligado | uma fonte só, a mesma do painel |
| Escrita em `/srv/dev/state` | ligado | onde o revisor grava o parecer |
| Kernel (agentes extras do OpenRig) | **desligado** | subiria agentes com a config padrão |
| Hooks do Codex | **desligado** | não reescreve o `~/.codex/config.toml` do `04` |
| MCP Exa/Context7 | **desligado** | fora da curadoria do `04` |
| Claude com `acceptEdits`, Codex com `workspace-write` | ligado | postura mínima do OpenRig |

Efeito colateral: o painel do OpenRig não mostra a atividade de seat em Codex.

## Uso

```sh
cd /srv/dev/repos/<arvore>/<projeto>
git switch -c chore/<tarefa>
rig-dupla --plan        # confere papéis e plano
rig-dupla               # sobe
rig tui --shared        # acompanha; Ctrl-b d sai sem derrubar
rig send dev-principal@<projeto> 'Implemente X, peça revisão e me diga como testar.'
```
