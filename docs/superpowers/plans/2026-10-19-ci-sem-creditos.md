# CI sem créditos do GitHub — plano de implementação

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or
> superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** CI sem minutos pagos: runners efêmeros isolados na `stack` (conta `ci`), convenção de CI local e os jobs agendados
parados passando a timers — conforme o spec.

**Architecture:** conta de sistema `ci` com Docker rootless próprio; regra de firewall por UID bloqueia tailnet e metadata;
um **supervisor** (Python stdlib, roda como `ci`) guarda o token de organização num arquivo `0400`, pede à API do GitHub uma
configuração **JIT** (uso único) por runner e inicia um container efêmero que recebe só essa configuração. Saúde pelo `health.sh`.

**Tech Stack:** Bash (shellcheck `-S warning`), Python 3 stdlib (`unittest`, `urllib`, `subprocess`), systemd, iptables/ip6tables
(`-m owner --uid-owner`), Docker rootless, imagem oficial do runner do GitHub, API REST do GitHub.

**Spec:** `docs/superpowers/specs/2026-10-19-ci-sem-creditos-design.md`

## Global Constraints

- Nada vai à VPS nem altera conta GitHub (grupo de runners, token, workflow) sem aprovação explícita do Ricardo, com o comando
  exato e o efeito; **snapshot antes** de cada etapa que instala algo (`sudo bash /opt/stack-vps/bin/hostinger.sh snapshot --sim`;
  a Hostinger guarda UM snapshot por VM, o novo sobrescreve).
- Uma branch por entrega (`feat/ci-runners`, …) com PR para `main`; branch nova **sem upstream** em `origin/main`; nunca push em `main`.
- Commits em português, conventional, com o trailer do repositório. Código no padrão do arquivo (scripts e PMO usam nomes em português).
- Script novo: idempotente, `set -euo pipefail`, `shellcheck -x -S warning` limpo, teste em `tests/test-NN-*.sh` com `tests/lib.sh`
  (stubs no PATH, `STACK_TESTE=1`). Python só com a biblioteca padrão; testes em `ci/tests/` (o `tests/run.sh` passa a descobri-los).
- Segredo nunca em argumento de linha de comando, variável de ambiente de container, log, `painel.json` ou Git. O token de organização
  (`RUNNER_TOKEN`) nunca entra num container.
- Runner **só** para repositórios **privados** das organizações, escolhidos um a um; PR vindo de fork nunca roda em runner.
- Repositórios de cliente (`nessenergy/Alupdatalake`, `nessenergy/sitealupar`): nenhuma mudança sem aprovação explícita; ficam por último.
- Testes de bash/Python rodam na VPS ou no WSL (`bash tests/run.sh`); baseline conhecido: o passo shellcheck do `run.sh` falha só com 28
  avisos SC2319 antigos de 4 arquivos de teste.

## Review Focus

1. **O container do runner nunca vê o token de organização**: nem em ambiente, nem em arquivo montado, nem em linha de comando de `docker run`.
   Teste na Task 4 (`test_container_recebe_so_a_configuracao_jit`).
2. **Um job não alcança a tailnet nem o metadata**: regra por UID da conta `ci` para IPv4 **e** IPv6 (a tailnet tem `fd7a:115c:a1e0::/48`).
   Teste na Task 3 e prova real no spike (Task 1).
3. **A conta `ci` não lê `/srv/dev/secrets`, nem o home do `agente`/`dev`, nem entra em `sudo`/`docker`/`agente`/`pmo`.** Teste na Task 2.
4. **O supervisor não cria containers sem fim** se a API cair, se o token for revogado ou se o número de runners já estiver completo;
   backoff e teto. Testes na Task 4.
5. **Runner de repositório público ou de fork**: o grupo de runners é criado restrito a repositórios privados escolhidos; o supervisor recusa
   iniciar se o grupo estiver aberto a todos. Teste na Task 4.

## Mapa de arquivos

| Arquivo | Responsabilidade | Task |
|---|---|---|
| `docs/spikes/2026-10-19-ci-runners.md` | respostas do spike | 1 |
| `scripts/38-ci-conta.sh` | conta `ci`, subuid/subgid, linger, Docker rootless | 2 |
| `scripts/39-ci-rede.sh` + `systemd/stack-ci-rede.service` | regra por UID (iptables/ip6tables), reaplicada no boot | 3 |
| `ci/runners.py` + `ci/tests/` | supervisor: API JIT, containers efêmeros, estado | 4 |
| `scripts/40-ci-runners.sh` + `systemd/stack-ci-runners.service` | instala token, config e unidade; só habilita com `--habilitar` | 5 |
| `bin/health.sh`, `tests/test-health.sh` | saúde dos runners | 6 |
| `docs/AGENTS.md`, `README.md`, `standards/`, `skills/project-bootstrap/` | convenção de CI | 7 |
| `tests/run.sh` | descobre `ci/tests` | 4 |

