# Development Hub — estado e continuidade (2026-10-16)

> **Direção atual:** docs/superpowers/specs/2026-10-18-lugar-de-trabalho-design.md (lugar de trabalho: OpenCode, 9router, PMO em uma página).

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
- Projetos podem ser software, análise, GRC, forense, docs ou arquitetura. Bootstrap, perfis GCP/Vercel/Cloudflare/fora-das-nuvens e escolha de stack são **somente para novos projetos**. Existentes permanecem intactos.
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
- **PR #7:** decisão de retirar Coder. Embora material legado e scripts de runners possam permanecer no repositório, não reintroduzir Coder, GitHub Actions ou runners como dependência do MVP. Status real de desinstalação na VPS requer inspeção. **REVISADO em 2026-10-19:** a parte dos runners foi superada, eles voltam como CI sem créditos (`docs/superpowers/specs/2026-10-19-ci-sem-creditos-design.md`); o Coder continua fora.
- Origem da verdade é o GitHub **e** o estado operacional da VPS, que podem divergir; planos antigos em `docs/superpowers` são históricos, não necessariamente implementação atual.

## Próximas ações recomendadas

1. **Revisar tecnicamente a Fase 2** (`feat/pmo-painel-sessoes`) versus Fase 1: agregação, nulls, defasagem, vazamento de metadados, preservação ao arquivar/classificar e UI. Verificar se a implementação de `pmo/painel.py` coleta dados via `sessoes.json` como `agente` (permissão 0600) e não exige que processo `pmo` leia esse arquivo.
2. Confirmar resultados dos testes em ambiente controlado; criar/atualizar PR de Fase 2 com base coerente e deixar **sem merge/deploy** até aprovação.
3. Após revisão, planejar a ativação do coletor no timer diário e o deploy seguro do PMO, com rollback e compatibilidade com o código instalado. Não mexer em segredos/sudoers.
4. Mais tarde: validar continuidade no segundo computador; Project Factory no PMO; freeze; avaliações de modelos e agentes.

## Procedimento para retomar contexto

Antes de recomendar ações: leia este documento, os PRs #8/#9, compare as branches da Fase 1/Fase 2 com `main`, e confirme o estado real da VPS quando uma decisão depender de runtime. **Pergunte só o dado que não puder ser determinado**. Seja direto em pt-BR; entregue prompts operacionais curtos quando solicitados.

## Atualização 2026-10-16 — aceleração da entrega (execução OpenCode)

