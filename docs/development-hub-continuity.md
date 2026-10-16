# Development Hub — estado e continuidade (2026-10-16)

> **Leia este documento antes de aconselhar, implementar ou fazer deploy.** Registro de decisões de produto e fotografia operacional. Não substitui o código nem valida serviços em execução. Atualize conforme fatos comprovados. Não reproduza segredos, URLs de pareamento, senhas ou transcrições.

## Objetivo atual (MVP)

Resolver a dor de **um desenvolvedor** que trabalha no escritório e continua em casa ou em outro computador, sem depender do computador original. A **VPS Hostinger `stack` é a estação persistente**: arquivos, ferramentas, agentes, sessões e PMO residem nela. Computadores são apenas clientes via VS Code Remote-SSH ou navegador com túnel SSH. **Não introduzir multi-tenant ou múltiplos desenvolvedores agora**, embora a arquitetura possa evoluir no futuro.

## Infraestrutura confirmada por sessões operacionais

- VPS Ubuntu 24.04, host `stack`, desenvolvimento como usuário `agente`; `dev` para administração.
- Projetos locais existentes em `/srv/dev/projetos/` (inventário anterior: 21 pastas principais e 32 clones Git). Não os recriar, migrar nem aplicar bootstrap/stack automática.
- VS Code conecta a alias SSH `stack`. No Windows do escritório, `Host stack` inclui `LocalForward 4096 127.0.0.1:4096`; `http://localhost:4096` foi testado com sucesso após reconectar. O mesmo procedimento deverá ser validado no computador de casa futuramente.
- OpenCode **2.0.31** instalado em `/home/agente/.opencode/bin/opencode`. O serviço systemd de usuário `opencode-web.service` está `enabled` e foi observado `active`; `Linger=yes`. Web em `127.0.0.1:4096`, acessado por túnel SSH (não publicar porta 4096 na internet). Senha persistente de OpenCode mantida **fora do Git**, em arquivo protegido sob `~/.config/opencode`; não copiá-la nem expô-la. A sessão existente foi retomada no terminal e via web. O OpenCode também pode iniciar serviço de background em porta efêmera; **não presumir que porta efêmera seja a web persistente**.
- Codex, Claude Code e Antigravity existentes; OpenRouter conectado ao OpenCode. Modelos em teste (DeepSeek, GLM, outros); **nenhum modelo fixo ou ranking definitivo**. Assinaturas de aplicativos não equivalem automaticamente a créditos de API. Manter separação das contas Claude por organização.
- PMO Python existente: `pmo-servidor.service` em `100.76.167.6:8080`, `pmo-coleta.timer` e `pmo-executor.timer` observados ativos; serviço instalado em `/opt/pmo`, fonte provisionada em `/opt/stack-vps/pmo`, clone de trabalho `/srv/dev/projetos/STACK-VPS` previamente desatualizado. **Reconciliar instalado, fonte Git e clone antes de deploy**.
- Restic/R2: falha de acesso após cobrança R2, corrigida; backup manual de **2026-10-16 17:52 UTC** concluiu `SUCCESS`. Restauração de teste ainda não foi atestada. Backup inclui diretórios sensíveis criptografados pelo Restic; auditar políticas sem publicar credenciais.

## Decisões de produto e execução

