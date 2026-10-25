# Prompt 03: alinhar um projeto existente ao padrão da stack

**Quando usar:** ao pegar um projeto existente e querer o mínimo do padrão (STATE.md, AGENTS.md, comando de CI), sem mudar a arquitetura dele.
**Onde colar:** OpenCode ou Claude Code, com a sessão aberta **dentro da pasta do projeto**.
**O que ele faz:** só lê e propõe. Não altera nada sem o seu "sim".

---

```
Você vai alinhar ESTE projeto existente ao padrão mínimo da stack, SEM mudar a arquitetura, a linguagem ou as dependências dele.
Regras: não altere nada até eu escrever "aplique"; nunca faça push nem abra PR; nunca imprima valores de segredo; não aplique o bootstrap de projeto novo (/novo-projeto) a um projeto existente.

PASSO 1: leitura
Leia README, AGENTS.md/CLAUDE.md (se houver), STATE.md (se houver), a estrutura de pastas e o histórico recente (git log --oneline -15).

PASSO 2: STATE.md
O PMO lê um STATE.md na raiz com exatamente estes campos em negrito, um por linha:
  **Tipo:** app | site | agente | dados | infra | documento | conhecimento
  **Estágio:** ideia | em andamento | em revisão | entregue | encerrado | parado
  **Próximo passo:** uma frase objetiva
Se não houver STATE.md, proponha um com valores reais deduzidos do projeto (não invente; se não souber, escreva "A DEFINIR"). Se houver, aponte o que falta ou está desatualizado.

PASSO 3: AGENTS.md
Proponha um AGENTS.md curto (se não houver) com: o que o projeto é, como rodar, como testar (o comando único de CI), convenções que já existem no código e o que NÃO mexer. Sem texto genérico: só o que você viu no repositório.

PASSO 4: segurança básica (somente relatório)
Procure, sem imprimir valores: arquivos .env versionados, chaves em código, credenciais em fixtures, dados reais de cliente em exemplos. Liste só arquivo e tipo do problema.

PASSO 5: proposta
Entregue a lista de arquivos a criar/alterar e o texto de cada um. Termine com "Aplico?". Só após o meu "aplique", crie a branch chore/padrao-projeto, faça as mudanças com commits em português (conventional) e pare antes de qualquer push.
```
