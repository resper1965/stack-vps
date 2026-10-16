---
name: project-bootstrap
description: Aplicar e revisar padrões reutilizáveis em projetos novos ou existentes no stack-vps. Usar quando iniciar ou incorporar projeto GCP, Azure, Vercel, Cloudflare ou VPS; selecionar perfis, autenticação, design system e quality gates sem reescrever código existente.
---

# Project bootstrap

1. Ler `standards/profiles.json`, `standards/README.md`, o `AGENTS.md` e o `STATE.md` do projeto, se existirem.
2. Identificar alvos de implantação reais (um projeto pode ser multi-cloud). Nunca inferir o provedor apenas pela linguagem.
3. Inspecionar autenticação, autorização, design, secrets, testes e deploy existentes. Reutilizar o que já foi implementado.
4. Usar `scripts/35-projeto-standards.py <pasta> --provider <id>` para prévia; solicitar aplicação só quando autorizada (`--apply`).
5. Tratar `.standards.json` como proposta inicial, não conformidade comprovada. Documentar exceções e evitar migrações não solicitadas.
6. Preferir `skills/ness-design` existente. Para identidade: OIDC e sessão server-side são recomendações, não substitutos automáticos de integrações existentes.
7. Não criar GitHub Actions, novas assinaturas, chaves estáticas nem segredos em repositórios.
8. Ao concluir, responder em até cinco linhas: perfis, reutilizações, conflitos e próximo passo recomendado.
