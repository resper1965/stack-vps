# CLAUDE.md — complemento para o Claude Code

As regras gerais estão no `AGENTS.md` (instalado logo acima deste trecho). Aqui só o que é do Claude.

## Skills e ferramentas

- ponytail liga pelo hook, em modo full. `/ponytail lite|full|ultra` muda; `/ponytail-review` e
  `/ponytail-audit` revisam diff e projeto.
- superpowers: `brainstorming` antes de construir algo novo; `writing-plans` para trabalho de
  várias etapas; `test-driven-development` em lógica não trivial; `systematic-debugging` antes de
  corrigir bug; `verification-before-completion` antes de dizer que terminou. Ajuste a cerimônia ao
  tamanho: mudança de uma linha não pede spec nem plano.
- Biblioteca, SDK, CLI ou serviço de nuvem: consulte a documentação atual (Context7 ou o MCP de docs
  da plataforma) em vez de confiar na memória.
- Skills de plataforma já instaladas: cloudflare, supabase, vercel, github-actions-hardening,
  github-issues. Use antes de escrever configuração dessas plataformas à mão.

## Trabalho agentic

- Busca ampla (muitos arquivos ou convenções): subagente `Explore`; você fica com a conclusão.
- Chamadas independentes saem juntas, em paralelo.
- Tarefa de várias etapas: lista de tarefas visível; plano longo, registro em arquivo (sobrevive
  à compactação do contexto).
- Saída longa de teste ou build vai para arquivo; leia o final.
- Revisão final de um branch grande: subagente novo, no modelo mais capaz.
- Mudança irreversível ou que sai da VPS (push em branch compartilhada, merge, publicação,
  chamada que altera serviço externo): confirme antes.

## Contas e atribuição

- Duas contas: bekaa (padrão) e ionic (vertical ionic, escolhida sozinha pela pasta).
  `claude-bekaa`/`claude-ionic` forçam.
- Trailer `Co-Authored-By` e "Generated with": só onde o projeto permitir. Os repositórios de cliente
  (`nessenergy/Alupdatalake` e `nessenergy/sitealupar`) proíbem em commit, PR, issue, comentário
  e nome de branch (`claude/*` incluso).
- Memória: nunca guarde segredo, dado pessoal ou material de caso.
