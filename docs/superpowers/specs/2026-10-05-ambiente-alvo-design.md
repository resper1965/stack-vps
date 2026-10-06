# Ambiente-alvo da VPS `stack`

Data: 05/10/2026. Desenho acordado com o Ricardo na sessão de brainstorming do mesmo dia.
Complementa `2026-10-05-migracao-vps-design.md`: aquele documento trata de **como chegar**
(migração, backup, reinstalação); este trata de **o que deve existir** na VPS.

## Objetivo

Um ambiente de desenvolvimento remoto único, onde o Ricardo e os agentes (Claude Code e Codex)
trabalham nas quatro frentes que pesam no dia a dia:

| Frente | Exemplos |
|---|---|
| A. Apps web | Next.js, Cloudflare Workers, Vercel, Supabase |
| B. Forense e pentest | análise de evidência, laudo, recon passivo |
| C. Documentos de GRC | políticas, relatórios, propostas, SoA, em DOCX e PDF |
| D. Dados | conectores Python, BigQuery (Alupdata), análise local |

Critérios: acessível de qualquer lugar sem porta aberta; um projeto ou um agente não atrapalha o
outro nem a máquina; tudo recriável pelos scripts do repositório.

## Decisões

| # | Decisão | Alternativa descartada |
|---|---|---|
| 1 | Ferramentas pesadas ou arriscadas em container; sistema base enxuto | instalar tudo no host |
| 2 | Pentest **ativo** fica no host `npentest`; a `stack` só faz análise passiva e forense | varrer a partir da `stack` (queima o IP, termos da Hostinger) |
| 3 | Jupyter pela extensão do VS Code via Remote-SSH | servidor Jupyter exposto |
| 4 | Agentes rodam como usuário `agente`, sem `sudo`, com Docker rootless | agentes como `dev` (equivale a root) |
| 5 | Segredos em três níveis (`admin`, `agente`, por projeto via `direnv`) | um `.env` único carregado para tudo |
| 6 | Tokens mínimos para o agente; `main` protegida no GitHub | confiar na regra escrita "nunca push em main" |
| 7 | Alertas por ntfy, e-mail e Telegram, só na mudança de estado | sem alerta; um canal só |
| 8 | Sem Kubernetes, Coolify, Portainer, desktop remoto, Vault, Grafana | — máquina única, um usuário humano |

## 1. Sistema base

Agentes: Claude Code (contas bekaa e ionic), Codex (ChatGPT Pro; OpenRouter com `-p openrouter`) e
Antigravity CLI (`agy`), todos no usuário `agente`; OpenRig para a dupla principal/revisor.

Já existe: Ubuntu 24.04, SSH só por chave, fail2ban, unattended-upgrades, UFW (22 só na tailnet),
Tailscale (`100.76.167.6`), Cloudflare Tunnel de reserva, Docker + Compose, tmux persistente,
`mise` com Node LTS, ripgrep, fd, jq, htop, ncdu, restic, rclone.

Entra:

| Item | Para quê |
|---|---|
| `uv` (Python por projeto, via `mise`) | frentes B, C e D |
| `gh`, `wrangler`, `vercel`, `supabase` | CLIs das plataformas (npm global ou binário oficial) |
| `gcloud` + `bq` | BigQuery; login de usuário (`gcloud auth login`), **sem arquivo de chave** |
| OpenRouter (serviço externo, nada instalado) | acesso a modelos por API compatível com OpenAI (`OPENAI_BASE_URL=https://openrouter.ai/api/v1`); uma chave por pessoa e por agente, cada uma com limite de crédito e revogável; Featherless segue com chave própria para os modelos de pentest |
| `direnv` | segredos por projeto ao entrar na pasta |
| `lazygit` | revisão e commit pelo terminal |
| `cloudflared` | instalado pelo `03` (hoje nenhum script instala) |
| Chromium headless + dependências do Playwright | testes de ponta a ponta e PDF |

Não entra no host: Go, Rust, .NET, PHP (o `mise` instala por projeto quando um repo pedir); banco
de dados no sistema.

## 2. Frente B — forense

Revisto em 06/10/2026 pela decisão do Ricardo de 30/09 (CLAUDE.md §9): **material de caso não entra
na VPS**. Na VPS ficam só os repositórios de código e método (`modusoperandi`, `carteira`) e o
repositório `casos`; originais e rascunhos ficam na estação forense, sob custódia e apagamento em D+30.
Ferramentas de análise, se usadas aqui, trabalham só com dado sintético ou público. Pentest ativo segue
no host `npentest`. `/srv/forense` existe, vazio, fora do alcance do `agente`.

## 3. Frente C — documentos de GRC

- Pandoc, LibreOffice sem interface (`libreoffice --headless --convert-to`), Typst, Mermaid CLI.
- Fontes da marca ness (Montserrat) instaladas no sistema.
- Repositório `templates-grc` (modelos de política, relatório, proposta) clonado em
  `repos/infra/`, consumido pelos agentes.
- Assinatura de PDF com pyHanko (certificado ICP-Brasil A1). **O certificado não fica na VPS**: é
  fornecido no momento da assinatura e descartado.

## 4. Frente D — dados

- Notebooks pela extensão Jupyter do VS Code (Remote-SSH); kernel do `uv` de cada projeto.
- Bibliotecas por projeto: pandas, polars, DuckDB, google-cloud-bigquery.
- Extratos e amostras de cliente em `/srv/dev/data/<projeto>`, nunca em repositório.
- Credencial da Alupdata segue o `AGENTS.md` daquele repositório (Secret Manager; nada em arquivo).

## 5. Segurança

### Usuários

