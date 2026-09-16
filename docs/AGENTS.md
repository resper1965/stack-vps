# Convenções do ambiente

Vale para todas as sessões em `/srv/dev`, dos dois agentes.
`AGENTS.md` é cópia deste arquivo — editar um, replicar no outro.

## 1. Estilo de resposta

- Objetivo e direto. Sem preâmbulo, sem repetir a pergunta, sem explicar o que já é conhecido,
  sem resumir o que acabou de fazer.
- Resposta curta por padrão. Longa só quando pedido.
- Nada de listar três opções e empurrar a decisão. **Recomende a melhor**, diga em uma linha por quê,
  e cite a alternativa só se for de fato competitiva.
- Se o caminho escolhido for pior, fale. Discordar é útil; concordar por educação não é.
- Faltando informação para decidir, faça **uma** pergunta — a que realmente destrava.

## 2. Escopo e permissões

- Leitura ampla em `/srv/dev/repos`.
- Escrita apenas em `/srv/dev/state` e em branch nova (`chore/...`). **Nunca** push em `main`/`master`.
- `/srv/dev/data/**` está fora do escopo: não ler, não escrever.
- Apagar, arquivar ou fundir projeto: registrar a recomendação, **não executar**.
- Segredo vem de `/srv/dev/secrets/.env` pelo ambiente do shell. Nunca no bloco `env` de `settings.json`,
  que é texto puro em arquivo versionável.
- API da Hostinger e gateway Composio: leitura livre. Qualquer chamada que altere estado para e pergunta
  antes, dizendo o endpoint e o efeito.

## 3. Papéis

Cada projeto declara no seu `STATE.md` quem é **agente principal** e quem é **agente revisor**.
O principal implementa e abre branch. O revisor nunca faz merge: escreve parecer em
`/srv/dev/state/reviews/<projeto>-AAAA-MM-DD.md`, rodando `ponytail-review` e `ponytail-audit`.

## 4. Convenções observadas

Medido em 16/09/2026 sobre 72 repositórios ativos e 10.352 commits.

| Assunto | Observação | Situação |
|---|---|---|
| Formato de commit | 74% em conventional commits; `feat:` 2874, `fix:` 2525, `docs:` 1113, `chore:` 557 | padrão de fato |
| `test:` e `ci:` | 98 e 90 commits — 1,8% do total | coerente com 44 de 72 repos sem teste |
| Idioma do commit | 2283 em inglês, 1495 em português | **divergente** |
| Gerenciador de pacote | npm 73, pnpm 4, yarn 1 | padrão de fato: npm |
| Branch padrão | `main` 87, `master` 16 | **divergente** |
| Arquivo de agente | `AGENTS.md` em 32 repos, `CLAUDE.md` em 21 | os dois convivem |

Quatro repositórios têm o `origin/HEAD` apontando para branch de trabalho em vez de `main`
(`claude/wordpress-nextjs-migration-plan-zoiRF`, `ccr-25affe9b-xifc4f`, `001-secure-sdlc`,
`001-ad-gateway-sync`). Isso faz clone novo nascer fora da linha principal — vale corrigir.

## 5. Convenções propostas

Proposta minha, não observação. Só vira regra com o seu OK.

1. **Commit em português, código em inglês.** Hoje está meio a meio, e o repositório sob contrato
   (`Alupdatalake`) já exige português. Padronizar elimina a decisão a cada commit.
2. **`main` em todos.** Os 16 em `master` migram quando forem tocados, não numa varredura só.
3. **npm.** É o que 73 repositórios usam; trocar por pnpm sem motivo forte é custo sem ganho.
4. **`AGENTS.md` como fonte, `CLAUDE.md` como cópia.** Os dois agentes leem o mesmo conteúdo,
   e a duplicação some do processo mental.
5. **`STATE.md` na raiz de todo projeto ativo**, atualizado pelo agente principal ao fim de cada trabalho
   relevante — é o que alimenta o painel sem exigir entrada manual.
6. **Sem CI não é pendência por enquanto.** 43 de 72 repositórios não têm CI; tratar isso repo a repo
   agora só geraria ruído. Fica registrado no inventário, sem recomendação, até você decidir a política.

## 6. Trilhas

- **bekaa** — 12 repositórios da `bekaa-trusted-advisors` e correlatos, inventário próprio em
  `state/inventario-bekaa.md`.
- **geral** — os outros 60, em `state/inventario.md`.

## 7. Entregável de cliente

Citação de cláusula, artigo ou prazo vinda das skills de GRC é apoio, não fonte normativa:
conferir contra a norma original e sinalizar no texto o que não foi verificado.
Documento gerado declara no rodapé qual tenant e qual versão do pacote de customização foram usados.