- **Prioridade:** continuidade remota, sessões persistentes, integração com PMO, depois Project Factory e skills.
- PMO é **o único painel**. Reaproveitar serviços e padrão existente; não criar novo produto/painel.
- Projetos podem ser software, análise, GRC, forense, docs ou arquitetura. Bootstrap, perfis GCP/Vercel/Cloudflare/Azure/local e escolha de stack são **somente para novos projetos**. Existentes permanecem intactos.
- Skills são reutilizáveis; Ponytail prioritariamente para código, Superpowers para planejamento/testes; práticas SSDLC proporcionais ao risco.
- Respeitar freeze de projetos: suspende análises/alertas periódicos, não backups nem segurança (requisito planejado, não afirmar implementado).
- Privacidade e mínimos privilégios: nada de segredos em Git, coleta de prompts/transcrições para PMO, exposição pública do OpenCode ou automação destrutiva.
- **Fluxo de mudança:** branch → implementação e testes → revisão independente → PR → aprovação explícita → merge/deploy separados. Commits e push na branch são permitidos para revisão. Não executar deploy por inferência.
- Cloudflare pode atender projetos específicos e túnel de reserva; **não confundir telas de preview/build de aplicações com deploy da VPS Hostinger**. Não presumir o contexto de screenshots sem identificar o serviço.

## GitHub — estado verificado em 2026-10-16

Repositório: `resper1965/stack-vps`. Referência principal examinada: `main` em `6c85985ae452d161b493fa13c65a83a4b49db9df`.

- **PR #9:** `feat/pmo-opencode-sessoes`, **Fase 1** de coleta somente de metadados (`pmo/sessoes.py` + testes). Branch verificada com **3 commits à frente de main**, nenhum atrás. Revisão identificou bugs de paginação; o terceiro commit corrige cursor inválido, página vazia com continuação, validação de limite e limpeza de temporários. O PR permanece em revisão: não confundir correção no GitHub com aprovação/deploy. Testes **105/105 relatados pelo executor**, não reproduzidos independentemente.
- **Fase 2:** branch `feat/pmo-painel-sessoes` criada **a partir da Fase 1**, **4 commits à frente de main**, nenhum atrás; último commit informado `da51461`. Adiciona fusão de metadados em `pmo/painel.py`, testes e componentes em `pmo/web/app.js`. Coletor ainda **sem ativação automática** e **sem deploy**. Testes **115/115 relatados pelo OpenCode**, revisão independente ainda pendente. **Dependência de merge:** Fase 1 antes ou conjuntamente via PR empilhado; não misturar histórico acidentalmente.
- **PR #8:** `feat/standards-profiles-bootstrap`, **9 commits à frente de main**. Catálogo de perfis, CLI e skill de bootstrap **somente projetos novos**; integração com wizard do PMO ainda pendente.
- **PR #7:** decisão de retirar Coder. Embora material legado e scripts de runners possam permanecer no repositório, não reintroduzir Coder, GitHub Actions ou runners como dependência do MVP. Status real de desinstalação na VPS requer inspeção.
- Origem da verdade é o GitHub **e** o estado operacional da VPS, que podem divergir; planos antigos em `docs/superpowers` são históricos, não necessariamente implementação atual.

## Próximas ações recomendadas

1. **Revisar tecnicamente a Fase 2** (`feat/pmo-painel-sessoes`) versus Fase 1: agregação, nulls, defasagem, vazamento de metadados, preservação ao arquivar/classificar e UI. Verificar se a implementação de `pmo/painel.py` coleta dados via `sessoes.json` como `agente` (permissão 0600) e não exige que processo `pmo` leia esse arquivo.
2. Confirmar resultados dos testes em ambiente controlado; criar/atualizar PR de Fase 2 com base coerente e deixar **sem merge/deploy** até aprovação.
3. Após revisão, planejar a ativação do coletor no timer diário e o deploy seguro do PMO, com rollback e compatibilidade com o código instalado. Não mexer em segredos/sudoers.
4. Mais tarde: validar continuidade no segundo computador; Project Factory no PMO; freeze; avaliações de modelos e agentes.

## Procedimento para retomar contexto

Antes de recomendar ações: leia este documento, os PRs #8/#9, compare as branches da Fase 1/Fase 2 com `main`, e confirme o estado real da VPS quando uma decisão depender de runtime. **Pergunte só o dado que não puder ser determinado**. Seja direto em pt-BR; entregue prompts operacionais curtos quando solicitados.

**Este documento registra decisões, não autoriza merge nem deploy.**