Revisto em 05/10/2026 depois da revisão independente: com repositórios compartilhados por grupo,
o `agente` gravava hooks e `.git/config` que depois rodavam como `dev` (e daí root). O modelo final
separa os papéis em vez de compartilhar a árvore.

| | `agente` (estação de trabalho: Ricardo + IA) | `dev` (administração) |
|---|---|---|
| `sudo` | não | sim |
| Docker | rootless próprio | daemon do sistema |
| `/srv/dev/repos`, `/srv/dev/state` | **dono** | não roda git ali (o git recusa: repositório de outro dono) |
| `/srv/dev/data`, `/srv/forense` | sem acesso | leitura e escrita |
| Segredos | `agente.env`, `projetos/` | `admin.env` |
| Rotina semanal (inventário, `STATE.md`) | roda aqui (crontab do `agente`) | — |
| Provisionamento (`scripts/`) | — | clone em `/opt/stack-vps`, dono root, fora do alcance do `agente` |

- O Ricardo trabalha conectado como `agente` (`ssh stack-agente`, VS Code na mesma conexão); usa
  `stack` (`dev`) só para administração.
- Comandos `ia` e `iax` continuam valendo para quem estiver como `dev`: abrem o agente como `agente`.
- Sem grupo compartilhado, sem `safe.directory '*'`, sem `core.sharedRepository`.
- Carimbos que o health confere (último backup, estado do vigia) ficam em `/var/lib/stack-vps`,
  onde o `agente` não escreve.

### Segredos

```
/srv/dev/secrets/
├── admin.env      600 dev     Cloudflare com escrita, Hostinger, R2, restic, canais de alerta
├── agente.env     640 :agente tokens mínimos do agente
└── projetos.env   640 :agente chaves de projeto, um arquivo só (decisão de 30/09), carregado no shell do agente
```

### Tokens do agente

- GitHub: um token *fine-grained* por dono (resper1965, bekaa-trusted-advisors, forense-io,
  nessenergy, demais conforme o escopo), com Contents e Pull requests em leitura e escrita, sem
  Administration.
- Proteção de branch na `main` (ou `master`) dos repositórios ativos do escopo: sem push direto,
  sem force push.
- Cloudflare: token de leitura (zona, DNS, tunnel, Access). O token com escrita fica no `admin.env`.
- Composio, SerpAPI, Featherless: no `agente.env`.

## 6. Operação

- **Alertas**: `stack-health.timer` roda o `health.sh` de hora em hora. Na **mudança** de estado
  (ok → falha ou falha → ok), `alertar` envia para todos os canais configurados no `admin.env`:
  ntfy (`NTFY_TOPIC`, tópico privado), e-mail via Resend (`RESEND_API_KEY`, para
  `resper@bekaa.eu`) e Telegram (`TELEGRAM_BOT_TOKEN`, `TELEGRAM_CHAT_ID`). Canal sem
  configuração é pulado; falha de um canal não impede os outros.
- **O que o health confere**: Tailscale, tunnel, Docker, disco, memória, idade do último backup,
  última rotina semanal, reboot pendente.
- **Painel**: `painel/index.html` + `dashboard.json` servidos em `http://100.76.167.6:8080`,
  ligado só no IP da tailnet.
- **Preview para cliente**: `expor <nome> <porta> <email>` cria a rota no tunnel, o CNAME
  `<nome>.esper.ws` e a aplicação de Access liberada para o Ricardo e o e-mail informado (com a
  regra de redirecionamento da zona excluindo o host); `recolher <nome>` desfaz os três. Só `dev`.
- **Kit de serviços**: `servicos up|down` (compose em `compose/servicos.yml`): Postgres 16, Redis,
  Mailpit, MinIO, em `127.0.0.1`, dados em `/srv/dev/data/servicos`, desligados por padrão.
- **Manutenção**: reboot pendente vira alerta (o Ricardo escolhe a hora); `atualizar` (mensal,
  manual) atualiza `mise`, CLIs e agentes; repositórios dormentes vão para `repos/arquivo/` com
  base no inventário semanal, sem apagar.
- Verificar se o plano KVM da Hostinger inclui backup semanal automático; se incluir, é a segunda
  camada além do restic.

## Ondas

O que muda layout, usuários ou o conjunto restaurado pelo backup precisa existir **antes** da
reinstalação, para a janela já reconstruir a VPS no formato final. O resto são scripts novos,
idempotentes, que entram depois sem nova reinstalação.

| Onda | Conteúdo | Quando |
|---|---|---|
| 1 | Seção 5 inteira (usuários, segredos, tokens, `ia`/`iax`); `cloudflared` no `03`; alertas e health ampliado | antes da reinstalação, junto com as correções da revisão da migração |
| 2 | Sistema base (seção 1) e kit de serviços | logo depois da janela |
| 3 | Frentes B, C e D; painel; preview para cliente; `atualizar`; arquivo de dormentes | conforme a necessidade |

## Testes

- Scripts novos seguem o padrão do repositório: `tests/test-*.sh` com stubs, `shellcheck` limpo.
- Segurança, provada na VPS depois da Onda 1, como `agente`:
  `sudo -n true` falha; `ls /srv/dev/data` e `cat /srv/dev/secrets/admin.env` falham;
  `docker run --rm hello-world` funciona (rootless); `git push origin main` num repo protegido é
  recusado pelo GitHub.
- Alertas: forçar uma falha (parar o `cloudflared`) e conferir a mensagem nos três canais; religar
  e conferir a de recuperação; rodar de novo sem mudança e conferir que nada é enviado.

## Fora do escopo

- Pentest ativo a partir da `stack`.
- Hospedar produção de cliente na `stack` (o preview é temporário e atrás de login).
- Migrar repositórios para devcontainers em lote (cada projeto adota quando for tocado).
