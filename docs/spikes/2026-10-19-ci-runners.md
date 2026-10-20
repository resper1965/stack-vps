# Spike: runners isolados da conta `ci` (2026-10-19)

Executado na VPS `stack` e na organização `bekaa-trusted-advisors`, com aprovação, em conta e repositório descartáveis (`cispike`,
`bekaa-trusted-advisors/ci-spike-runner`). **Tudo foi removido ao final** (container, arquivo da configuração JIT, 3 regras de firewall, conta,
`/home/cispike`, repositório de teste); conferido depois: 0 regras `spike-ci`, 0 runners na organização, `agente`, PMO, Tailscale e Docker do
sistema intactos. Nenhum segredo foi impresso.

| Pergunta | Resposta | Evidência |
|---|---|---|
| Pré-condições da VPS | Ok. Pacotes `uidmap`, `slirp4netns`, `rootlesskit`, `docker-ce-rootless-extras` e `dockerd-rootless-setuptool.sh` instalados; perfil AppArmor `usr.bin.rootlesskit` já existe; `fuse-overlayfs` ausente (não foi necessário); iptables 1.8.10 (backend nf_tables); `RUNNER_TOKEN` existe no `admin.env` | `dpkg -s`, `ls /etc/apparmor.d/usr.bin.rootlesskit`, `grep -o '^RUNNER_TOKEN='` |
| Escopo do `RUNNER_TOKEN` | PAT clássico com **só `admin:org`**; lê grupos de runners e runners das 3 organizações. Serve ao JIT de **organização**; o JIT de **repositório** exige também `repo` | cabeçalho `X-OAuth-Scopes: admin:org`; `GET /orgs/{org}/actions/runner-groups` e `/runners` = 200 nas 3 |
| Plano das organizações | **As 3 são `free`** (`bekaa-trusted-advisors` 15 privados + 1 público; `nessenergy` 43 privados + 1 público; `forense-io` 13 privados). Só existe o grupo `Default` (visibilidade `all`, repositórios públicos **não** permitidos). **Não dá para restringir o grupo a repositórios escolhidos** (recurso de plano pago). Workflows de fork em repositórios privados estão desligados (`run_workflows_from_fork_pull_requests=false`, forks de privados não permitidos) | `GET /orgs/{org}`, `/actions/runner-groups`, `/actions/permissions/fork-pr-workflows-private-repos` |
| Docker rootless para uma conta nova | Sobe em **~9 s** com os mesmos passos do `16-agente.sh` (subuid/subgid, linger, `dockerd-rootless-setuptool.sh install`). O `adduser` coloca a conta no grupo `users` (usar `useradd --system` no script de produção) e atribui sozinho um intervalo de subuid sem colidir (`296608:65536`) | `id cispike`, `/etc/subuid`, `systemctl --user is-active docker` |
| A regra por UID barra o container? | **Sim.** `iptables -I OUTPUT -m owner --uid-owner <uid> -d 100.64.0.0/10 -j REJECT` (e `169.254.169.254/32`, e `ip6tables` para `fd7a:115c:a1e0::/48`). Antes da regra o container alcançava `100.76.167.6:22` e `100.100.100.100:53`; depois, bloqueado (contadores: 4 pacotes na regra da tailnet, 2 na do metadata); a internet (`1.1.1.1:443`) continua funcionando; `dev` e `agente` não foram afetados. O container **não tem IPv6 global**, então a regra v6 não foi exercitada | `nc -z` antes/depois, `iptables -L OUTPUT -n -v -x` |
| Dentro de um job real | Do job (bash `/dev/tcp`): tailnet e metadata **bloqueados**, internet **ok**. Containers criados pelo job (aninhados) também ficam sem tailnet (a regra vale para a conta) | log do run no repositório de teste |
| A conta lê segredos? | **Não**: `/srv/dev/secrets/*`, `/home/agente`, `/home/dev`, `/etc/pmo/*`, `/srv/coder`, `/var/lib/pmo` negados; sem sudo; sem acesso aos sockets do Docker do sistema, do `agente` e do PMO. **Mas** `/srv/dev`, `/srv/dev/projetos` (755) e `/srv/dev/state` (755) são legíveis por qualquer conta, e há ao menos um `.env` legível (`ionic-health/ionic-txramp/.env`, conteúdo não lido) | `test -r`, `ls`, `find -readable` (só nomes) |
| Configuração JIT de ponta a ponta | **Funciona.** `generate-jitconfig` (repositório e organização) → container da imagem `ghcr.io/actions/actions-runner:latest` (2,16 GB, runner 2.338.0) → "Listening for Jobs" em ~10 s → pega o job → **se desregistra sozinho** (0 runners restantes). A configuração entra por `ACTIONS_RUNNER_INPUT_JITCONFIG` via `--env-file` (não pelo argv). O **ambiente do job não contém token nem JIT** (0 variáveis com nome de token/segredo) | `docker logs`, log do run, `GET .../actions/runners` |
| Caminho de produção | Validado: o `RUNNER_TOKEN` (`admin:org`), lido na VPS, gerou o JIT de **organização** (`HTTP 201`, grupo `Default`), o runner `spike-org` ficou online e executou o job | execução na VPS sem imprimir o token |
| Docker dentro do job | Montando o socket rootless da conta `ci` no container do runner: o socket aparece como `srw-rw---T root` e o usuário `runner` (que pertence aos grupos `sudo` e `docker` **do container**) só usa com `sudo`; funciona. **Um job com o socket pode montar `/srv/dev/projetos` e listar os 21 itens** (o que é legível por qualquer conta no host); `/srv/dev/secrets` continuou negado | log do run |

