# Standards & Skills — versão inicial

O stack-vps **não** substitui o código nem a arquitetura dos projetos existentes. Este catálogo define perfis selecionáveis de implantação e padrões recomendados; alterações reais são propostas e revisadas separadamente.

## Perfis

Selecione um ou mais: `gcp`, `vercel`, `cloudflare`, `azure`, `local`. Um projeto pode usar frontend Vercel e backend Azure, por exemplo.

```bash
python3 scripts/35-projeto-standards.py /srv/dev/projetos/meu-projeto --provider gcp
python3 scripts/35-projeto-standards.py /srv/dev/projetos/meu-projeto --provider gcp --apply
```

Sem `--apply`, apenas apresenta prévia. Com `--apply`, cria exclusivamente `.standards.json` (não sobrescreve arquivo existente). Nenhuma dependência, SDK, secret, deploy, workflow ou código de aplicação é alterado.

## Incorporação em projeto existente

1. Examinar infraestrutura, autenticação, componentes visuais, requisitos contratuais e código já presente.
2. Escolher perfis correspondentes aos **alvos de implantação**, não às linguagens.
3. Gerar `.standards.json` em estado `proposed` e comparar com o projeto.
4. Registrar exceções em `overrides`; validar com o responsável. Não forçar migração de autenticação/design existente.
5. Aplicar melhorias incrementais, com testes e revisão. Atualizar `status` para `adopted` somente após validação.

## Governança

- Instruções globais continuam no `docs/AGENTS.md`; instruções específicas ficam no projeto.
- Preservar `AGENTS.md`, `CLAUDE.md`, `STATE.md` e skills locais existentes.
- `skills/ness-design` é a referência visual já existente, não substituir por cópia.
- Políticas de segurança e autorização não podem ser enfraquecidas por overrides.
- Não distribuir secrets globais a todos os processos. Compartilhar capacidades de leitura via perfis autorizados.
- Evitar GitHub Actions, serviços pagos, novas assinaturas e migrações automáticas.
- O PMO poderá editar `.standards.json` após criar uma interface e validar autorização; este MVP é CLI.