---

## Etapa 1 — Spike (resposta, não código)

### Task 1: Spike dos runners isolados (com aprovação, na VPS)

Resultado: `docs/spikes/2026-10-19-ci-runners.md` com **Pergunta | Resposta | Evidência** e uma linha **Decisão**. Tudo reversível e
em diretório/conta descartáveis; nenhuma conta GitHub é alterada sem aprovação.

- [ ] **Step 1 — pré-condições (só leitura):** `RUNNER_TOKEN` existe no `admin.env` (só o nome da chave, sem imprimir valor); quais
  escopos o token tem (`gh api -i user | grep -i x-oauth-scopes` com ele, sem imprimir); as 3 organizações aceitam grupos de runners
  (plano da organização); AppArmor: perfil do `rootlesskit` já existe (`/etc/apparmor.d/usr.bin.rootlesskit`, criado pelo `16-agente.sh`).
- [ ] **Step 2 — Docker rootless de uma conta descartável `cispike`:** criar a conta com os mesmos passos do `16-agente.sh` (subuid/subgid
  em faixa que não colida com a do `agente`: `grep -E '^(agente|dev|ci):' /etc/subuid`), linger, `dockerd-rootless-setuptool.sh install`,
  `docker run --rm alpine true`. Registrar o tempo e o que faltou (pacotes `uidmap`, `slirp4netns`, `fuse-overlayfs`).
- [ ] **Step 3 — a regra por UID pega o tráfego do container?** Com `iptables -I OUTPUT -m owner --uid-owner cispike -d 100.64.0.0/10 -j REJECT`
  (e `ip6tables` para `fd7a:115c:a1e0::/48`, e `169.254.169.254/32`): de dentro de um container da conta `cispike`, tentar alcançar
  `100.76.167.6` (a própria `stack` pela tailnet), o IP tailnet do notebook e `169.254.169.254` (esperado: recusa) e `1.1.1.1` (esperado: ok);
  testar com o modo de rede padrão do Docker rootless (slirp4netns/pasta). **Se a recusa não funcionar, PARE e proponha a segunda VPS de CI.**
- [ ] **Step 4 — a conta não lê segredos:** `sudo -u cispike cat /srv/dev/secrets/agente.env` e `ls /home/agente /home/dev` (esperado: negado);
  `id cispike` sem grupos extras.
- [ ] **Step 5 — configuração JIT de ponta a ponta (com aprovação, em UMA organização, num repositório privado de teste):**
  criar o grupo de runners restrito a esse repositório; `POST /orgs/{org}/actions/runners/generate-jitconfig` (rótulos `self-hosted`, `stack`);
  iniciar o container da imagem oficial `ghcr.io/actions/actions-runner` com **somente** a configuração (`./run.sh --jitconfig …`);
  disparar um workflow `runs-on: [self-hosted, stack]` que imprime `id; env | wc -l; docker ps` e confirmar: o runner pega o job, desregistra
  sozinho ao final, e **o ambiente do job não contém o token**. Apagar o repositório de teste e o grupo ao final, com aprovação.
- [ ] **Step 6 — job que usa Docker:** decidir como um job faz `docker build`: (a) montar o socket do Docker rootless da conta `ci`
  no container do runner (o alcance fica limitado à conta `ci`); (b) container privilegiado dentro do namespace rootless; (c) sem Docker
  no CI. Medir e registrar prós e contras.
- [ ] **Step 7 — limpeza e decisão:** remover a conta `cispike`, as regras temporárias, o repositório e o grupo de teste. Escrever o
  documento. **Decisão:** "isolamento confirmado" (segue a Task 2) ou "isolamento não confirmado" (parar e levar ao dono a segunda VPS).
- [ ] **Step 8 — commit:** `docs: spike dos runners isolados da conta ci`.

---

## Etapa 2 — Conta, rede e supervisor