## Decisão

**Isolamento confirmado: seguir com a Task 2**, com estas mudanças no desenho (já refletidas no plano e no spec):

1. **O grupo restrito a repositórios escolhidos não existe nas organizações Free.** O supervisor passa a recusar iniciar quando o grupo
   permitir repositórios públicos (`allows_public_repositories`) **ou** quando a organização permitir workflows de fork em repositórios
   privados; a visibilidade `all` do grupo `Default` é aceita. Consequência: um runner de organização atende **qualquer repositório privado
   daquela organização** que peça o rótulo `stack`. Por isso: `bekaa-trusted-advisors` (piloto) e `forense-io` ok; **`nessenergy` (43 privados,
   inclusive repositórios de cliente) fica fora do nível de organização**; se precisar, só com runner por repositório, que exige um token com
   `repo` (o `RUNNER_TOKEN` atual não tem) e aprovação explícita.
2. **Docker em job é opt-in.** Por padrão o container do runner **não** recebe o socket. Só depois de apertar as permissões de
   `/srv/dev/projetos`, `/srv/dev/state` e `/srv/dev` (hoje 755; sugestão 750 para o dono e o grupo certos, decisão do Ricardo porque afeta
   `dev`, `pmo` e os agentes) é que um repositório pode pedir o socket.
3. **`38-ci-conta.sh` usa `useradd --system`** (sem o grupo `users`), shell `/bin/bash`, home `/srv/ci`.
4. **Imagem**: `ghcr.io/actions/actions-runner` (oficial), `./run.sh` com `ACTIONS_RUNNER_INPUT_JITCONFIG` em `--env-file` 0600 ou `docker run -e VAR`
   sem valor no argv; limites `--cpus 2 --memory 4g --pids-limit 512`.
5. A regra v6 (`fd7a:115c:a1e0::/48`) fica por precaução; o container rootless padrão não tem IPv6 global.

**Não verificado:** comportamento com vários runners simultâneos e carga real; `docker build` pesado dentro do job; tempo de pull da imagem em cada
reinício (a imagem fica no cache da conta `ci`).
