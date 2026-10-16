# Standards & Skills — escolha para projetos novos

**Projetos existentes permanecem em suas stacks atuais.** Não há migração, adoção retroativa nem exigência de cadastrar seus provedores neste catálogo.

Ao **criar um projeto novo**, escolher um ou mais destinos: `gcp`, `vercel`, `cloudflare`, `azure`, `local`. Essa seleção orienta os agentes e futuros templates, mas não implanta infraestrutura automaticamente.

```bash
python3 scripts/35-projeto-standards.py /srv/dev/projetos/novo-projeto --provider gcp
python3 scripts/35-projeto-standards.py /srv/dev/projetos/novo-projeto --provider gcp --apply
```

O comando aceita somente pasta inexistente ou vazia; a prévia não escreve nada. `--apply` cria `.standards.json`. Não instala dependências nem cria recursos cloud.

## Regras
- Para projetos existentes: manter arquitetura, identidade, design, deploy e código; podem consumir skills pontuais sem serem migrados.
- Para projetos novos: escolher stack e provider no bootstrap; aplicar design e receitas aprovadas conforme necessidade.
- `skills/ness-design` permanece fonte dos padrões de marca.
- Nunca carregar segredos globais indiscriminadamente.
- Sem GitHub Actions, novas assinaturas ou migração automática.
- O futuro PMO pode oferecer um assistente de **Novo Projeto** e apenas **exibir** a stack de projetos existentes, sem alterá-la.