Branch `feat/ci-runners` a partir de `main` (ou do PR #18 mergeado). Todas as Tasks 2–6 são código + teste local; nada vai à VPS até a Task 8.

### Task 2: Conta `ci` (`scripts/38-ci-conta.sh`)

**Files:**
- Create: `scripts/38-ci-conta.sh`
- Test: `tests/test-38-ci-conta.sh`

**Interfaces:**
- Consumes: decisões do spike (faixa de subuid/subgid, pacotes, passos do Docker rootless).
- Produces: usuário de sistema `ci`, home `/srv/ci` (0700), linger ligado, Docker rootless ativo, `DOCKER_HOST` do `ci` em
  `unix:///run/user/<uid>/docker.sock`. Variável de teste `CI_HOME` (padrão `/srv/ci`).

Mesmo modelo do `16-agente.sh` (leia-o primeiro): root, idempotente, `STACK_TESTE=1` ignora o teste de root.

- [ ] **Step 1 — testes (stubs de `useradd`, `usermod`, `loginctl`, `id`, `getent`, `systemctl`, `install`):**
  - `test_recusa_quando_nao_e_root` (rc 1, nenhuma escrita);
  - `test_cria_usuario_sem_grupos_privilegiados` — o script chama `useradd` com `--system`, home `/srv/ci`, shell `/bin/bash` (Docker rootless
    precisa de sessão), e **nunca** com `-G sudo,docker,agente,pmo`;
  - `test_falha_se_ci_estiver_em_grupo_privilegiado` — `id -nG ci` stubado contendo `sudo` → rc 1 com mensagem (Review Focus 3);
  - `test_subuid_nao_colide_com_o_agente` — faixa escolhida não intersecta a do `agente` (`/etc/subuid` de fixture);
  - `test_idempotente` — segunda execução com o usuário existente não chama `useradd`;
  - `test_nao_toca_no_perfil_apparmor_existente` — só confere/avisa se `usr.bin.rootlesskit` falta, não reescreve.
- [ ] **Step 2 — RED:** `bash tests/test-38-ci-conta.sh` falha (script ausente).
- [ ] **Step 3 — implementar** conforme o spike; verificação final no script: `sudo -u ci test ! -r /srv/dev/secrets/agente.env` (saída
  `negado` esperada) — em teste, isolada por variável (`CI_VERIFICA=0`).
- [ ] **Step 4 — GREEN, shellcheck limpo.**
- [ ] **Step 5 — commit:** `feat: conta ci com Docker rootless para os runners`.

### Task 3: Isolamento de rede por UID (`scripts/39-ci-rede.sh`)

**Files:**
- Create: `scripts/39-ci-rede.sh`, `systemd/stack-ci-rede.service`
- Test: `tests/test-39-ci-rede.sh`

**Interfaces:**
- Produces: cadeia `STACK-CI` em `OUTPUT` (iptables e ip6tables) com `REJECT` para tailnet v4 `100.64.0.0/10`, tailnet v6
  `fd7a:115c:a1e0::/48`, metadata `169.254.169.254/32`, aplicada só ao UID da conta `ci` (`-m owner --uid-owner`). Idempotente.

- [ ] **Step 1 — testes (stubs de `iptables`, `ip6tables`, `id`; o stub `iptables -C` devolve 1 até a regra ser inserida, como no teste do antigo
  `31-rede-containers`):** as 3 regras v4 e a regra v6 são inseridas com o UID de `id -u ci`; segunda execução não duplica (`-C` antes de `-I`);
  UID inexistente (`id -u ci` falha) → rc 1 e nenhuma regra; a regra nunca é inserida sem `--uid-owner`; `--instalar` copia o script e a unidade e
  habilita `stack-ci-rede.service`; recusa não-root.
- [ ] **Step 2 — RED / Step 3 — implementar** (modelo: `git show origin/main:scripts/31-rede-containers.sh`, sem a parte do `daemon.json`) /
  **Step 4 — GREEN.** A unidade `Type=oneshot`, `RemainAfterExit=yes`, `After=network-online.target docker.service`, reaplica no boot.
- [ ] **Step 5 — commit:** `feat: regra de rede por UID da conta ci (tailnet e metadata)`.

### Task 4: Supervisor dos runners (`ci/runners.py`)

**Files:**
- Create: `ci/__init__.py`, `ci/runners.py`, `ci/tests/__init__.py`, `ci/tests/test_runners.py`
- Modify: `tests/run.sh` (descobre `ci/tests`: `python3 -m unittest discover -s ci/tests -t .`)

**Interfaces (assinaturas exatas):**
- `class Github:` `__init__(self, token: str, post=urllib_post, get=urllib_get)`; `grupo(self, org: str, nome: str) -> dict` (id, `visibility`,
  `allows_public_repositories`); `jitconfig(self, org: str, grupo_id: int, nome: str, rotulos: list[str]) -> str` (devolve `encoded_jit_config`);
  `runners(self, org: str) -> list[dict]`. Erros → `RuntimeError` **sem** o token na mensagem.
- `def planejar(configuracao: dict, ativos: dict[str, int]) -> list[tuple[str, int]]` — `configuracao = {org: {"grupo": str, "quantidade": int}}`,
  `ativos = {org: n}` → `[(org, faltam)]` só com `faltam > 0`.
- `class Docker:` `iniciar(self, nome: str, imagem: str, jit: str, cpus: str, memoria: str) -> None`; `ativos(self, rotulo: str) -> dict[str, int]`;
  `parar_todos(self) -> None`. Todas as chamadas usam `subprocess.run([...])` com lista de argumentos, **nunca** `shell=True`.
- `def ciclo(cfg: dict, gh: Github, dk: Docker, estado_path: str, agora: float) -> dict` — um passe: valida o grupo (recusa se
  `visibility == "all"` ou `allows_public_repositories`), calcula `planejar`, inicia no máximo `LIMITE_POR_CICLO = 4` runners, grava o estado
  (`/srv/ci/status.json`, atômico) e devolve o resumo.
- `def main(argv=None) -> int` — lê `/srv/ci/config.json` (`{"imagem", "cpus", "memoria", "orgs": {…}}`) e o token de `/srv/ci/token`;
  laço com `sleep(INTERVALO = 30)`; backoff exponencial até 10 min em erro; `--uma-vez` roda um ciclo (usado por teste e pelo health).

- [ ] **Step 1 — testes (`ci/tests/test_runners.py`, API e Docker falsos):**
  - `test_container_recebe_so_a_configuracao_jit` — o Docker falso registra o argv e o ambiente de `iniciar`; afirmar que o token **não aparece**
    em nenhum argumento, variável de ambiente ou arquivo, e que o jit config aparece uma única vez (**Review Focus 1**);
  - `test_planejar_calcula_o_que_falta` e `test_planejar_nao_inicia_alem_da_quantidade`;
  - `test_recusa_grupo_aberto_a_todos` e `test_recusa_grupo_com_repositorio_publico` — `ciclo` levanta `RuntimeError`, nada é iniciado
    (**Review Focus 5**);
  - `test_api_caindo_nao_cria_container` e `test_backoff_cresce_e_tem_teto` (**Review Focus 4**);
  - `test_limite_por_ciclo` — 10 faltando, só `LIMITE_POR_CICLO` iniciados;
  - `test_erro_da_api_nao_vaza_o_token`;
  - `test_estado_atomico_e_sem_token` — `status.json` contém contagens e horários, nunca o token;
  - `test_nomes_unicos` — dois runners da mesma org recebem nomes diferentes (`stack-<org>-<hex>`).
- [ ] **Step 2 — RED / Step 3 — implementar / Step 4 — GREEN** (`python3 -m unittest discover -s ci/tests -t . -q`), e `bash tests/run.sh`
  continua só com o baseline.
- [ ] **Step 5 — commit:** `feat: supervisor de runners efêmeros com configuração JIT`.

### Task 5: Instalação (`scripts/40-ci-runners.sh`)

**Files:**
- Create: `scripts/40-ci-runners.sh`, `systemd/stack-ci-runners.service`
- Test: `tests/test-40-ci-runners.sh`

**Interfaces:**
- Consumes: Tasks 2–4; `RUNNER_TOKEN` e a lista de organizações do `admin.env` (`CI_ORGS=nessenergy:grupo:3,bekaa-trusted-advisors:grupo:3`).
- Produces: `/srv/ci/token` (0400, `ci:ci`, copiado do `admin.env` por subshell/umask, nunca por argv), `/srv/ci/config.json` (0640),
  a unidade `stack-ci-runners.service` (`User=ci`, `ExecStart=/usr/bin/python3 -m ci.runners`, `Restart=on-failure`, `PYTHONPATH=/opt`),
  instalada e **só habilitada com `--habilitar`**.

- [ ] **Step 1 — testes:** sem `RUNNER_TOKEN` → rc 1 e nada escrito; token gravado 0400 `ci:ci` e fora de argv/log; sem `--habilitar` a unidade
  não é habilitada; com `--habilitar` roda `systemctl enable --now`; idempotente; valida `CI_ORGS` (formato, organização não vazia).
- [ ] **Step 2–4 — RED, implementar, GREEN, shellcheck.** `34-pmo.sh` é o modelo de como copiar o `admin.env` para um arquivo de serviço.
- [ ] **Step 5 — commit:** `feat: instalador dos runners da conta ci (token 0400, só habilita sob flag)`.

### Task 6: Saúde (`bin/health.sh`)

- [ ] **Step 1 — testes em `tests/test-health.sh`:** seção `ci` só aparece se `stack-ci-runners.service` existir; unidade ativa +
  `status.json` com `atualizado` < 3 min e runners ≥ 1 → `ok    runners (n)`; unidade parada ou status velho → `FALHA runners`; falha de API gravada
  no status → `FALHA runners (api)`; o conteúdo do status nunca é impresso além de contagens.
- [ ] **Step 2–4:** implementar lendo `/srv/ci/status.json` (caminho sobrescrevível por `HEALTH_CI_STATUS`); o `ler_saude` do PMO já parseia o formato.
- [ ] **Step 5 — commit:** `feat: health confere os runners da conta ci`.

### Task 7: Convenção de CI nos documentos e no bootstrap

- [ ] **Step 1:** `docs/AGENTS.md` — a linha de CI passa de "planejado" a descrever o que existir (somente depois da Task 8); `README.md` ganha as linhas de 38–40;
  `skills/project-bootstrap/SKILL.md` e `standards/README.md`: "sem GitHub Actions" vira "CI local (`ci: local-vps`); `runs-on: [self-hosted, stack]` só
  em repositório privado de organização com runner".
- [ ] **Step 2:** teste: `tests/test-35-projeto-standards.py` continua passando; nenhum texto novo promete runner antes de a Task 8 passar.
- [ ] **Step 3 — commit:** `docs: convenção de CI local e runners da stack`.

---

## Etapa 3 — Instalação e piloto (somente com aprovação, na VPS)

### Task 8: Instalar, habilitar e provar com um repositório piloto

Não é código: é o roteiro executado com o Ricardo, passo a passo.

- [ ] Snapshot da Hostinger. `git` do `/opt/stack-vps` na versão mergeada.
- [ ] `sudo ./scripts/38-ci-conta.sh` → `sudo ./scripts/39-ci-rede.sh --instalar` → prova da rede **como `ci`** (alcança `1.1.1.1`, **não** alcança
  `100.76.167.6` nem `169.254.169.254`, IPv4 e IPv6) → `sudo ./scripts/40-ci-runners.sh` → conferir o `config.json` → `sudo ./scripts/40-ci-runners.sh --habilitar`.
- [ ] Grupo de runners criado por você (ou por mim, com aprovação) na organização piloto: **repositórios selecionados, só privados, sem forks**.
- [ ] Piloto: **um repositório privado de organização que não seja de cliente**; um PR trocando `runs-on` para `[self-hosted, stack]`; rodar o workflow e conferir
  no log do job: `id` é a conta do runner, `env` não contém token, o runner some do GitHub ao terminar.
- [ ] Só depois: `docs/AGENTS.md` descreve o CI da stack como disponível (Task 7, Step 1) e abrimos os outros repositórios, **um PR por vez**.
- **Rollback:** `sudo systemctl disable --now stack-ci-runners.service`; remover runners órfãos na organização; a conta e a regra de rede podem ficar.

---

## Etapa 4 — Jobs agendados parados viram timers (um plano por job)

Cada job tem a sua tarefa, **depois** de ler o workflow desligado (`gh api repos/<repo>/contents/<path>`) e de o Ricardo fornecer os segredos em
`projetos.env`. Ordem: (1) **backup** do `n.360-alternative` (diário; o que mais importa); (2) verificação de DNS do `dns-repair`; (3) varreduras
de segurança (`aegis-itms`, `n.discovery`, `be-secure`, `nTransfer`, `site-sabrina`, `DocVault`).

Molde de cada tarefa: unidade `*.service` + `*.timer` de usuário (`agente`, ou `ci` se não precisar de segredo), `OnCalendar` igual ao `cron` do
workflow, `OnFailure=` chamando `alertar.sh`, linha no `health.sh` (`ok` se o último run foi < período×1,5), teste que roda o comando do job contra
fixtures e afirma o alerta em caso de falha. Os ids dos workflows desligados estão em `workflows-desligados.json` (workspace de execução); religar um
workflow no GitHub só depois de o timer equivalente provar o mesmo resultado.

## Fora do plano

Mover repositórios da conta pessoal para uma organização; "sem crédito" separado de "CI vermelho" no PMO; segunda VPS (só se o spike reprovar o isolamento);
consertar o pagamento do GitHub.
