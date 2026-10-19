# Lugar de trabalho — redesenho do stack-vps (spec mestre)

**Data:** 2026-10-18 · **Estado:** proposto, aguardando revisão do Ricardo
**Substitui:** a direção de produto de `docs/pmo-ux-ui-handoff.md` (8 telas, PR #14) e o perfil `azure` de
`standards/profiles.json` (PR #8). `docs/development-hub-continuity.md` segue válido como registro operacional.

## Problema

O projeto cresceu em peças (Coder, runners, OpenRig, comando `modelo`, Continue, painel de 8 telas planejado)
sem um centro. A dor real é outra: **ter um lugar único para trabalhar**, de qualquer computador, onde se
constroem **agentes, pareceres e sistemas** com vários modelos, e de onde os sistemas saem prontos para um de
quatro destinos, com o design system da ness e um caminho único de autenticação.

Recursos disponíveis: 2 assinaturas Claude (bekaa, ionic), 1 ChatGPT, Antigravity, chaves OpenRouter,
DeepSeek e Featherless, API da Hostinger.

## Decisões

| Tema | Decisão |
|---|---|
| Porta de entrada | **OpenCode Web** na VPS `stack`; tudo começa nele. |
| Acesso | **Tailscale**, via `tailscale serve`; serviços escutam em `127.0.0.1`. Fallback em 3 camadas. |
| Modelos | **9router** como gateway único (assinaturas e chaves), **hospedado na própria VPS `stack`**, ao lado do OpenCode; CLIs oficiais como plano B. Spike antes. |
| Projetos | Comando **`/novo-projeto`** no OpenCode; naturezas **sistema, agente, parecer**. |
| Autenticação | Pacote **`@ness/auth`** extraído do niso; SSO OIDC no v1. |
| Authentik | **Opcional e externo** (ness.OS, VPS própria, não pronto); entra como provedor OIDC. |
| Destinos | **Cloudflare, Vercel, GCP e "fora das nuvens"** (VPS, servidor do cliente, on-prem) com **Kamal**. |
| Painel | **PMO em uma página**, fonte da verdade do **ciclo de vida** dos projetos, + saúde + atalhos. |
| Linear | **Lista espelhada** do PMO (conta resper@bekaa.eu): um projeto por linha, só o estágio, PMO → Linear. |
| Avaliação | **promptfoo** no template de agente. |
| Aviso | Sessão do OpenCode concluída → `alertar.sh` (ntfy/Telegram). |

## Arquitetura

```
 Computador / celular ──Tailscale (tailscale serve, HTTPS)──► VPS stack (usuário agente)
                                                               │
   OpenCode Web 127.0.0.1:4096  ◄── porta de entrada
     ├─► 9router 127.0.0.1:20128 ── assinaturas (2× Claude, ChatGPT, Antigravity)
     │                            └ chaves (OpenRouter, DeepSeek, Featherless)
     ├─► CLIs oficiais (claude-bekaa, claude-ionic, codex, agy) — plano B
     ├─► /novo-projeto → /srv/dev/projetos/<nome>  ou  /srv/dev/pareceres/<nome>
     └─► plugin de aviso → alertar.sh

   PMO /run/pmo/pmo.sock (uma página)    Base inalterada: scripts 01–07, 16, restic, vigia-health
```

Princípios: uma porta de entrada; nada público por padrão; segredos continuam em `admin.env`, `agente.env`
e `projetos.env`; a VPS `stack` nunca hospeda sistema de cliente.

## 1. Acesso e fallback

O OpenCode passa a escutar em `127.0.0.1:4096` e o PMO num **socket Unix** (`/run/pmo/pmo.sock`, grupo `pmo`,
fora do alcance do `agente`); os dois são publicados na tailnet por `tailscale serve`. Assim a queda do
`tailscaled` não derruba os serviços — só o caminho até eles.

O socket existe por segurança: o PMO recusa hoje ação vinda de dentro da VPS pelo IP de origem, e com
`tailscale serve` toda requisição chegaria de `127.0.0.1`. Com o socket, quem não está no grupo `pmo` (o
`agente`, os containers) nem consegue conectar.

| Camada | Como | Estado padrão |
|---|---|---|
| 0. Normal | `https://stack.<tailnet>.ts.net` (OpenCode) e `:8443` (PMO) via `tailscale serve` | ligado |
| 1. SSH pelo Cloudflare Tunnel | `ssh stack-cf` com `LocalForward 4096 127.0.0.1:4096` e `LocalForward 8080 /run/pmo/pmo.sock` (tunnel já existe, `06-tunnel.sh`) | ligado |
| 2. Web de emergência | `emergencia.esper.ws` atrás de Cloudflare Access (código por e-mail, sessão de 1 h) + senha do próprio OpenCode; `stack-emergencia on/off` liga e desliga só a rota no tunnel; ligar e desligar geram alerta | **desligado** |
| 3. Hostinger | console pelo navegador; reinício ou modo de recuperação pela API da Hostinger | sob demanda |

O `health.sh` já checa o Tailscale ("tailscale fora da tailnet") e o `vigia-health` já alerta por
ntfy/Telegram, que não dependem da tailnet; entram as checagens do OpenCode e do PMO.

## 2. Camada de modelos (9router)

- **Roda na própria VPS `stack`**, no mesmo ambiente do OpenCode e dos projetos — sem máquina separada.
  Serviço systemd de usuário do `agente` (padrão do `opencode-web.service`), só `127.0.0.1:20128`, versão
  fixada no script; atualizar é trocar a versão e rodar de novo. Novo script substitui `24-modelos.sh`.
- O comando `modelo` **fica** (a skill de pentest depende dele) e passa a falar com o 9router; o catálogo
  `docs/modelos.tsv` vira nomes de modelo do 9router.
- Consumidores: OpenCode (provedor compatível com OpenAI) e promptfoo. CLIs oficiais mantêm login próprio.
- Contas: assinaturas por OAuth no 9router; chaves lidas do `agente.env`. Conta Claude ionic só na vertical ionic.
- Segurança: senha do painel vem do ambiente e o script **recusa subir sem ela**; painel só na tailnet;
  tokens OAuth no home do `agente` (0600), cobertos pelo restic; prompts e transcrições nunca vão ao PMO.
- Risco aceito: uso de assinatura por gateway de terceiros pode ser bloqueado pelo provedor.
- Falha: `vigia-health` checa o 9router; trabalho segue pelos CLIs.

**Spike (resultado descartável) responde:** (1) duas contas Claude convivem? (2) ChatGPT e Antigravity
funcionam? (3) existe senha padrão no código? (4) onde e com que permissão ficam os tokens? (5) termos de uso
de cada provedor. **Se falhar:** modo "duas faixas" — assinaturas nos CLIs, chaves no 9router. O resto do
desenho não muda.

## 3. Fábrica de projetos (`/novo-projeto`)

Comando do OpenCode que conduz a skill `project-bootstrap` (PR #8): **natureza → poucas perguntas → prévia →
confirmação → pasta + `STATE.md` → sessão do OpenCode aberta nela**. Criar repositório privado no GitHub é
confirmação separada. Projeto existente nunca recebe bootstrap.

Templates versionados em `templates/<natureza>/`, copiados (não gerados):

| Natureza | Conteúdo |
|---|---|
| **sistema** | Hono + TypeScript, `skills/ness-design`, `@ness/auth` opcional, um arquivo de deploy por destino |
| **agente** | TypeScript, modelos via 9router, `promptfoo` com `casos/` e um caso que passa |
| **parecer** | Markdown → Typst → PDF/DOCX ness.design; `fontes.md` marca cada citação como verificada ou não. **Conteúdo fora do Git**, em `/srv/dev/pareceres/<nome>` (restic); só o template é versionado |

Análise, GRC, forense e documentação são variantes de **parecer**.

### Destinos

| Destino | Arquivo no template | Dados |
|---|---|---|
| cloudflare | `wrangler.jsonc` | D1 / KV |
| vercel | `vercel.json` | Postgres gerenciado |
| gcp | `Dockerfile` para Cloud Run, sem chave estática de conta de serviço | Postgres (Cloud SQL) |
| fora das nuvens | `Dockerfile` + `config/deploy.yml` do **Kamal** (imagem Docker oficial; nada de Ruby na `stack`) | Postgres acessório do Kamal |

"Fora das nuvens" = qualquer máquina com SSH e Docker (VPS, servidor do cliente, on-prem). Deploy e rollback
saem da `stack` (`kamal deploy`, `kamal rollback`). `standards/profiles.json` troca `local` por `fora-das-nuvens`
e perde `azure`.

## 4. `@ness/auth`

Repositório privado próprio, publicado no GitHub Packages. Middleware e rotas Hono, extraídos de `src/sso.ts`,
`src/middleware/auth.ts`, `src/routes/auth.ts` e `auth-policy.ts` do niso. O niso migra depois, em trabalho
separado.

- **v1:** e-mail e senha, sessão, RBAC que nega por padrão, chave de API, SSO OIDC por tenant com as proteções
  do niso (host público contra SSRF/DNS rebinding, `redirect: 'manual'`, segredo do IdP cifrado, retorno por
  fragmento, mensagens genéricas).
- **v2:** SCIM, política de MFA, lista de IPs. Sobe para o v1 se o primeiro cliente exigir desprovisionamento.
- **Adaptadores de armazenamento:** D1/KV e Postgres.
- **Modos de login por sistema:** sem SSO; SSO direto com o IdP do cliente (Entra ID, Google, Okta via OIDC);
  SSO via **Authentik da ness**, que também faz ponte para clientes só com SAML.
- **Login de emergência:** e-mail e senha só para administradores quando o IdP cair; desligável, sempre na trilha.

## 5. Painel (PMO em uma página) — controle do ciclo de vida

As 8 telas nunca foram implementadas; nada a remover de código. O PMO é **a fonte da verdade do ciclo de vida
de cada projeto**: a visão consolidada de `STATE.md` (escrito pelos agentes ao fim de cada trabalho) mais as
decisões de gestão que só existem no PMO (`/var/lib/pmo`). A página tem três blocos:

- **Projetos — ciclo de vida:**

  | Controle | Origem | Estado hoje |
  |---|---|---|
  | Estágio (ideia → em andamento → em revisão → entregue / encerrado / parado) e próximo passo | `STATE.md` | coletado |
  | Classificação (empresa, área, cliente, tipo) | PMO | existe |
  | Arquivar, restaurar, descartar | PMO (executor) | existe |
  | **Congelar / descongelar** — suspende alarmes e avaliações, nunca backup nem segurança | PMO | **novo** |

  Mais as sessões do OpenCode com "copiar `opencode -s <id>`" (PRs #9, #11, #12). Os alarmes que já existem
  (esquecidos, CI vermelho, PRs) ficam como estão, sem expansão; projeto congelado não dispara alarme.
- **Saúde:** `health.sh`, último backup restic, 9router e OpenCode de pé, Tailscale, e CPU/RAM/disco pela API
  da Hostinger (só leitura).
- **Atalhos:** OpenCode e painel do 9router.

Ferramentas internas ficam só na tailnet. Quando o Authentik do ness.OS existir, ligá-lo nelas é opcional; o
teste do servidor do PMO ganha o caso do `Host` repassado pelo proxy.

## 5b. Espelho no Linear (conta resper@bekaa.eu)

**O Linear é uma lista: um projeto por linha, cada um no seu estágio.** Nada além disso. Sentido único,
PMO → Linear; o PMO decide, o Linear mostra.

- **Quais projetos:** todos os projetos do PMO que não estão arquivados nem descartados. Cada um vira um
  projeto do Linear com o mesmo nome; o vínculo técnico (id do projeto no Linear e último estágio enviado)
  fica em `/var/lib/pmo/linear.json`. O campo `classe.linear` do painel continua sendo o rótulo livre que já é.
- **Único campo espelhado: o estágio**, como status do projeto no Linear, um status por estágio do PMO
  (ideia, em andamento, em revisão, entregue, encerrado, parado, congelado). Se o workspace não aceitar status
  de projeto personalizados, usa o mapeamento para os padrões: ideia → Backlog; em andamento e em revisão →
  In Progress; parado e congelado → Paused; entregue e encerrado → Completed.
- **Não espelha:** próximo passo, descrição, datas, responsáveis, issues. Arquivar ou descartar no PMO marca o
  projeto como Canceled no Linear e encerra o espelho dele.
- **Quando:** `pmo/linear.py` roda depois da coleta diária e após cada ação de ciclo de vida; envia só o que
  mudou. Falha no Linear nunca bloqueia a coleta (mesmo padrão do `ExecStartPre=-` das sessões) e vai para o
  log e o alerta. Status alterado à mão no Linear é sobrescrito na corrida seguinte.
- **Primeira carga:** cria em lote os projetos que faltam no Linear. Roda antes em modo prévia (lista o que
  criaria) e só grava com confirmação.
- **Credencial:** chave de API pessoal do Linear (resper@bekaa.eu) no `admin.env`, lida pelo serviço do PMO;
  nunca no Git nem no `painel.json`.
- **A confirmar na etapa:** se o workspace aceita status de projeto personalizados e os limites do plano.

## 6. API da Hostinger

Leitura livre; alteração só com confirmação (regra do `AGENTS.md`). Usos:

1. **Snapshot da `stack` antes de cada deploy de etapa** — rollback da máquina inteira.
2. **Fallback camada 3:** reinício e modo de recuperação.
3. **Métricas** no bloco de saúde do PMO.

Token no `admin.env`; endpoints a confirmar no spike.

## 7. O que sai

| Sai | Motivo |
|---|---|
| `30-sysbox`, `31-rede-containers`, `33-runners`, restos de `compose/` e `coder/` | Coder já saiu (#7); sem equipe em container. **REVISADO em 2026-10-19: runners voltam, ver docs/superpowers/specs/2026-10-19-ci-sem-creditos-design.md** (`33-runners` e `compose/runners.yml` saem aqui e voltam adaptados depois) |
| `22-openrig`, `23-papeis`, `openrig/` | Dupla principal/revisor vira sessões do OpenCode |
| `24-modelos`, Continue | Substituídos pelo 9router (o comando `modelo` fica, apontado ao 9router) |
| Perfil `azure` | Fora dos 4 destinos |

Antes de cada remoção, confirmar que nada mais chama o script. Desinstalação na VPS tem roteiro próprio e pede
confirmação.

## 8. Testes

- Bash e Python rodam **na VPS ou no WSL**; `tests/run.sh` avisa e sai fora do Linux (os 19 erros de 10/10 eram
  do Windows: `os.O_NOFOLLOW` e symlink).
- `@ness/auth`: testes do niso vêm junto e rodam contra os dois adaptadores — D1 via wrangler/miniflare,
  Postgres via `/srv/dev/bin/postgres.yml` descartável.
- Templates: cada um com teste rápido que gera numa pasta temporária, faz build e roda os testes do projeto.
  Kamal: valida `deploy.yml` sempre; deploy real testado uma vez em máquina descartável.
- Fallback: ensaio documentado de cada camada (derrubar `tailscaled`, usar camada 1, ligar e desligar camada 2).

## 9. Falhas

| Cai | Continua |
|---|---|
| Tailscale | Camadas 1–3 de acesso |
| 9router | CLIs oficiais |
| OpenCode | SSH + CLIs |
| Authentik (app que usa) | Login de emergência de administrador |
| Deploy ruim (Kamal) | `kamal rollback` |
| Mudança ruim na `stack` | Snapshot da Hostinger |
| Linear | PMO segue normal; espelho reenvia o que mudou na próxima corrida |

## 10. Ordem de entrega

Cada etapa tem plano e PR próprios; nada vai à VPS sem aprovação explícita.

| # | Etapa | Entrega |
|---|---|---|
| 0 | Sincronizar | Clone local alinhado ao `origin/main`; conferir na VPS o que de #9, #11 e #12 está ativo |
| 1 | Spikes | 9router (5 perguntas), Kamal (versão, TLS), endpoints da API da Hostinger |
| 2 | Lugar de trabalho | `tailscale serve`, fallback 1–3, aviso de agente concluído, PMO em uma página, snapshot antes de deploy, remoções |
| 3 | PMO: ciclo de vida + Linear | Congelar/descongelar, alarmes respeitando congelado, espelho PMO → Linear |
| 4 | 9router | Script, serviço na `stack`, checagem no `vigia-health` (ou modo "duas faixas") |
| 5 | `@ness/auth` v1 | Repositório próprio, extração com adaptadores D1 e Postgres |
| 6 | `/novo-projeto` | Templates sistema (4 destinos, Kamal), agente (promptfoo), parecer (Typst) |

## Fora de escopo

Multiusuário na `stack`; Authentik na `stack`; SAML no `@ness/auth`; migração do niso para `@ness/auth`;
observabilidade de LLM além do painel do 9router; segredos de deploy centralizados (SOPS/Infisical) e
configuração única de MCP — entram quando a dor aparecer.
