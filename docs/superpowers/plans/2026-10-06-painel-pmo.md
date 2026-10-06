# Painel do PMO — plano de execução

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Painel em `http://100.76.167.6:8080` com todos os projetos (descobertos no GitHub + "a destinar"), alarme de esquecidos, detalhe por projeto e ações de descartar/restaurar/reanalisar.

**Architecture:** Pacote Python só com biblioteca padrão em `pmo/`: `github.py` (API REST via `urllib`), `coleta.py` (monta um registro por projeto), `regras.py` (esquecidos, estágio sugerido — funções puras), `painel.py` (gera `painel.json`), `servidor.py` (serve a página e grava pedidos de ação), `executor.py` (executa pedidos), `resumo.py` (aviso de segunda). Página estática em `pmo/web/`. Timers systemd. A análise por agente (`claude -p`) entra na Task 9, por cima de um painel que já funciona sem ela.

**Tech Stack:** Python 3.12 (stdlib: `urllib`, `json`, `http.server`, `unittest`, `tarfile`), HTML/CSS/JS sem framework, systemd, UFW.

**Spec:** `docs/superpowers/specs/2026-10-06-painel-pmo-design.md` (+ `2026-10-05-agente-pmo-design.md`)

## Global Constraints

- Só pela tailnet: o servidor escuta em `100.76.167.6:8080`; UFW libera 8080 só em `tailscale0`.
- Donos acompanhados: `resper1965 bekaa-trusted-advisors nessenergy forense-io t4isb-infra familia-almeida` (arquivo `pmo/donos.txt`).
- Esquecido: `em andamento` sem atividade há 14 dias; `em revisão` há 30 dias; ativo sem próximo passo.
- Tipos: `app documento conhecimento agente`. Estágios: `ideia, em andamento, em revisão, entregue, encerrado, parado`.
- Excluir: nome digitado idêntico ao nome do repositório; dono `nessenergy` só arquiva (recusado no executor).
- Cópias locais de excluídos em `/srv/dev/arquivo/excluidos/`, apagadas após 30 dias; arquivados em `/srv/dev/arquivo/`.
- Usuários: coleta e servidor como `agente`; executor como `root` (usa o token do `admin.env`, não roda git em árvore do agente; "trazer" é delegado ao `agente`).
- Toda ação em `/srv/dev/state/pmo/acoes.log`. Testes: `python3 -m unittest discover -s pmo/tests`.

## Review Focus

1. Repositório sem `STATE.md` (a maioria hoje) → painel mostra tipo/estágio "sugerido", nunca quebra. Teste na Task 2.
2. API do GitHub falhando ou com limite (403/rate limit) no meio da coleta → mantém o último `painel.json` bom e marca "coleta incompleta". Teste na Task 3.
3. Nome com espaço e acento ("ORM Carlos Eugenio", "Área") no link "Abrir no VS Code" e na pasta a arquivar → URL codificada e caminho tratado. Teste nas Tasks 4 e 6.
4. Pedido de ação duplicado (dois cliques) → executa uma vez só. Teste na Task 6.
5. Repositório arquivado no GitHub por fora do painel → aparece em "Arquivados", não em esquecidos. Teste na Task 2.

---

### Task 1: Regras puras (`pmo/regras.py`)

**Interfaces — Produces:** `ler_state(texto:str)->dict` (chaves `tipo`, `estagio`, `proximo`); `estagio_sugerido(dias_sem_atividade:int, prs_abertos:int, arquivado:bool)->str`; `esquecido(estagio:str, dias:int, proximo:str|None, arquivado:bool)->str|None` (motivo ou `None`).

- [ ] Teste `pmo/tests/test_regras.py`: `ler_state` lê `**Tipo:** documento`/`**Estágio:** em revisão`/`**Próximo passo:** x` (com e sem acento em "Estágio"); valores inválidos viram `None`; `esquecido('em andamento',15,'x',False)` → motivo; `(…,13,…)` → `None`; `('em revisão',31,…)` → motivo; `('em andamento',2,None,False)` → "sem próximo passo"; arquivado → sempre `None`; `estagio_sugerido(200,0,False)` → `parado`; `(3,1,False)` → `em andamento`.
- [ ] Rodar → falha (módulo inexistente). Implementar. Rodar → passa. Commit `feat: regras do PMO (estagio, esquecidos)`.

