# Development Hub / PMO — UX/UI handoff (2026-10-16)

> **Substituído** por docs/superpowers/specs/2026-10-18-lugar-de-trabalho-design.md (PMO em uma página; as 8 telas não serão implementadas). Mantido como registro.

> Origem: decisões de interface aceitas em conversa com o usuário. **Especificação de produto e navegação, não implementação final ou imagens/mockups anexados.** Consulte também `docs/development-hub-continuity.md`. Não inventar telas já aprovadas nem substituir o PMO.

## Princípio

**Evoluir o PMO Python existente para tornar-se o painel de controle do Development Hub, sem criar segundo dashboard.** MVP para **um único desenvolvedor** com trabalho persistente na VPS Hostinger `stack`, de diferentes computadores, por VS Code Remote-SSH, OpenCode Web e agentes. Interface útil, rica e clara; não trocar a UX por uma página técnica genérica. Mobilidade futura e acesso remoto seguro, sem expor portas.

## Mapa das 8 telas/conjuntos aprovados

1. **Dashboard** — visão geral consolidada de projetos **ativos, congelados, esquecidos**, eventos relevantes, progresso e próximo passo. Preservar classificação, filtros, ações e cartões existentes no PMO. Acrescentar status de sessões OpenCode quando integração aprovada. Não confundir 'congelado' (decisão de gestão) com 'parado/esquecido' (inferência operacional).
2. **Novo Projeto** — assistente guiado pela **natureza**: **Software / Análise / GRC / Forense / Documentação / Arquitetura**. Mostrar questões pertinentes à natureza escolhida, não uma configuração técnica uniforme. Previsão de contexto inicial e workspace persistente. Só criar se usuário confirmar; preview/default sem efeitos destrutivos.
3. **Configuração Técnica** — stack, destino(s) cloud, autenticação e design system conforme natureza do projeto. Suportar Cloudflare, Vercel, Azure, GCP e VPS conforme perfil, inclusive múltiplos destinos quando fizer sentido. **Somente projetos novos** recebem bootstrap automático. Não migrar ou reconfigurar projetos preexistentes.
4. **Detalhe do Projeto** — contexto/objetivo, tarefas e próximos passos, agentes, sessões retomáveis, documentação, progresso, tecnologia e links existentes GitHub/VS Code. Manter arquivamento, classificação, congela/descongela planejados, e rastreabilidade. Retomar OpenCode preferencialmente pelo comando copiado já planejado; não executar ações remotamente sem controles.
5. **Standards & Skills** — catálogo de padrões, versões, referências e skills reutilizáveis por tipo de projeto. Standards propostos na PR #8; seleção guiada, editável e não dogmática. Preservar separação entre padrões e stack de cada projeto.
6. **AI Operations** — panorama de provedores/modelos/LLMs, agentes, sessões, consumo/custo quando disponível, roteamento. **Nenhum modelo obrigatório ou ranking artificial**; configuração dinâmica. Distinguir custo API de assinaturas pessoais e respeitar contas separadas. Não coletar prompts/transcrições para PMO. Dados de custo/telemetria somente quando implementados e autorizados.
7. **Infraestrutura** — saúde VPS, recursos, Tailscale, backup/restauração, segurança, serviços e alertas de operação. Não mostrar credenciais, detalhes sensíveis ou interfaces administrativas não autorizadas. Diferenciar verificação em tempo real de último status coletado.
8. **Integrações** — GitHub, Linear (opcional/Free), Gabi/Hermes e outras conexões futuras; mostrar estado, escopo e o que realmente está conectado. Não instalar novos conectores, atribuir privilégios nem presumir integrações já operacionais.

## Fluxo aprovado de Novo Projeto

`Escolher natureza → perguntas específicas (cloud/stack quando Software, metodologia quando avaliação) → recomendar standards/skills/agentes ajustáveis → revisar alterações → criar workspace/contexto`.

O catálogo do PR #8 é base potencial, **ainda não deployado**. A pergunta de 'qual cloud' não é universal: projetos Forense/GRC/Documento podem não exigir hospedagem. Não fixar soluções tecnológicas; recomendações editáveis e justificadas.

## Estado de implementação versus proposta (não confundir)

- Painel PMO Python existente: UI atual `pmo/web/index.html` e `pmo/web/app.js`, com cartões/detalhes, filtros, ações, links VS Code e GitHub.
- PR #9 (Fase 1): coletor **somente metadados** de sessões; revisão e testes relatados na VPS; não significa que serviço esteja em produção.
- PR #11 (Fase 2): propõe indicador `sessões N`, última sessão e copiar `opencode -s <id>` diretamente no **PMO existente**; branch empilhada sobre #9. Sem ativação automática ou deploy até autorização.
- PR #8: padrões e bootstrap apenas para projetos novos, ainda pendente integração ao Novo Projeto.
- **As oito telas são um desenho de produto aprovado**, não oito páginas implementadas. **Não há neste documento screenshot, mockup pixel-perfect, Figma ou CSS aprovado**. Para fidelidade visual exata, localizar o artefato original ou pedir referência visual; não alegar que existe imagem versionada aqui.

## Princípios de experiência e de implementação

- Interface premium, consistente, navegável, eficiente para uso cotidiano; respeitar o design do PMO existente, sem reescrever sem evidência de necessidade.
- Evolução incremental e testável, reutilizar componentes e `textContent` para dados externos; manter acessibilidade e responsividade.
- Priorizar **Dashboard + Detalhe + Sessões (Fases 1/2)**, depois **Novo Projeto + Configuração + Standards (PR #8)**; AI Ops/Infra/Integrações em etapas incrementais, mostrando só capacidade real.
- Navegação clara e dados honestos: não apresentar módulos planejados como ativos.
- Freeze de projetos é requisito planejado, não recurso entregue. Deve suspender avaliações/alertas operacionais sem cancelar backups/segurança.
- Sessões continuam sob conta `agente`; dados coletados mínimos, sem prompts e credenciais.
- Não ligar/ativar serviço nem alterar `/opt/pmo` por escrever frontend.
- Testar interface responsiva, estados vazios, permissões e regressões antes do merge.

## Próxima entrega UX/UI para o agente

Após o fechamento técnico dos PRs #9/#11, preparar **um plano de implementação incremental dessas telas** a partir do código atual, com mapa de navegação, estado realizado versus planejado, backlog curto e mockups de fidelidade suficiente para aprovação. Evitar codificar oito telas inteiras de uma vez ou fazer deploy por inferência. Entregar Markdown reutilizável em handoff para outras IAs.
