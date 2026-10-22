# CI sem créditos do GitHub — runners isolados, CI local e jobs na VPS

**Data:** 2026-10-19 · **Estado:** proposto, aguardando revisão do Ricardo
**Complementa** `docs/superpowers/specs/2026-10-18-lugar-de-trabalho-design.md` e **corrige** a decisão dele de tirar os
runners ("runners não são dependência do MVP"): para a Alup/ness, runner na VPS é justamente o caminho de CI sem minutos pagos.

## Problema

Não há créditos para GitHub Actions hospedado. Levantamento feito em 2026-10-19 sobre os 168 projetos ativos do PMO
(leitura da API do GitHub, nada alterado na época):

| Medida | Resultado |
|---|---|
| Repositórios com workflow | 53 |
| Só runner do GitHub (gasta crédito) | 52 (1 misto, **0 `self-hosted`**) |
| Por conta | `resper1965` 37 (33 privados), `bekaa-trusted-advisors` 6, `nessenergy` 6, `forense-io` 4; todos privados exceto 5 |
| Gatilhos | 47 em `pull_request`, 51 em `push`, **14 repositórios com workflow agendado ativo** (23 workflows; 11 desses repositórios são privados) |
| Última execução bloqueada por pagamento ou limite de gasto | **13**, todos da conta pessoal `resper1965` ("The job was not started because recent account payments have failed or your spending limit needs to be increased") |

As organizações **não** estão bloqueadas hoje (os agendados delas, inclusive os de cliente, rodaram com sucesso em 2026-10-19);
o bloqueio é da conta pessoal. Ainda assim a restrição vale para todos, então o desenho não depende de crédito em lugar nenhum.

