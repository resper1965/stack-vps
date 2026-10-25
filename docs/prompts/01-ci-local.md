# Prompt 01: adequar um projeto ao CI sem créditos do GitHub

**Quando usar:** ao pegar um projeto existente para tirar a dependência de minutos do GitHub Actions.
**Onde colar:** OpenCode ou Claude Code, com a sessão aberta **dentro da pasta do projeto**.
**O que ele faz:** só lê e propõe. Não altera nada sem o seu "sim" e nunca faz push sozinho.

---

```
Você vai adequar ESTE projeto ao CI sem créditos do GitHub Actions. Trabalhe na ordem e pare onde eu pedir.
Regras que valem o tempo todo:
- Não altere nada até eu escrever "aplique". Antes disso, só leia e proponha.
- Nunca faça push, nunca abra PR, nunca habilite workflow, nunca crie segredo.
- Nunca imprima valor de segredo; cite apenas NOMES de secrets.* e vars.*.
- Não mexa em outros repositórios.

PASSO 1: inventário (somente leitura)
1. Liste .github/workflows/*: para cada arquivo, os gatilhos (push, pull_request, schedule com o cron, workflow_dispatch), o valor de runs-on, os jobs e o que cada um faz em uma linha, e os NOMES dos secrets/vars usados.
2. Descubra o dono do repositório (git remote get-url origin) e se ele é privado (gh repo view --json isPrivate,owner).
3. Descubra como o projeto roda testes hoje (package.json scripts, Makefile, pytest, etc.).

PASSO 2: o comando único de CI
Proponha UM comando que roda tudo que o CI roda (ex.: npm run ci, make ci, bash tests/run.sh). Ele precisa funcionar localmente, sem rede externa além de instalar dependências. Mostre o comando, o que ele executa e se já existe ou precisa ser criado.

PASSO 3: onde o CI roda
Classifique o repositório:
- Conta pessoal (resper1965): sem runner. CI = o comando único do passo 2, rodado pelo agente antes de cada commit e de cada PR. Workflows com runner do GitHub devem ficar desligados.
- Organização com runner da stack (hoje: bekaa-trusted-advisors, forense-io) e repositório PRIVADO: pode usar runs-on: [self-hosted, stack]. Nunca ubuntu-latest em repositório privado.
- Organização nessenergy (clientes): NÃO migrar nada. Pare e me avise.
- Repositório público: runner self-hosted é proibido. Pare e me avise.

PASSO 4: workflows agendados (schedule)
Para cada workflow com schedule, NÃO o reative. Descreva o que ele faz, o cron, quais NOMES de segredos usa e o que precisa para rodar fora do GitHub. Esse relatório vira um "job agendado" da VPS (prompt 02). Diga se é backup, verificação, varredura de segurança ou outro.

PASSO 5: proposta
Entregue um plano com: (a) o comando único de CI e o arquivo a criar/alterar; (b) as mudanças em workflows (runs-on ou desativação), arquivo por arquivo; (c) a linha de CI para o AGENTS.md/README do projeto ("antes de commit e de PR, rode <comando>"); (d) a lista de workflows agendados para virar jobs; (e) os riscos.
Termine perguntando: "Aplico?". Só depois do meu "aplique" faça as mudanças, em uma branch chore/ci-local, com commits em português no padrão conventional. Rode o comando único e mostre o resultado. Pare antes de qualquer push.
```

---

## Depois de rodar
- Revise o diff com `git diff main...chore/ci-local`.
- Faça o push e o PR você mesmo (ou peça explicitamente "faça push e abra o PR").
- Os workflows agendados listados no passo 4 seguem para o prompt 02.
