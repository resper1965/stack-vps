# Ambiente da equipe: Coder Community e runners próprios do GitHub Actions

Data: 06/10/2026. Desenho acordado com o Ricardo. Prazo: equipe trabalhando em até 10 dias.
Complementa `2026-10-05-ambiente-alvo-design.md` (base da VPS) e `2026-10-05-migracao-vps-design.md`.

## Objetivo

A VPS `stack` deixa de ser só o ambiente do Ricardo e vira o ambiente de desenvolvimento de uma
equipe de **5 pessoas** (o Ricardo e mais 4, entre funcionários e terceiros), e passa a rodar o CI
dos repositórios privados, sem consumir minutos pagos do GitHub Actions.

## Decisões

| # | Decisão | Alternativa descartada |
|---|---|---|
| 1 | Coder **Community** (gratuito) na própria KVM 8; host reservado para administração | usuário Linux por pessoa (isolamento fraco); Coder em VPS separada (custo; vira o caminho acima de ~8 pessoas) |
| 2 | Endereço `coder.ness.com.br`, previews em `*.coder.ness.com.br`, pelo Cloudflare Tunnel + Access | VPN para terceiros |
| 3 | Login no Coder pela conta GitHub de cada pessoa; acesso a código decidido no GitHub, por repositório | token compartilhado |
| 4 | Agentes (Claude Code, Codex) rodam **dentro** do workspace, cada pessoa com a própria assinatura | Coder Agents (exige API e tem cota no Community); compartilhar assinatura (fere os termos) |
| 5 | Gasto de LLM da equipe pelo OpenRouter, uma chave por pessoa com limite | AI Gateway do Coder (pago) |
| 6 | GitHub continua como fonte do código; **runners próprios** na VPS para os repositórios privados | Forgejo como fonte (vira pré-requisito de backup; cliente fica no GitHub) — reavaliar depois do backup |
| 7 | Workspaces e runners em containers com **sysbox** (Docker dentro sem modo privilegiado) | Docker privilegiado (terceiro viraria root no host) |

Limites do Community que o desenho aceita: qualquer membro usa qualquer modelo; sem log de
auditoria nem cotas do Coder; sem AI Gateway nem Agent Firewall. Por isso forense, dados de cliente
e administração ficam **fora** do Coder.

## Quem fica onde

| Camada | Onde | Quem acessa |
|---|---|---|
| Workspaces da equipe | containers do Coder (sysbox) | cada pessoa, os seus |
| Runners do Actions | containers efêmeros (sysbox) | ninguém interativamente |
| Forense, `/srv/dev/data`, `admin.env` | host | só o Ricardo (`dev`, pela VPN) |
| Agente de PMO e rotina semanal | host, usuário `agente` | ninguém interativamente |
| Coder (servidor + Postgres) | host, Docker do sistema | administrador: só o Ricardo |

Terceiros nunca têm SSH no host nem entram na tailnet.

## 1. Acesso e identidade

- `coder.ness.com.br` e `*.coder.ness.com.br` entram como regras de ingress do tunnel `stack-vps`
  (CNAME proxied) — nenhuma porta nova aberta.
- Cloudflare Access na frente, liberando só os e-mails da equipe; o Coder, atrás dele, autentica pela
  conta GitHub (OAuth app da organização). Saída de alguém: remover do Access, suspender no Coder,
  tirar do GitHub; workspaces dela parados e apagados.
- *External auth* do GitHub no Coder: o workspace clona e faz push com o login da própria pessoa.
- O Ricardo é o único `owner` do Coder.

## 2. Workspaces

| Modelo | Para | Contém |
|---|---|---|
| `web` | Node, Next.js, Workers, Supabase | mise + Node LTS, npm, gh, wrangler, vercel, supabase, Docker interno, Chromium (Playwright) |
| `dados` | Python, BigQuery, notebooks | uv, Python, DuckDB, gcloud/bq, extensões Python e Jupyter |

- Ambos: Claude Code, Codex, extensões do VS Code; abre no VS Code desktop (um clique) ou no
  navegador (code-server).
- Limite por workspace: 4 vCPU, 6 GB de RAM; desligamento automático após 2 h ocioso.
- Volume persistente do workspace para o código; **volume por pessoa** para `~/.claude`, `~/.claude-2`
  e `~/.codex` — login nos agentes uma vez, vale para todos os workspaces da pessoa.
- Segredos de projeto como parâmetros do workspace ou variáveis por usuário; nunca arquivo
  compartilhado.
- Rede: saída para a internet liberada; **acesso ao host bloqueado** (regras na cadeia `DOCKER-USER`
  contra o IP do host, a faixa da tailnet `100.64.0.0/10` e as redes internas do Docker do sistema).

## 3. Runners do GitHub Actions

- Runners **efêmeros**: um container por job, destruído ao fim (`--ephemeral`), com sysbox para o Docker
  interno dos jobs. Concorrência inicial: 3 jobs; limite de 2 vCPU e 4 GB por job.
- Registro no nível da **organização** onde houver organização (`nessenergy`,
  `bekaa-trusted-advisors`, `forense-io`) e no nível do repositório para os privados de `resper1965`.
  Rótulo: `stack`.
- **Nunca em repositório público** (um fork poderia rodar código na VPS). `stack-vps` é público:
  fica fora.
- Workflows passam a usar `runs-on: [self-hosted, stack]`. Nos repositórios da Alupdata a mudança
  segue o `AGENTS.md` de lá: branch `ci/…`, commit em português **sem atribuição de IA**, PR para `main`.
- Credencial de registro: token do GitHub com permissão de administrar runners da organização,
  guardado no `admin.env`; os runners em si recebem só o token de registro de curta duração.
- Os runners **não reduzem assentos**: assento é cobrado por pessoa com acesso a repositório privado.
  Política: terceiros entram só nos repositórios em que trabalham.

## 4. Capacidade

KVM 8 (8 vCPU, 31 GB): Coder + Postgres ~2 GB; 5 pessoas com até 2 workspaces ativos de 6 GB
(compartilhando CPU); runners até 3 × 4 GB. Sobrecarga vira alerta pelo `health.sh` (memória). Acima
de ~8 pessoas ou com runners saturando, separar em segunda VPS (decisão 1).

## 5. Ordem de implantação (10 dias)

1. Reinstalação base (plano da migração): 01 → 07, 16, 04, 09.
2. sysbox + regras `DOCKER-USER`.
3. Coder (compose com Postgres) + ingress e Access + OAuth do GitHub.
4. Modelos `web` e `dados`; workspace de teste do Ricardo.
5. Runners efêmeros; um repositório privado de teste; depois Alupdata e demais.
6. Entrada da equipe: e-mail no Access, conta no Coder, acesso no GitHub por repositório, chave do
   OpenRouter com limite.

## Testes

- Workspace de um usuário comum não alcança o host (SSH, painel, `100.76.167.6`, `172.17.0.1`).
- `docker run` dentro do workspace funciona sem `--privileged`; o container do workspace não enxerga
  o `docker.sock` do host.
- Runner efêmero: job de teste roda e o container some ao fim; job de repositório público não pega
  o runner.
- Saída de um membro: depois de suspenso, perde acesso ao Coder e aos workspaces.

## Fora do escopo

- Forgejo/Gitea próprio (reavaliar depois do backup).
- Licença Premium do Coder.
- Mudar o plano do GitHub ou a política de assentos das organizações.