- **Validação final executada na VPS** (somente leitura): Fase 1 ⊂ Fase 2 provada por ancestralidade (`feat/pmo-opencode-sessoes` ancestral de `feat/pmo-painel-sessoes`); suíte `pmo/tests` **120/120 OK** com `-W error::ResourceWarning` na branch da Fase 2 (`93e1f23`); fusões simuladas pela base (`merge-tree`): **0 conflitos** para #9↔main, #11↔main e #11↔#9; árvore final do merge sequencial simulado (`merge-tree --write-tree origin/main feat/pmo-painel-sessoes` → `23202958`): `pmo/` idêntico à branch e **doc preservado**. Conteúdo real: #9 = 3 arquivos, #11 = 5 arquivos (+230/−4); **0 segredos/dados de produção** nos 7 commits (1 hit falso = fixture sintético de path-traversal em `test_sessoes.py`).
- **Buraco real corrigido na revisão final da Fase 2** (`93e1f23`): itens de sessão que não são dicionário derrubavam a geração (`AttributeError`) — reprovado por execução antes da correção; regressão incluída. Defasagem com datas sem timezone/incompatíveis provada contida.
- **Fase 4 preparada** (branch `feat/pmo-fase4-coleta-sessoes`, **PR #12** empilhado em #11): `ExecStartPre=-/usr/bin/python3 -m pmo.sessoes` em `pmo-coleta.service` (o travessão faz o systemd ignorar falha — a coleta diária nunca é bloqueada; `rodar()` também nunca sai com erro, provado com `OPENCODE_BIN=/bin/false` → exit 0) + `Environment=HOME=/home/agente`; ordem Pre→ExecStart dá fusão fresca na mesma corrida (elimina defasagem ≤ 24 h). `systemd-analyze verify` exit 0. Nada tocado em serviços: **ativação só ocorre no deploy da unidade**.
- **Sequência de merge preparada**: #9 → main; retarget do #11 → main; #11 → main; retarget do #12 → main; #12 → main. Histórico linear: Fase 1 (3 commits) ⊂ Fase 2 (7) ⊂ Fase 4 (8).
- **Plano de implantação** (mecanismo existente, idempotente): aprovar merges → `git fetch` → `sudo ./34-pmo.sh` (instala `pmo/` + unidades, `daemon-reload`, reinicia `pmo-servidor`; **não apaga state**) → validar `sessoes.json` 0600 + painel fundido na tailnet → primeira corrida `systemctl start pmo-coleta.service` (autorização separada). **Rollback**: (a) cirúrgico — remover a linha `ExecStartPre` de `/etc/systemd/system/pmo-coleta.service` + `daemon-reload`; (b) completo — `git revert` dos merges e novo `34-pmo.sh` (re-provisiona release anterior; state nunca tocado). Gatilho de rollback: painel 503 persistente ou geração falhando 2 corridas seguidas (painel antigo fica de pé pela gravação atômica enquanto isso).
- **Aguardando aprovação explícita**: merges (#9 → #11 → #12, docs incluídos), retargets de base, deploy (`sudo ./34-pmo.sh`, root) e primeira corrida do coletor.
- Testes reportados pelo executor e reexecutados na VPS nesta validação: 120/120 (duas corridas, com e sem `-W error::ResourceWarning`).

**Este documento registra decisões, não autoriza merge nem deploy.**

## Estado em 2026-10-18 (antes do redesenho)

Levantamento somente leitura na VPS, sem segredo e sem URL de pareamento. Nada foi instalado, reiniciado ou apagado.

- **Clone de trabalho** `/srv/dev/projetos/STACK-VPS`: branch `feat/29-skills-superpowers`, 26 commits atrás de `origin/main`, árvore limpa (só `__pycache__`).
- **Instalado x fonte**: `/opt/pmo` é idêntico a `/opt/stack-vps/pmo` (só difere `__pycache__`). O `pmo-coleta.service` instalado já tem `ExecStartPre` (coletor de sessões ativo), então os PRs #9, #11 e #12 estão instalados. Não foi possível ler o git de `/opt/stack-vps` (propriedade root, "dubious ownership"); nenhuma configuração foi alterada.
- **Ativos hoje**: `opencode-web` (usuário `agente`), `pmo-servidor`, `pmo-coleta.timer`, `cloudflared`, `tailscaled` e `stack-rede-containers`. Pacote `sysbox-ce 0.7.1` instalado. ~~Nenhum container Docker rodando~~ (errado: só conferi o Docker rootless do `agente`; o Docker do sistema tinha 6 containers, ver "Atualização 2026-10-19"). `~/.continue` existe no `agente`. `tailscale serve` sem configuração.
- **Alcance**: é isso que as remoções da Task 16 e o deploy da etapa 2 vão tocar.

## Atualização 2026-10-19 — Docker do sistema, runners e CI sem créditos

- **Correção:** o Docker do sistema tinha **6 containers**: Coder (`coder-coder-1`, `coder-database-1`) e 4 runners do GitHub
  (`runners-nessenergy-runner-1/2`, `runners-bekaa-trusted-advisors-runner-1/2`), de pé havia 2 dias.
- **Removidos hoje, com aprovação do dono** (`docker stop` + `docker rm`): os 2 do Coder e os 4 runners.
- **Ficou na VPS:** volumes `coder-b8dec1e8-0db7-492a-88d4-70e382da0439-home` e `coder-e7fd6a59-faa3-4fde-a794-4fe7061b08cc-agentes`;
  diretório `/srv/coder` (root 0700, com o banco do Coder); imagens `myoung34/github-runner:ubuntu-noble` (3,33 GB), `stack/web`
  (5,28 GB), `ghcr.io/coder/coder:latest` (876 MB), `postgres:17` (646 MB) e `alpine:latest`; redes `coder_default`,
  `runners-nessenergy_default` e `runners-bekaa-trusted-advisors_default`; o container **parado** `coder-ricardo-teste` (workspace do Coder).
  Limpeza em `docs/runbooks/2026-10-remocoes-vps.md`.
- **Túnel:** a rota `coder.ness.com.br` saiu da configuração do tunnel (reexecução do `06-tunnel.sh`, `TUNNEL_EXTRA` vazio). O
  registro DNS na Cloudflare **não** foi apagado (órfão, responde 404).
- **Workflows:** 10 workflows agendados de repositórios privados da conta pessoal foram desligados com `gh workflow disable`
  (lista na spec abaixo).
- **Decisão nova:** o dono não tem créditos de GitHub Actions. Runners na VPS voltam (containers isolados sob a conta `ci`,
  só repositórios privados das organizações), com CI local como padrão e jobs agendados como timers systemd. **Planejado,
  nada implementado ainda.** Ver `docs/superpowers/specs/2026-10-19-ci-sem-creditos-design.md`.

## Atualização 2026-10-25 — estado e processo

**Na VPS (leitura de 2026-10-25, nada alterado hoje):** PMO em socket Unix, OpenCode Web e `tailscale serve` (etapa 2, PR #18 mergeado
em 2026-10-23). `/srv/dev`, `/srv/dev/projetos` e `/srv/dev/state` ainda em 755; o usuário `ci` existe (UID 1003) e hoje leria essas
pastas; `/srv/dev/pareceres` não existe. O usuário `pmo` lê `/srv/dev/projetos` e `/srv/dev/state/pmo/painel.json` mas não está no grupo
`agente`: apertar essas pastas para 750 exige antes `usermod -aG agente pmo` (concessão de acesso, **aguarda o dono**) e reiniciar o
`pmo.service`. Restos do runbook de remoções (sysbox, `stack-rede-containers`, `.continue`, OpenRig, regra 8080 do UFW, imagens/redes/
volumes do Coder) seguem na VPS. Dados do Coder: apagar é irreversível, decisão do dono pendente.

**No GitHub:**
- #18 (lugar de trabalho): mergeado.
- #19 (runners de CI isolados, Tasks 2 a 7): aberto, revisado, **nada instalado**; a Task 8 (instalar e piloto em `bekaa-trusted-advisors`)
  depende de snapshot e aprovação por passo. Decisão do dono (2026-10-23): manter o `RUNNER_TOKEN` (PAT clássico `admin:org`) e aceitar o risco.
- #20 (9router faixa 1 + `/novo-projeto` + 3 templates): aberto, revisado contra o pacote real `9router@0.5.104`, **nada instalado**.
- #16 e #17 (correções do PMO): abertos.

**Decisões vigentes:** 9router e `/novo-projeto` são obrigatórios. 9router só com chaves de API (OpenRouter, DeepSeek, Featherless); as
assinaturas (Claude Code x2, Codex, Antigravity) ficam nos CLIs oficiais do `agente`, fora do 9router (termos da Anthropic, roteamento de
conta automático, CVEs). Conta pessoal sem runner; CI local como padrão.

**Processo de entrega (como estamos trabalhando):** spec e plano por etapa em `docs/superpowers/`; execução por subagentes com revisão
por task, revisão final da branch e re-revisão das correções; PR por etapa; na VPS, um passo por vez, com snapshot antes de mudança
destrutiva e aprovação do dono a cada comando que altere estado. O classificador do Claude Code barra por conta própria merge de PR e
concessão de acesso (grupo/ACL): esses passos ficam com o dono.

**Próximos passos, em ordem:**
1. Dono: merge de #19 e #20; criar o snapshot no hPanel.
2. VPS: `usermod -aG agente pmo` (dono), aperto 750/751 de `/srv/dev`, criar `/srv/dev/pareceres`, restart do `pmo.service`.
3. VPS: remoções do runbook (cada bloco com aprovação; Coder só com decisão sobre backup).
4. VPS: piloto de CI (Task 8): 38, 39, 40 com `bekaa-trusted-advisors`.
5. VPS: spike do 9router (`requireApiKey` no painel, túnel embutido desligado, permissão de `~/.9router`), depois `41-9router.sh`.
6. Dono: logins `claude`, `codex`, `agy` no `agente`; escolher o modelo padrão do OpenCode.
7. Depois: timers dos jobs agendados parados (backup do `n.360-alternative` primeiro), `@ness/auth` (opcional), espelho no Linear (chaves).

**Go-live:** o roteiro por fases (portões, quem faz, rollback) está em `docs/runbooks/2026-10-go-live.md`; o critério de pronto é o `bin/stack-doctor` sem `FALTA`. Nada dele foi executado na VPS.

## Atualização 2026-10-25 (noite) — execução na VPS

- **Feito com aprovação do dono:** `usermod -aG agente pmo`; `/srv/dev` 751, `projetos` e `state` 750, `/srv/dev/pareceres` criado (agente, 750);
  Coder apagado por completo sem backup (container de teste, 2 volumes, `/srv/coder`, rede e imagens `coder`/`postgres:17`); restos dos runners
  (redes, imagem, `/srv/runners`); Continue, OpenRig (pacote, estado, linhas do `.bashrc` com backup), sysbox (pacote; Docker reiniciado sem
  containers) e a regra 8080 do UFW.
- **Não feito:** `stack-rede-containers` (barrado pelo classificador como enfraquecimento de segurança; precisa de autorização explícita do dono;
  hoje sem efeito, não há containers de terceiros no Docker do sistema) e a imagem `stack/web` (5,28 GB; decisão do dono).
- **`stack-doctor` na VPS (leitura):** 29 ok, 1 pend, 16 FALTA. O CI (conta `ci`, regra de rede, `stack-ci-runners`, `status.json`) já aparece
  instalado e fresco: foi feito fora desta sessão. Faltam o 9router (aguarda merge do #20 e as chaves pelo `43-segredos-guiado.sh`), o clone de
  `/opt/stack-vps` fora do `main` e o login do `agy`.
- **PRs:** #19 mergeado; #20 e #21 abertos (#21 empilhado sobre #20); #16 e #17 abertos.

## Atualização 2026-10-25 (9router no ar)

- **9router 0.5.104 instalado e ativo** (`127.0.0.1:20128`; painel só na tailnet em `https://stack.tail985643.ts.net:20128`). `9router.env`
  gerado com `43-segredos-guiado.sh 9router --gerar` (senha e `JWT_SECRET` nunca impressos). A unidade precisou de `Environment=PATH` com os
  shims do mise (o shebang `env node` caía no `/usr/local/bin` do dev: "Permission denied").
- **Fatos medidos:** `GET /v1/models` é público (catálogo embutido); a exigência de chave vale para `POST /v1/chat/completions` (sem chave: 401).
  `requireApiKey` é `true` por padrão; `tunnelEnabled` é `false` e `tunnelDashboardAccess` foi posto em `false` pela API do painel.
- **Chave de API `stack-vps`** criada pela API do painel e gravada em `~agente/.config/9router/client.env` e em `/srv/dev/secrets/agente.env`
  (valor nunca impresso). `opencode-web` reiniciado para enxergá-la; `36-opencode.sh` reaplicado (provedor `9router` com `models: {}` e comando
  `/novo-projeto`).
- **Imagem `stack/web` removida:** era a imagem de workspace do Coder (usuário `coder`).
- **`stack-doctor` na VPS:** 45 ok, 1 pend, 1 FALTA (`/opt/stack-vps` fixado na branch do go-live; volta ao `main` após o merge do #20 e do #21).
- **Falta (dono):** cadastrar no painel os provedores (OpenRouter, DeepSeek, Featherless; nenhuma conexão cadastrada ainda), acrescentar os
  modelos ao `opencode.json`, logins de `claude`, `codex` e `agy`, escolher o modelo padrão, merge do #20 e #21, autorizar a remoção do
  `stack-rede-containers`.