O que as configurações da stack já previam: `standards/profiles.json` tem `"ci": "local-vps"` por padrão, o `docs/AGENTS.md`
original dizia `CI: runs-on: [self-hosted, stack] (runners da VPS, sem minutos pagos)` e o bootstrap não cria Actions sozinho.
O que **desfez** isso: a remoção do Coder (PR #7) e a decisão de tirar os runners; o PR #18 também tirou a linha de CI do `AGENTS.md`, e os 4
runners que rodavam no Docker do sistema foram removidos em 2026-10-19. Nenhum workflow usava `self-hosted`, então nada quebrou.

Ações já tomadas em 2026-10-19 (com aprovação): 10 workflows **agendados** de 8 repositórios privados da conta pessoal, que já
falhavam para iniciar, foram desligados (`gh workflow disable`; reativar com `gh workflow enable <id> --repo <repo>`; os ids ficam no
registro local `workflows-desligados.json` do workspace de execução, fora do Git; os 10 são: `DocVault` (nightly), `aegis-itms`
(security-nightly), `be-secure` (codeql), `dns-repair` (dnscheck), `n.360-alternative` (backup e vigilancia), `n.discovery`
(codeql e security), `nTransfer` (codeql) e `site-sabrina` (codeql-analysis)). Isso deixou **sem execução**: o backup diário do `n.360-alternative`, a verificação diária de
DNS do `dns-repair` e as varreduras de segurança (CodeQL, Security, DefectDojo, SSDLC) de alguns repositórios.

## Decisões

| Tema | Decisão |
|---|---|
| Runners | **Containers efêmeros na `stack`, isolados**, sob uma conta `ci` (usuário comum, UID >= 1000, sem shell de login); só repositórios **privados** de organizações; as 3 organizações são plano Free, então o runner de organização atende **todos** os privados dela (ver spike) |
| Conta pessoal `resper1965` | **Sem runner por enquanto.** CI local (abaixo). Repositórios que importarem podem ser movidos a uma organização depois, a pedido |
| CI local | Todo projeto tem um comando único de CI; o agente o roda antes de commit e de PR; padrão dos projetos novos |
| Jobs agendados parados | Viram **timers systemd** na VPS, com alerta de falha e presença no bloco Saúde |
| Migração de workflows | Nada em massa: **um PR por repositório**, só quando o Ricardo pedir; repositórios de cliente por último e só com aprovação explícita |

## 1. Runners isolados

- **Conta `ci`:** usuário comum (UID >= 1000, shell `nologin`), sem sudo, **sem leitura de `/srv/dev/secrets`**, com Docker rootless próprio (separado do
  Docker do `agente` e do Docker do sistema).
- **Rede:** regra de firewall por UID da conta `ci` negando destino `100.64.0.0/10` (tailnet) e `169.254.169.254` (metadata), e
  nada publicado. Substitui o `31-rede-containers` (que protegia só o Docker do sistema, via `DOCKER-USER`). *Confirmado no spike (`docs/spikes/2026-10-19-ci-runners.md`): o tráfego de um
  Docker rootless sai com o UID da conta e a regra o recusa, inclusive para containers criados pelo job.*
- **Runners:** efêmeros, imagem do runner oficial do GitHub (ou `myoung34/github-runner`, como antes), o grupo `Default` de cada
  organização (as 3 são Free: não existe grupo restrito a repositórios escolhidos), rótulo `[self-hosted, stack]`. O supervisor recusa iniciar
  se o grupo permitir repositório público ou se a organização permitir workflows de fork em repositórios privados. **Organizações do nível
  de organização: `bekaa-trusted-advisors` (piloto) e `forense-io`.** `nessenergy` (43 privados, inclusive de cliente) fica de fora; se precisar,
  só runner por repositório (exige token com `repo`) e aprovação explícita.
- **Registro sem vazar o token:** o runner antigo recebia o token de organização (`ACCESS_TOKEN`, com `admin:org`) como variável de ambiente do
  container, e o código de um PR consegue ler isso. Aqui, um **supervisor** que roda fora do container (como a conta `ci`) guarda o token
  num arquivo `0400` e, para cada runner, chama a API `generate-jitconfig` da organização (configuração de uso único, já com o rótulo e o
  grupo) e passa **só essa configuração** ao container. O container nunca vê o token; a configuração JIT serve para um único runner
  efêmero. Nunca em argumento de linha de comando, log ou Git (mesmo padrão do `alertar.sh`).
- **Scripts e supervisor:** `scripts/38-ci-conta.sh`, `39-ci-rede.sh` e `40-ci-runners.sh` mais o supervisor `ci/runners.py` (unidade
  `stack-ci-runners.service`) substituem o `33-runners.sh` e o `compose/runners.yml` antigos (que rodavam no Docker do sistema com sysbox e
  estão no histórico do `main`). Token e config ficam em `/etc/stack-ci` (root:ci 0750; config `root:ci 0640` (a conta só lê); token `ci:ci 0400` (a conta é dona do arquivo, mas nem o root o lê depois)); só o `status.json` fica em `/srv/ci`.
- **Saúde:** `health.sh` confere o isolamento de rede, a unidade e o `status.json` dos runners da conta `ci`; falha vira alerta. Ele **não** consulta o
  Docker rootless diretamente: um Docker parado só aparece pelo campo `erro` do `status.json` (ou por `status.json` velho).
- **Segurança de uso:** só repositórios privados (runner self-hosted em repositório público é risco de execução de código de
  terceiros); PR vindo de fork nunca roda em runner (configuração do grupo).

## 2. CI local

- Cada projeto expõe **um comando de CI** (`npm test`, `pytest`, `bash tests/run.sh`, `make ci`...). O `docs/AGENTS.md` volta a
  ter a linha de CI, agora assim: o agente roda o CI local antes de commit e de PR; onde houver runner da `stack`, o workflow usa
  `runs-on: [self-hosted, stack]`; **nunca** `ubuntu-latest` em repositório privado.
- O padrão dos projetos novos fica `ci: local-vps` (já está em `standards/profiles.json`). Publicar um status de commit no GitHub
  pelo CI local é opcional e fica para depois.

## 3. Jobs agendados viram timers

- Primeiros candidatos (hoje desligados e sem execução): backup diário do `n.360-alternative`, verificação diária de DNS do
  `dns-repair`, e as varreduras de segurança dos repositórios privados da conta pessoal.
- Cada job vira uma unidade systemd `*.service` + `*.timer` de usuário (`agente`, ou `ci` quando não precisar de segredo),
  com alerta de falha pelo `alertar.sh` e linha no bloco Saúde.
- **Dependência do Ricardo:** esses workflows usam **segredos do GitHub**, que o GitHub não devolve; os valores precisam ir para
  `projetos.env`. O desenho de cada job só começa depois de ler o workflow correspondente (uma tarefa por job).

## 4. Correções dos entregáveis do PR #18

- `docs/AGENTS.md`: devolver a linha de CI com o texto novo.
- `docs/development-hub-continuity.md` e `docs/runbooks/2026-10-remocoes-vps.md`: o registro "nenhum container Docker rodando" estava
  errado (conferi só o Docker do `agente`); o Docker do sistema tinha **6 containers** (Coder: `coder-coder-1`, `coder-database-1`;
  runners: 2 de `nessenergy` e 2 de `bekaa-trusted-advisors`). Registrar o que foi removido e o que sobrou (volumes
  `coder-…-home` e `coder-…-agentes`, `/srv/coder`, imagens, redes `coder_default` e `runners-*_default`, container parado
  `coder-ricardo-teste`).
- `docs/superpowers/specs/2026-10-18-lugar-de-trabalho-design.md` e o plano: trocar "runners fora do MVP" por esta decisão.

## 5. Ordem de entrega

1. Correções de documentos (item 4) — sem efeito em produção.
2. Spike: Docker rootless da conta `ci` + regra de firewall por UID (resposta, não código).
3. Conta `ci`, regra de rede, supervisor (`38`/`39`/`40` + `ci/runners.py`), saúde — com snapshot antes e aprovação em cada passo.
4. Primeiro repositório piloto de uma organização (não-cliente): um PR trocando `runs-on` e uma execução de ponta a ponta.
5. Um job agendado por vez migrado para timer (backup primeiro), cada um com o seu plano.

## Fora de escopo

Mover repositórios da conta pessoal para uma organização; mostrar "sem crédito" separado de "CI vermelho" no PMO; segunda VPS só de CI;
consertar o pagamento do GitHub (solução mais barata para a conta pessoal, e é decisão do Ricardo).

## Riscos aceitos

- Runner na mesma máquina da estação de trabalho: mitigado por conta dedicada, Docker rootless, regra de rede por UID, efêmero e
  só privados; **se o isolamento do spike não se confirmar, parar e propor a segunda VPS de CI**.
- Jobs de cliente (`nessenergy/Alupdatalake`, `nessenergy/sitealupar`) hoje rodam com minutos da organização; migrar só com
  aprovação explícita e nunca como efeito colateral de um PR em massa.
- **`docker_socket` é opt-in:** com o socket do Docker rootless, um job pode montar caminhos do host (visíveis à conta `ci`) e ler os JIT dos
  runners vizinhos; o supervisor só aceita com `docker_socket_ciente_do_risco: true` e vale apenas para repositórios totalmente confiáveis.
- **`RUNNER_TOKEN` é um PAT clássico com `admin:org` das 3 organizações e passa a ficar legível pela conta `ci`** (`/etc/stack-ci/token`, 0400).
  Um escape do container ou do Docker rootless até a conta `ci` dá `admin:org`, **inclusive em `nessenergy`**. Mitigação futura, a verificar:
  PAT fine-grained por organização (um por organização, só o escopo de runners). **Decisão do Ricardo (2026-10-22): manter o PAT atual no piloto** (opção mais simples), aceitando este risco; revisar antes de abrir runners em mais organizações.
