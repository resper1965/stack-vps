# Painel do PMO

Data: 06/10/2026. Desenho acordado com o Ricardo. Amplia `2026-10-05-agente-pmo-design.md` (o agente
que analisa os projetos) com a tela, o alarme de esquecidos e as ações de descartar.

## Objetivo

Um painel onde o Ricardo vê **todos** os projetos, clica para ver o andamento de cada um, é **avisado
quando esquece um projeto** e pode **descartar** o que não vai seguir — e o descarte vale em todos os
lugares. A dor principal é esquecer projeto; a segunda é não enxergar o estágio de cada um.

## Decisões

| # | Decisão | Alternativa descartada |
|---|---|---|
| 1 | Só o Ricardo, só pela VPN: `http://100.76.167.6:8080` | Cloudflare Access na internet (depois, se quiser); equipe (depois) |
| 2 | Descoberta automática de todos os repositórios das organizações do Ricardo + pastas sem git a destinar | cadastro manual de projetos |
| 3 | Tipo e estágio no `STATE.md` de cada projeto; o agente sugere quando faltar | campo só no painel |
| 4 | Alarme de esquecidos: em andamento sem atividade há 14 dias, em revisão há 30 dias, ou sem próximo passo; resumo toda segunda (ntfy + e-mail) | só a visão, sem cobrança |
| 5 | Descartar = arquivar (reversível) ou excluir de vez com confirmação digitando o nome | só arquivar; espera de 7 dias (o GitHub já guarda repositório excluído por 90 dias) |
| 6 | Repositório de organização de cliente (`nessenergy`) só pode ser arquivado pelo painel | permitir exclusão |
| 7 | Coder fora do escopo do painel por ora | — |

## Fontes de dados

| Fonte | O que traz |
|---|---|
| GitHub (`gh`, token de leitura das organizações) | lista de repositórios (inclusive os novos), issues, PRs, commits, CI, branches `wip/…`, arquivado ou não |
| `STATE.md` de cada repositório | tipo, estágio, próximo passo declarado, dono |
| `/srv/dev/projetos` | onde o projeto está na VPS (link "abrir no VS Code") |
| `/srv/dev/laptop` (e, depois, a varredura do WSL) | pastas sem git: seção "a destinar" |
| Agente de PMO (`claude -p`, conta dedicada) | situação, próximos 3 passos, bloqueios, riscos, estágio e tipo sugeridos |

Coleta e análise seguem o desenho do agente de PMO (diária às 06:00, só projetos que mudaram).
A descoberta de repositórios roda junto, todo dia.

## Tipos e estágios

- **Tipo**: `app`, `documento` (consultoria, GRC, propostas), `conhecimento` (skills, métodos, bases),
  `agente`. Para `documento` e `conhecimento` o agente não cobra CI nem teste: olha o que mudou nos
  arquivos, as issues e o checklist do `STATE.md`.
- **Estágio**: `ideia` → `em andamento` → `em revisão` → `entregue` → `encerrado`, mais `parado`.
- No `STATE.md`: `**Tipo:** documento` e `**Estágio:** em andamento`. Vazio: o painel mostra o
  sugerido pelo agente com "confirmar". Trocar: pedir ao agente no projeto ou editar a linha.

## Telas

### Visão geral
- Topo: contadores (em andamento, em revisão, parados, esquecidos, PRs abertos, CI vermelho) e
  "o que mudou desde ontem".
- **Faixa "Esquecidos"** logo abaixo do topo, sempre visível quando houver algum.
- Filtros: pasta (a mesma árvore da `DESENVOLVIMENTO`), tipo, estágio, organização.
- Cartões: nome, tipo, estágio (cor), última atividade, primeiro próximo passo, ⚠ se houver bloqueio.
- Seções à parte: **"A destinar"** (pastas sem git vindas do laptop/WSL) e **"Arquivados"**.

