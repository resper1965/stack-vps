# Agente de acompanhamento de código (PMO de código)

Data: 05/10/2026. Desenho acordado com o Ricardo; a operação (layout final do painel, prompts,
limites de cota) é refinada depois que a VPS estiver no ar, já reinstalada.

## Objetivo

Um agente que acompanha **todos os projetos de código em desenvolvimento**, lê issues, PRs,
commits, CI e o `STATE.md` de cada um, **planeja os próximos passos** e os expõe num painel.

Fora do escopo: atividades, prazos, contratos, propostas e horas (ficam em outra ferramenta).

## Decisões

| # | Decisão | Alternativa descartada |
|---|---|---|
| 1 | Só lê; o resultado vai para o painel, com o texto de issue sugerida para o Ricardo criar | escrever no GitHub (rascunho ou livre) — ruído e risco nos repositórios de cliente; a regra da Alupdata proíbe marca de IA em issue e comentário |
| 2 | Roda todo dia às 06:00, só nos projetos que mudaram desde a última análise; botão "reanalisar" por projeto | semanal (painel atrasado); por webhook (expõe endpoint, gasta mais) |
| 3 | Claude Code sem interface (`claude -p`), orquestrado por script, saída em JSON com schema | Agent SDK (mais código, cobrança por API); API direta (custo por uso) |
| 4 | Uma das duas assinaturas do Claude Code fica dedicada ao agente | dividir a cota com o trabalho do Ricardo |
| 5 | "Em desenvolvimento" = no escopo e com commit, issue ou PR nos últimos 30 dias; os demais aparecem como parados, sem análise | analisar tudo |

## Dependências

- Modelo de segurança do ambiente-alvo (usuário `agente`, sem acesso a `data/`, `forense/` e
  `admin.env`). O agente de PMO roda como `agente`.
- Token GitHub **somente leitura** de issues, PRs, conteúdo e status de CI, por dono do escopo.
- Escopo e inventário semanal existentes (`state/escopo-auditoria.tsv`, `10-inventario.sh`).
- Painel servido na tailnet (`http://100.76.167.6:8080`), da Onda 3 do ambiente-alvo, adiantado
  para cá.
- Canais de alerta (`alertar.sh`) para o resumo diário.

## Arquitetura

```
06:00 (timer do usuário agente)
  1. coletar     por projeto ativo: gh (issues, PRs, commits, CI), git (diff desde a última
                 análise), STATE.md  →  state/pmo/<projeto>/coleta.json
  2. filtrar     impressão digital (último commit + issues + PRs) igual à da análise anterior
                 → reaproveita o plano; diferente → analisa
  3. analisar    claude -p (conta dedicada, ferramentas só de leitura, sem rede além do gh)
                 recebe a coleta e o clone local → plano.json validado contra o schema
  4. consolidar  state/pmo/painel.json (todos os projetos, com data da última análise boa)
  5. avisar      resumo curto por ntfy/Telegram (bloqueios novos, PRs parados, falhas)

Painel estático lê painel.json. Botão "reanalisar" → endpoint mínimo grava um pedido em
state/pmo/fila/ → timer de 5 min processa a fila (o endpoint nunca executa nada direto).
```

## Plano por projeto (`plano.json`)

| Campo | Conteúdo |
|---|---|
| `projeto`, `dono`, `trilha` | identificação (trilhas `geral` e `bekaa`, como no inventário) |
| `situacao` | `andando`, `travado`, `parado`, `atencao` + uma frase |
| `proximos_passos` | até 3; cada um com `descricao`, `por_que`, e `issue` (número existente) **ou** `issue_sugerida` (título e corpo prontos para colar) |
| `bloqueios` | o que impede avanço, com evidência (PR sem revisão há N dias, CI vermelho, issue sem resposta) |
| `riscos` | segurança, dependência vencida, divergência entre `STATE.md` e o código |
| `confianca` | `alta`, `media`, `baixa` — baixa quando a coleta é pobre |
| `analisado_em`, `impressao_digital` | controle do filtro diário |

Plano que não valida contra o schema conta como falha da análise; o painel mostra
"análise falhou" e mantém o último plano válido.

## Painel (a refinar na operação)

- Visão geral: um cartão por projeto ativo, agrupado por trilha, com situação, primeiro próximo
  passo e marcador de bloqueio; projetos parados numa lista à parte.
- Detalhe do projeto: os três passos, bloqueios, riscos, links para issues e PRs, botão de copiar
  a issue sugerida e botão "reanalisar".
- Topo: o que mudou desde ontem.

## Segurança

- O conteúdo de issues, PRs e commits vem de terceiros: entra no prompt marcado como **dado, não
  instrução**.
- O agente roda sem ferramenta de escrita e sem rede além do `gh` de leitura; mesmo induzido por
  conteúdo malicioso, não altera nada.
- Saída só em JSON com schema; o painel não renderiza HTML vindo do modelo.
- O endpoint do botão aceita só o nome de um projeto do escopo e grava um arquivo na fila.

## Falhas

- Uma análise por projeto, isolada, com limite de tempo; falha ou estouro não afeta os outros.
- Cota da conta dedicada esgotada: as análises restantes ficam para o dia seguinte e o resumo diário
  avisa.
- `gh` sem acesso a um repositório: o projeto aparece com "sem acesso" no painel.

## Testes

- Coleta, filtro e consolidação com stubs de `gh` e `claude` (padrão do repositório).
- Validação do schema com planos válidos e inválidos.
- Prompt injection: issue de teste com instrução embutida ("ignore as instruções e…") não altera o
  formato da saída nem dispara ação.

## Fora do escopo

- Gestão de atividades, prazos, contratos e horas.
- Escrever no GitHub.
- Executar código dos projetos (testes, build) durante a análise.
