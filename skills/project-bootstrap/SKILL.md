---
name: project-bootstrap
description: Configurar o início de projetos novos no stack-vps escolhendo GCP, Azure, Vercel, Cloudflare ou VPS, autenticacao, design system e skills. Usar somente na criação de projetos novos; projetos existentes preservam sua stack e podem utilizar skills especializadas sem bootstrap.
---

# Project bootstrap

1. Confirmar que é um projeto **novo**. Nunca aplicar bootstrap ou migração a um projeto existente.
2. Ler `standards/profiles.json` e `standards/README.md`.
3. Escolher um ou mais destinos de implantação explicitamente definidos pelo usuário; não presumir stack pela linguagem.
4. Executar `scripts/35-projeto-standards.py <pasta> --provider <id>` para prévia. Aplicar `--apply` somente no diretório novo/vazio.
5. Selecionar receita de autenticação, autorização e referências de design conforme o novo projeto. Reutilizar `skills/ness-design`.
6. Não criar serviços, assinaturas, chaves ou deploy automaticamente. CI local (`ci: local-vps`); `runs-on: [self-hosted, stack]` só em repositório privado de organização com runner.
7. Para projetos **existentes**, encerrar o bootstrap; respeitar a arquitetura atual e oferecer somente skills pontuais quando solicitadas.
8. Responder de forma breve: provider(s), padrões selecionados e próximo passo.