### Detalhe do projeto
- Situação (frase do agente), estágio e tipo (com "confirmar" se sugeridos).
- Próximos 3 passos, cada um com link para a issue ou botão "copiar issue sugerida".
- Bloqueios e riscos com evidência; PRs, issues, últimos commits, CI, branches `wip/…`.
- Linha do tempo simples da atividade (últimas semanas).
- Botões: **Abrir no VS Code** (`vscode://vscode-remote/ssh-remote+stack-agente/srv/dev/projetos/<pasta>`),
  **Abrir no GitHub**, **Reanalisar**, **Descartar**.

Aparência: cuidada (o andamento "bonito" é requisito) — cores por estágio, legível no celular, tema
claro e escuro.

## Alarme de esquecidos

- Esquecido = `em andamento` sem commit/issue/PR há **14 dias**, ou `em revisão` há **30 dias**, ou
  qualquer projeto ativo **sem próximo passo**.
- Toda **segunda 08:00**: resumo por ntfy e e-mail ("5 projetos esquecidos: …" + link do painel).
- No detalhe de um esquecido, o agente propõe: retomar (com o próximo passo), `parado` ou descartar.

## Descartar

Ao clicar em **Descartar**, o painel oferece:

1. **Arquivar** (reversível): GitHub → repositório arquivado (só leitura); VPS → a pasta sai de
   `/srv/dev/projetos` (e da cópia do laptop, se houver) e vai compactada para `/srv/dev/arquivo/`;
   escopo e painel → vai para "Arquivados". **Restaurar** desfaz tudo.
2. **Excluir de vez**: confirmação digitando o nome do projeto; GitHub → repositório excluído
   (o GitHub permite restaurar por 90 dias); VPS → cópias vão para `/srv/dev/arquivo/excluidos/`
   e são apagadas depois de 30 dias.

- Organização de cliente (`nessenergy`): só **Arquivar**.
- Itens "a destinar" (pastas sem git): **Trazer** (vira repositório privado e entra em
  `/srv/dev/projetos`) ou **Descartar** (vai para `/srv/dev/arquivo/excluidos/`, 30 dias).
- Toda ação vai para `/srv/dev/state/pmo/acoes.log` (data, projeto, ação, resultado).
- O laptop fica fora do alcance do painel; no fim da migração a `DESENVOLVIMENTO` do laptop é
  esvaziada de uma vez.

## Arquitetura

- Página estática (HTML/JS, sem framework pesado) + `painel.json` gerado pelo agente/coleta.
- Um serviço pequeno em Python (stdlib) na VPS, ligado só no IP da tailnet, que serve a página e
  recebe as ações (`reanalisar`, `arquivar`, `excluir`, `restaurar`, `trazer`).
- As ações não executam no serviço: viram pedidos em `/srv/dev/state/pmo/fila/`. Um executor
  (timer de 1 min) processa a fila **como `dev`** (tem o token com permissão de arquivar/excluir) e
  registra o resultado. O serviço web roda como usuário sem privilégio.
- Exclusão no GitHub exige token com `delete_repo` no `admin.env`; sem ele, a ação falha com aviso.

## Segurança

- Só pela tailnet; sem login próprio (a VPN é o controle de acesso), por decisão desta etapa.
- O serviço web valida o nome do projeto contra a lista conhecida e grava só arquivos de pedido.
- Exclusão: nome digitado tem de bater exatamente; repositório de `nessenergy` é recusado no executor
  (não só na tela).

## Testes

- Descoberta: repositório novo numa organização aparece no `painel.json`.
- Esquecidos: projeto `em andamento` com último commit há 15 dias entra na faixa; com 13, não.
- Executor: arquivar move a pasta e chama `gh repo archive`; restaurar desfaz; excluir sem o nome
  certo é recusado; excluir repositório `nessenergy` é recusado; tudo com `gh` em stub.
- Serviço web: só aceita ações conhecidas e projetos da lista.

## Fora do escopo

- Equipe no painel (logins e permissões por pessoa).
- Coder no painel.
- Editar `STATE.md` pelo painel (só pelo agente ou à mão).
- Varredura do WSL (entra depois, alimentando "A destinar").
