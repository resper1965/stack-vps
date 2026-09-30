# OpenRig na VPS

O OpenRig faz o Claude Code e o Codex trabalharem como uma equipe só: cada agente numa
sessão tmux, com endereço fixo, fila de tarefas e um daemon que acompanha tudo.
Aqui a equipe se chama `dupla`: **principal** (Claude) implementa, **revisor** (Codex) confere.

## Peças

```mermaid
flowchart LR
  voce([Você]) -->|rig send / rig tui| cli[CLI rig]
  cli --> daemon[Daemon OpenRig<br/>/srv/dev/state/openrig]
  daemon --> fila[(Fila de tarefas<br/>SQLite)]
  daemon --> p[principal<br/>Claude Code · tmux]
  daemon --> r[revisor<br/>Codex · tmux]
  p -->|pede revisão| r
  p & r --> repo[Repositório<br/>branch chore/...]
```

- **CLI `rig`**: o que você digita.
- **Daemon**: guarda estado, fila e quem está vivo. Sobe sozinho no primeiro `rig up`.
- **Seats**: cada agente é um "assento" com endereço `dev-principal@dupla` e `dev-revisor@dupla`.

## Uma tarefa, do pedido ao resultado

```mermaid
sequenceDiagram
  actor V as Você
  participant P as principal (Claude)
  participant R as revisor (Codex)
  V->>P: rig send dev-principal@dupla "faça X"
  P->>P: registra na fila, implementa na branch
  P->>R: pede revisão do candidato exato
  R->>R: verifica o efeito, roda testes
  R-->>P: aprovado ou com ressalvas
  P-->>V: resultado + como testar
  V->>V: lê, decide o merge
```

O merge é sempre seu. Pelo `CLAUDE.md`, o revisor nunca faz merge e ninguém faz push em `main`.

## O que o `14-openrig.sh` faz

```mermaid
flowchart TD
  a[Checa Node 22 ou 24] --> b[npm i -g @openrig/cli]
  b --> c[Exporta variáveis no .bashrc]
  c --> d[Copia os agentes embutidos<br/>e tira acceptEdits/Exa/Context7]
  d --> e[Gera specs/rigs/dupla/rig.yaml]
  e --> f[Imprime o comando de subida]
```

Ele não sobe a equipe. Só instala e prepara.

## Ligado e desligado

| Item | Estado | Por quê |
|---|---|---|
| Estado em `/srv/dev/state/openrig` | ligado | junto do resto que os agentes escrevem |
| Kernel (agentes extras do OpenRig) | **desligado** | subiria agentes com a config padrão |
| Hooks do Codex | **desligado** | não reescreve o `~/.codex/config.toml` do `04` |
| MCP Exa/Context7 | **desligado** | fora da curadoria do `04` |
| Hook de atividade do Claude | ligado | alimenta o painel |
| Claude com `acceptEdits`, Codex com `workspace-write` | ligado | postura mínima do OpenRig, não dá para tirar |

Efeito colateral: o painel mostra a atividade do principal, mas não a do revisor.

## Uso

```sh
cd /srv/dev/repos/<arvore>/<projeto>
git switch -c chore/<tarefa>
rig up /srv/dev/state/openrig/specs/rigs/dupla/rig.yaml --cwd . --plan   # confere
rig up /srv/dev/state/openrig/specs/rigs/dupla/rig.yaml --cwd .          # sobe
rig tui --shared                                                          # acompanha
rig send dev-principal@dupla 'Implemente X, peça revisão ao revisor e me diga como testar.'
```

`Ctrl-b d` sai do painel sem derrubar nada. `rig ps --nodes --rig dupla` mostra se os dois estão prontos.