### Task 2: Cliente GitHub e coleta (`pmo/github.py`, `pmo/coleta.py`)

**Interfaces — Produces:** `GitHub(token, abrir=urllib.request.urlopen)` com `.repos(dono)->list[dict]`, `.state_md(dono,repo)->str|None`, `.resumo(dono,repo)->dict` (prs, issues, ci, branches_wip, ultimo_commit); `coletar(gh, donos, locais:dict[str,str], agora)->list[dict]` — um registro por repositório: `id` (`dono/repo`), `nome`, `dono`, `arquivado`, `ultima_atividade` (ISO), `dias`, `tipo`, `estagio`, `estagio_sugerido`, `proximo`, `prs`, `issues`, `ci`, `wip`, `pasta` (caminho em `/srv/dev/projetos` ou `None`), `esquecido` (motivo|None), `privado`.
- [ ] Teste com `abrir` falso (respostas JSON gravadas em dicionário): repositório sem STATE.md → `tipo=None`, `estagio=None`, `estagio_sugerido` preenchido; repositório `archived:true` → `arquivado=True`, `esquecido=None`; repositório novo aparece; paginação (`Link: rel="next"`) segue.
- [ ] `locais`: `mapear_locais(raiz)->dict` lê `origin` de cada `.git` em `/srv/dev/projetos` (teste com repositórios criados em diretório temporário, incluindo pasta "ORM Carlos Eugenio").
- [ ] Implementar, testes verdes, commit `feat: coleta do PMO pela API do GitHub`.

### Task 3: Geração do `painel.json` (`pmo/painel.py`)

**Interfaces — Produces:** `gerar(registros, a_destinar, anterior:dict|None, agora)->dict` com `gerado_em`, `contadores`, `mudou_desde_ontem`, `projetos`, `a_destinar`, `arquivados`, `coleta_incompleta`; CLI `python3 -m pmo.painel` grava `/srv/dev/state/pmo/painel.json` atomicamente (arquivo temporário + `rename`).
- [ ] `a_destinar(raiz='/srv/dev/laptop')`: pastas de primeiro e segundo nível sem `.git` e com ao menos 1 arquivo (teste em diretório temporário).
- [ ] Teste: falha do GitHub (exceção na coleta) → mantém `projetos` do `anterior` e `coleta_incompleta=True`; `mudou_desde_ontem` lista projetos novos, que mudaram de estágio e que viraram esquecidos.
- [ ] Commit `feat: painel.json com a destinar e mudancas do dia`.

### Task 4: Página (`pmo/web/index.html`, `app.js`, `estilo.css`)
- [ ] Visão geral: contadores, faixa "Esquecidos" (cartões com o motivo), filtros (dono, tipo, estágio, busca), grade de cartões coloridos por estágio, seções "A destinar" e "Arquivados"; tema claro/escuro; responsivo.
- [ ] Detalhe (clique): situação, tipo/estágio (com "sugerido — confirmar"), próximo passo, PRs/issues/CI/wip, botões **Abrir no VS Code** (`vscode://vscode-remote/ssh-remote+stack-agente` + `encodeURI(pasta)`), **Abrir no GitHub**, **Reanalisar**, **Descartar** (diálogo: Arquivar | Excluir de vez com campo para digitar o nome; para `nessenergy`, só Arquivar), **Restaurar** nos arquivados, **Trazer/Descartar** em "a destinar".
- [ ] Teste manual com um `painel.json` de exemplo (`pmo/web/exemplo.json`) servido localmente; conferir no celular pela tailnet.
- [ ] Commit `feat: pagina do painel do PMO`.

