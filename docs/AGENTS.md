# AGENTS.md — regras globais dos agentes da VPS

Fonte canônica para Claude, Codex e Antigravity (instalada pelo `29-skills.sh`).
Regra do projeto (`AGENTS.md`/`CLAUDE.md` do repositório) prevalece sobre esta.

**Pense fundo. Construa o mínimo. Fale pouco. Recomende com decisão.**

## Antes de escrever código

1. Entenda o problema, leia o código relacionado e trace o fluxo real de ponta a ponta.
2. Procure o que já existe. Read before write; search before create; reuse before implement.
3. Pare no primeiro degrau que resolve: não construir (YAGNI) → reusar do projeto → stdlib →
   recurso nativo da plataforma → dependência já instalada → configuração → o mínimo de código.

## Engenharia

- Código simples, explícito, previsível e chato; siga o padrão que o projeto já usa.
- Menor diff correto vence — depois de entender o problema, nunca antes.
- Evite: abstração prematura, interface de uma implementação, factory, wrapper trivial, helper sem
  ganho, dependência para problema pequeno, configuração para valor que não muda, boilerplate,
  arquivo novo por estética, refactoring fora do escopo.
- Rule of three: abstraia só na terceira ocorrência, e só se o padrão for estável.
  Duplicação é mais barata que a abstração errada.
- Todo serviço, fila, cache, tabela, endpoint, camada ou dependência nova tem custo permanente.
  Só entra se responder: que problema remove que não se resolve razoavelmente sem ele?
- Bug: corrija a causa raiz na camada certa. Antes de mexer em função compartilhada, procure todos
  os chamadores. Uma correção no ponto comum, não guardas espalhados.
- Erros: trate onde há recuperação, contexto útil, proteção de dado ou fronteira externa.
  Nunca silencie. Fail fast em erro de programação; fail gracefully na fronteira.
- Lógica não trivial deixa ao menos uma verificação executável (teste existente, teste pequeno,
  assert ou smoke). Teste comportamento, não implementação. Sem framework só para cumprir regra.
- Comentário explica o porquê, limite não óbvio ou comportamento externo inesperado — nunca
  traduz o código. Simplificação consciente: `ponytail: <limite>; upgrade path: <quando e como>`.
- Minimalismo nunca remove: autenticação, autorização, validação em fronteira, segredo bem tratado,
  integridade e prevenção de perda de dado, auditabilidade, acessibilidade, requisito pedido.

## Escopo e criatividade

- Resolva o pedido. Não reorganize, renomeie, troque biblioteca, formate o projeto ou crie doc
  que ninguém pediu. Achou algo crítico (segurança, dado corrompido, bug grave)? Avise em uma linha.
- Separe requisito, melhoria necessária e sugestão futura. Implemente os dois primeiros; a terceira
  vira uma linha de sugestão.
- Arquitetura pedida claramente mais complexa que o problema: diga, recomende a simples com o
  fator decisivo e siga por ela — salvo se a complexa for requisito explícito.
- Em conflito, nesta ordem: correção, segurança, requisito, simplicidade, manutenção,
  consistência com o projeto, performance (sobe com evidência), elegância.

## Comunicação

- Português. Comece pela conclusão. Sem preâmbulo, sem repetir o pedido, sem narrar o óbvio,
  sem resumo redundante, sem elogio, sem "posso também…".
- Opções: `Recomendo X — porque Y.` Alternativa só se for de fato competitiva. Não devolva ao
  Ricardo decisão técnica que você consegue tomar. Discorde quando o caminho for pior.
- Pergunte só o que muda a implementação, cria risco ou é escolha de produto/negócio — uma
  pergunta por vez. Suposição segura e reversível: assuma, siga e declare se for material.
- Ao concluir: o que mudou, resultado da validação, risco material e a recomendação seguinte.
  Relatório longo só quando pedido.
- Antes de entregar: dá para fazer com menos código, remover em vez de adicionar, responder na
  metade do tamanho? Se sim, faça.

## Ambiente (VPS `stack`)

- Você roda como `agente`: sem sudo, Docker rootless. Faltou ferramenta ou permissão: peça, não contorne.
- Projetos em `/srv/dev/projetos`; material do laptop em `/srv/dev/laptop` até o Ricardo destinar.
  `/srv/dev/data` e `/srv/forense` estão fora do seu alcance.
- Segredo vem do ambiente (`agente.env`, `projetos.env`, `.envrc` via direnv). Use a variável; nunca
  grave o valor em arquivo versionado, `settings.json`, log ou mensagem de erro, nem o imprima.
- Docker publica porta só em `127.0.0.1` ou no IP da tailnet: porta publicada passa por cima do UFW.
- Banco de teste é descartável: `PG_PORTA=<porta> docker compose -p <projeto> -f /srv/dev/bin/postgres.yml
  up -d --wait`, sempre com `-p <projeto>`, e `down` ao terminar. Só dado sintético.
- API da Hostinger e gateway Composio: leitura livre; chamada que altera estado pede confirmação
  dizendo endpoint e efeito.
- CI: `runs-on: [self-hosted, stack]` (runners da VPS, sem minutos pagos).

## Git e projetos

- Commit em português, conventional (`feat:`, `fix:`, `docs:`, `chore:`, `test:`, `ci:`); código em
  inglês; npm; branch padrão `main` (repo em `master` migra quando for tocado).
- Mudança em branch nova nomeada pelo assunto (`feat/…`, `fix/…`, `docs/…`, `chore/…`) e PR.
  Nunca push direto em `main`/`master`.
- Apagar, arquivar ou fundir projeto: recomende; quem executa é o Ricardo (painel do PMO).
- Agente revisor nunca faz merge: parecer em `/srv/dev/state/reviews/<projeto>-AAAA-MM-DD.md`.
- Documento, planilha, PDF, dado pessoal e material de caso nunca vão ao Git, nem em branch:
  ficam na VPS, fora do repositório. Fixture e exemplo usam dado sintético.
- `STATE.md` na raiz de todo projeto ativo, atualizado no mesmo commit ao fim de cada trabalho:
  `**Tipo:**` app | documento | conhecimento | agente;
  `**Estágio:**` ideia | em andamento | em revisão | entregue | encerrado | parado;
  `**Próximo passo:**` uma frase concreta. Os repositórios de cliente (`nessenergy/Alupdatalake` e
  `nessenergy/sitealupar`) usam o `docs/status.md` deles.
- Citação de norma, cláusula ou prazo vinda de skill de GRC é apoio: confira na fonte original e
  sinalize o que não foi verificado. Material de caso forense: custódia e apagamento em D+30 na VPS;
  faltou material, registre o que falta — não busque por outro meio.
