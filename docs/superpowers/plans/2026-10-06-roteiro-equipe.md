# Roteiro: equipe na VPS e os itens 1 a 5

Ordem acordada em 06/10/2026 ("do item 1 ao 5, paulatinamente"). Cada etapa ganha o seu plano
detalhado quando começar; esta página é só a sequência e o critério de pronto de cada uma.

| Etapa | Conteúdo | Plano | Pronto quando |
|---|---|---|---|
| 0 | Integrar o PR #3 (30/09) à branch da migração, no modelo `agente`/`dev`, e concluir o PR #4 | `2026-10-06-etapa0-integracao-pr3.md` | `main` com tudo; scripts 22–29 aplicados na VPS como `agente`; testes verdes |
| A | Coder Community + sysbox + runners efêmeros (spec `2026-10-06-equipe-coder-runners-design.md`) | a escrever | workspace de teste do Ricardo abre em `coder.ness.com.br`; job de teste roda num runner efêmero |
| 1 | Entrada e saída de pessoas em um comando (`equipe entrar/sair`) | a escrever | uma pessoa de teste entra e sai, com comprovante; nada sobra no Access, Coder, GitHub, OpenRouter |
| 2 | Auditoria semanal do GitHub (acessos, assentos, proteções) | a escrever | relatório da segunda com assentos ociosos e repositórios sem proteção, por organização |
| 3 | Evidências de ISO 27001 geradas pela operação, registradas no n.iso | a escrever | pacote mensal registrado como evidência dos controles mapeados |
| 4 | Segurança de código contínua nos runners (gitleaks, osv-scanner/trivy, Semgrep) | a escrever | PR de teste com segredo e dependência vulnerável é barrado; achados no painel |
| 5 | `projeto novo` padronizado | a escrever | repositório criado já com CI nos runners, proteção, `AGENTS.md`, `STATE.md`, devcontainer e escopo |

Prazo da equipe: 10 dias a partir de 06/10/2026 — etapas 0, A, 1 e 2 dentro dele; 3, 4 e 5 em seguida.
Pendências que seguem fora deste roteiro: backup próprio (pós-migração), envio do laptop, template
do VS Code, agente de PMO, tokens mínimos, Bitwarden Secrets Manager.