### Task 5: Servidor (`pmo/servidor.py`)

**Interfaces — Produces:** `GET /` e estáticos de `pmo/web`; `GET /painel.json`; `POST /acao` com JSON `{acao, alvo, confirmacao?}`, `acao` ∈ `reanalisar arquivar excluir restaurar trazer descartar`; grava `/srv/dev/state/pmo/fila/<epoch>-<acao>-<hash>.json`; responde 202. Recusa (400) ação desconhecida e alvo fora do `painel.json`.
- [ ] Teste com `http.client` contra o servidor em porta efêmera: ação válida gera arquivo na fila; inválida → 400; alvo desconhecido → 400; caminho `/../` → 404.
- [ ] Commit `feat: servidor do painel grava pedidos de acao`.

### Task 6: Executor (`pmo/executor.py`)

**Interfaces — Produces:** `processar(fila, gh_admin, raiz_projetos, raiz_laptop, arquivo, log, agora)`; um pedido processado vira `fila/feitos/…` com resultado; duplicata (mesma ação+alvo já feita nos últimos 10 min) → ignorada e registrada.
- [ ] Teste com `gh_admin` falso e diretórios temporários: `arquivar dono/repo` chama `archive` e move `projetos/<pasta>` para `arquivo/<dono>__<repo>-<data>.tar.gz`; `restaurar` desfaz; `excluir` com confirmação errada → recusado; `excluir` de `nessenergy/*` → recusado; `excluir` certo → `delete` + cópia em `excluidos/`; `descartar` de "a destinar" → move para `excluidos/`; limpeza remove `excluidos/*` com mais de 30 dias; nomes com espaço e acento.
- [ ] `trazer` executa `sudo -u agente` um passo que faz `git init`/commit e cria o repositório privado em `resper1965` (reaproveita as travas do `20-laptop-github.sh` chamando-o com um TSV de uma linha).
- [ ] Commit `feat: executor das acoes do painel`.

### Task 7: Resumo de segunda (`pmo/resumo.py`)
- [ ] `texto(painel)->(titulo, mensagem)`: "N projetos esquecidos" + lista curta + link; vazio → `None` (nada enviado). Teste unitário.
- [ ] CLI chama `/usr/local/lib/stack-vps/alertar.sh`. Commit `feat: resumo semanal de esquecidos`.

### Task 8: Instalação (`scripts/34-pmo.sh`, unidades systemd, UFW)
- [ ] `34-pmo.sh` (root): copia `pmo/` para `/opt/pmo` (dono root), cria `/srv/dev/state/pmo/{fila,feitos}` (agente), `/srv/dev/arquivo/excluidos` (root, 700), instala `pmo-coleta.timer` (06:00, como agente), `pmo-executor.timer` (1 min, root), `pmo-resumo.timer` (seg 08:00), `pmo-servidor.service` (agente, `100.76.167.6:8080`, `Restart=always`).
- [ ] `07-firewall.sh`: `ufw allow in on tailscale0 to any port 8080 proto tcp`; teste do 07 ganha essa linha.
- [ ] Prova na VPS: `curl 100.76.167.6:8080` → página; pelo IP público → recusado; primeira coleta gera `painel.json` com todos os repositórios dos 6 donos.
- [ ] Commit `feat: instalacao do painel do PMO`.

### Task 9: Análise por agente (situação e próximos 3 passos)
- [ ] `pmo/analise.py`: para projetos com impressão digital mudada, `claude -p` (conta do `agente`) com a coleta, saída JSON validada (`situacao`, `proximos_passos[3]`, `bloqueios`, `riscos`, `confianca`); conteúdo de issue marcado como dado; inválido → mantém o anterior. Teste com `claude` em stub (válido, inválido, timeout).
- [ ] Integra no `painel.json` e na página. Commit `feat: analise do PMO por agente`.

### Task 10: Documentação e PR
- [ ] README (34), `srv-dev-README.md` (Painel: endereço, ações, esquecidos); PR `feat/painel-pmo` → `main`.
