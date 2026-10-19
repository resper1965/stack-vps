# Remoções na VPS (outubro de 2026)

> **Nenhum bloco numerado deste runbook foi executado.** Cada bloco destrutivo só roda com aprovação expressa do dono.
> Origem: o repositório deixou de ter OpenRig, sysbox, rede de containers, runners e Continue; a VPS ainda
> carrega o que esses scripts instalaram (estado lido em 2026-10-18, ver `docs/development-hub-continuity.md`).
>
> **Já feito em 2026-10-19, com aprovação do dono (fatos, fora dos blocos):** o Docker do sistema tinha 6 containers
> (o levantamento de 2026-10-18 só conferiu o Docker rootless do `agente`). Os 2 do Coder (`coder-coder-1`,
> `coder-database-1`) e os 4 runners (`runners-nessenergy-runner-1/2`, `runners-bekaa-trusted-advisors-runner-1/2`)
> foram parados e **removidos** (`docker stop` + `docker rm`). A rota `coder.ness.com.br` saiu da configuração do tunnel
> (`06-tunnel.sh` reexecutado, `TUNNEL_EXTRA` vazio); o registro DNS na Cloudflare ficou (órfão, responde 404).
> O que sobrou está nos blocos 2, 2b e 2a (nessa ordem). Os runners voltam em outra forma (`docs/superpowers/specs/2026-10-19-ci-sem-creditos-design.md`).

## Pré-requisito (antes de qualquer bloco)

1. Snapshot novo. O `hostinger.sh` só é instalado em `/usr/local/bin` pelo `05-servicos.sh`, que roda depois:
   chame-o pelo clone. Primeiro `sudo bash /opt/stack-vps/bin/hostinger.sh metricas` (confere a credencial, só
   leitura) e então `sudo bash /opt/stack-vps/bin/hostinger.sh snapshot --sim` (sem `--sim` só mostra o que
   faria). A Hostinger guarda **um** snapshot por VM: o novo **sobrescreve** o anterior.
2. `health.sh` verde (`/srv/dev/bin/health.sh`, ver `docs/srv-dev-README.md`). Se não estiver verde, pare.

Rollback geral: restaurar o snapshot.

## 1. Rede dos containers (`stack-rede-containers`) — root, DESTRUTIVO

O que o script antigo (`31-rede-containers.sh --instalar`) mudou na VPS:

- regras `DROP` na chain `DOCKER-USER` para `100.64.0.0/10` (tailnet) e `169.254.169.254/32` (metadata);
- `"dns": ["1.1.1.1", "8.8.8.8"]` em `/etc/docker/daemon.json` (reinicia o Docker se mudar);
- `/usr/local/lib/stack-vps/31-rede-containers.sh`, `/etc/systemd/system/stack-rede-containers.service` (habilitada).

```sh
systemctl disable --now stack-rede-containers.service
rm /etc/systemd/system/stack-rede-containers.service /usr/local/lib/stack-vps/31-rede-containers.sh
systemctl daemon-reload
# regras: apagar as duas (repetir o -D até dar erro se houver duplicata)
iptables -D DOCKER-USER -d 100.64.0.0/10 -j DROP
iptables -D DOCKER-USER -d 169.254.169.254/32 -j DROP
# DNS: tirar a chave do daemon.json e reiniciar o Docker (só sem containers rodando)
jq 'del(.dns)' /etc/docker/daemon.json > /tmp/daemon.json && install -m 644 /tmp/daemon.json /etc/docker/daemon.json && rm /tmp/daemon.json
systemctl restart docker
```

Conferência: `systemctl is-enabled stack-rede-containers` imprime `disabled`/`not-found`;
`iptables -S DOCKER-USER` não lista `100.64.0.0/10` nem `169.254.169.254`; `jq .dns /etc/docker/daemon.json` imprime `null`.

Perde: o bloqueio de containers à tailnet e ao metadata. Seguro enquanto nenhum container de terceiro rodar
(desde 2026-10-19 os runners e o Coder foram removidos; só resta o `coder-ricardo-teste`, parado).
Rollback: restaurar o snapshot (o script foi apagado do repositório; está no histórico do Git).

**Quando executar este bloco.** Ele protegia só o Docker do sistema, e a conta `ci` planejada (spec 2026-10-19) o
substitui por uma regra de firewall por UID (ainda inexistente). Então: ou se executa junto com ou depois da regra da
`ci`, ou o dono aceita que hoje nenhum container precisa dele (nenhum container de terceiro roda). Não há pressa: a
proteção só faz falta se algum container voltar a subir no Docker do sistema. O mesmo vale para o `sysbox` (bloco 3):
ele não sustenta nada agora, e a `ci` usa Docker rootless.

## Antes dos blocos 2, 2a e 2b: o `docker` tem de falar com o daemon do SISTEMA

Os containers do Coder e dos runners viviam no Docker do **sistema** (root), não no Docker rootless do `agente`. Conferir
o daemon errado foi o que gerou a afirmação falsa "nenhum container rodando". Rode estes blocos como root (`sudo -i`),
sem `DOCKER_HOST` e sem `XDG_RUNTIME_DIR` do `agente` no ambiente, e nunca como `agente`. Confirme:

```sh
echo "${DOCKER_HOST:-}"                       # esperado: vazio
docker info --format '{{.DockerRootDir}}'     # esperado: /var/lib/docker
```

Se imprimir outro caminho (por exemplo `~/.local/share/docker`), pare: é o daemon rootless. As conferências "`docker ps -a`
vazio" e "redes só `bridge`, `host`, `none`" abaixo só valem nesse daemon. **Ordem:** 2b (backup e dados) antes de 2a,
porque o backup dos volumes usa a imagem `alpine:latest`, que o 2a remove.

## 2. Containers de runner — JÁ REMOVIDOS em 2026-10-19; restos de imagem, rede e diretório — root, DESTRUTIVO

Os 4 containers `runners-*-runner-*` já foram removidos. Sobram a imagem, as redes e, se existir, `/srv/runners`.
Daemon do sistema, conforme a seção acima.

```sh
docker ps -a --filter name=runner                       # esperado: vazio
docker compose ls | grep runners-                       # projetos compose órfãos, se listar
docker network rm runners-nessenergy_default runners-bekaa-trusted-advisors_default
docker rmi myoung34/github-runner:ubuntu-noble          # 3,33 GB
# envs com RUNNER_TOKEN: apague e revogue o token no GitHub
test "$(realpath /srv/runners)" = /srv/runners && test -d /srv/runners && rm -rf -- /srv/runners
```

Se a guarda falhar (o `test` sai com código 1 e nada é apagado): `/srv/runners` não existe (nada a fazer) ou é um link
simbólico para outro lugar (o `realpath` mostra o destino): não apague, investigue.

Conferência: `docker images | grep -i runner` não imprime nada; `docker network ls | grep runners-` não imprime nada;
`ls /srv/runners` retorna "No such file". Perde: só a imagem (rebaixa de novo se o runner voltar) e os tokens. Rollback:
a imagem se baixa outra vez; o `33-runners.sh` e o `compose/runners.yml` estão no histórico do `main` e voltam
adaptados pela spec 2026-10-19. Revogue no GitHub o token que estava em `/srv/runners`.

## 2b. Dados do Coder: volumes e `/srv/coder` — root, DESTRUTIVO, **irreversível** (executar ANTES do 2a)

Aqui estão os dados reais do Coder: o banco (`/srv/coder`, root 0700) e a home dos workspaces (volumes). **Não há volta
depois destes comandos.** Daemon do sistema, conforme a seção acima. Antes: decida com o dono se algo daqui importa. Se
sim, faça o backup abaixo para fora da VPS **e** um snapshot novo (a Hostinger guarda **um** snapshot por VM: o novo
sobrescreve o anterior). Sem essa decisão registrada (backup feito, ou "não precisa"), não prossiga.

```sh
D=<destino-do-backup>                                   # diretório com espaço, fora de /srv/coder
tar -C /srv -czf "$D/coder.tgz" coder
for V in coder-b8dec1e8-0db7-492a-88d4-70e382da0439-home coder-e7fd6a59-faa3-4fde-a794-4fe7061b08cc-agentes; do
  docker run --rm -v "$V":/v -v "$D":/b alpine tar -C /v -czf "/b/$V.tgz" .
done
ls -l "$D"                                              # esperado: coder.tgz e um .tgz por volume, com tamanho > 0
```

(Se o `alpine:latest` já não existir, o `docker run` o baixa de novo.) Prova de que os volumes não estão em uso, um por
um, antes de cada remoção:

```sh
docker volume ls | grep coder-                          # esperado: os 2 volumes
docker ps -a --filter volume=coder-b8dec1e8-0db7-492a-88d4-70e382da0439-home       # esperado: só o cabeçalho (nenhum container)
docker volume rm coder-b8dec1e8-0db7-492a-88d4-70e382da0439-home
docker ps -a --filter volume=coder-e7fd6a59-faa3-4fde-a794-4fe7061b08cc-agentes    # esperado: só o cabeçalho (nenhum container)
docker volume rm coder-e7fd6a59-faa3-4fde-a794-4fe7061b08cc-agentes
du -sh /srv/coder                                       # confira o tamanho do que será apagado
test "$(realpath /srv/coder)" = /srv/coder && test -d /srv/coder && rm -rf -- /srv/coder
```

Se um `docker ps -a --filter volume=...` listar um container, **não remova esse volume**: ele ainda está em uso
(provavelmente `coder-ricardo-teste`, que o 2a remove; nesse caso decida e remova o container antes). Se a guarda do
`test` falhar (código 1, nada apagado): `/srv/coder` não existe ou é link simbólico; não apague, investigue.

Conferência: `docker volume ls | grep coder-` não imprime nada; `ls /srv/coder` retorna "No such file".
Perde, **irreversivelmente**: o banco do Coder (usuários, workspaces, templates) e o conteúdo das duas homes de workspace.
Rollback: só pelo backup/snapshot feito antes (restaurar o snapshot desfaz também tudo o mais feito depois dele).

## 2a. Coder: container parado, imagens e rede — root, DESTRUTIVO (depois do 2b)

Os containers `coder-coder-1` e `coder-database-1` já foram removidos em 2026-10-19. Sobra o container **parado**
`coder-ricardo-teste` (workspace do Coder), as imagens e a rede. Daemon do sistema, conforme a seção acima.

```sh
docker ps -a --filter name=coder                        # esperado: só coder-ricardo-teste, parado
docker rm coder-ricardo-teste
docker network rm coder_default
docker rmi ghcr.io/coder/coder:latest postgres:17 alpine:latest stack/web
```

Antes: `docker ps -a` e `docker images`; se `postgres:17`, `alpine:latest` ou `stack/web` (5,28 GB) servirem a outro
app seu, não os remova. O Docker recusa remover imagem em uso por container.

Conferência: `docker ps -a` vazio; `docker network ls` só com `bridge`, `host` e `none`; `docker images` sem as imagens acima.
Perde: o container de teste (a home dele provavelmente vive no volume do bloco 2b, não no container) e imagens
rebaixáveis. Rollback: as imagens se baixam de novo; o container de teste não se recria (o Coder saiu, PR #7).

## 3. sysbox — root, DESTRUTIVO

O `30-sysbox.sh` só instalou o `.deb` `sysbox-ce 0.7.1` (e `jq`); não editava `daemon.json`. O pacote registra
o runtime `sysbox-runc` no Docker por conta própria: confira o arquivo antes e depois.

```sh
test -z "$(docker ps -q)"                  # o purge reinicia o Docker; precisa estar vazio
apt-get purge -y sysbox-ce
jq '.runtimes' /etc/docker/daemon.json     # se ainda houver "sysbox-runc", apague a entrada e reinicie o Docker
systemctl restart docker
```

Conferência: `dpkg -s sysbox-ce` falha ("not installed"); `docker info | grep -i sysbox` não imprime nada;
`systemctl is-active sysbox` imprime `inactive`/`unknown`. Perde: Docker-in-Docker sem privilégio.
Rollback: restaurar o snapshot (ou reinstalar o `.deb` 0.7.1 com SHA-256 conferido).

## 4. Continue — agente, DESTRUTIVO

```sh
sudo -u agente -H bash -c '
  rm -rf ~/.continue
  CS=$(find ~/.vscode-server/cli/servers -maxdepth 4 -path "*/server/bin/code-server" | head -1)
  [ -n "$CS" ] && "$CS" --uninstall-extension continue.continue
'
```

Conferência: `sudo -u agente ls -d /home/agente/.continue` falha; `ls /home/agente/.vscode-server/extensions | grep -i continue`
não imprime nada. Perde: a config de modelos do Continue (era gerada por `modelo --continue`, recriável) e o
atalho para `agente.env` (o `.env` era um link; o arquivo de segredos não é tocado, mas confira que o `rm -rf` não seguiu o link: `ls -l /srv/dev/secrets/agente.env`).

## 5. OpenRig (pacote, estado e variáveis do `.bashrc`) — root/agente, DESTRUTIVO

O `22-openrig.sh` instalou o pacote npm global `@openrig/cli`, copiou `rig-dupla` para `~/.local/bin`, criou
`/srv/dev/state/openrig` e **acrescentou 4 linhas ao `~/.bashrc` do `agente`** (sem marcador de início/fim; só entram
se o arquivo ainda não continha `OPENRIG_HOME`):

```
export OPENRIG_HOME=/srv/dev/state/openrig
export OPENRIG_SHARED_DOCS_ROOT=/srv/dev/state/openrig/shared-docs
export OPENRIG_NO_KERNEL=1
export OPENRIG_RUNTIME_CODEX_HOOKS_ENABLED=false
```

```sh
# 5a. pacote e atalho. O npm vem do mise: login shell do agente (o script antigo exportava
# ~/.local/bin e ~/.local/share/mise/shims no PATH antes de usar npm).
sudo -u agente -H bash -lc 'npm rm -g @openrig/cli; mise reshim; rm -f ~/.local/bin/rig-dupla'
# Se o pacote nunca esteve instalado, o npm responde "up to date" e sai com 0: não é erro.

# 5b. estado
rm -rf /srv/dev/state/openrig

# 5c. variáveis do .bashrc: mostrar, fazer backup, remover só as 4 linhas, conferir
sudo -u agente -H bash -c '
  grep -n OPENRIG ~/.bashrc                      # revise: devem ser exatamente as 4 linhas acima
  cp -p ~/.bashrc ~/.bashrc.bak-$(date +%Y%m%d)
  sed -i "/^export OPENRIG_\(HOME\|SHARED_DOCS_ROOT\|NO_KERNEL\|RUNTIME_CODEX_HOOKS_ENABLED\)=/d" ~/.bashrc
  grep -c OPENRIG ~/.bashrc                      # esperado: 0
'
sudo -u agente -H bash -lc 'echo ok'            # esperado: ok (o .bashrc continua carregando)
```

Se o `grep -n` mostrar outras linhas com `OPENRIG` (editadas à mão), o `sed` não as apaga: trate-as à mão.
Os shells já abertos mantêm as variáveis; os novos não as terão. Restaurar: `cp -p ~/.bashrc.bak-AAAAMMDD ~/.bashrc`.

Conferência: `test ! -e /srv/dev/state/openrig && echo ok`; `sudo -u agente -H bash -lc 'command -v rig rig-dupla'`
não imprime nada. Perde: rigs, especificações geradas dos `STATE.md` e o histórico do daemon do OpenRig.
Os `STATE.md` dos projetos não são afetados. As branches/commits `chore/papeis-<data>` que o `23-papeis.sh` fez nos
repositórios permanecem e são inofensivos (dá para apagá-las depois, se quiser). Rollback: restaurar o snapshot.

## 6. Regra do UFW para a porta 8080 — root, DESTRUTIVO

O `07-firewall.sh` antigo abria `8080/tcp` em `tailscale0` para o painel do PMO. O painel agora escuta em socket
Unix, atrás do `tailscale serve` (443 e 8443), então nada escuta em 8080 e a regra é só superfície. O script novo
não a cria, mas a regra já aplicada continua na VPS (rodar o `07` de novo faria `ufw reset` e a tiraria).

```sh
ufw status numbered | grep 8080                   # confira que existe e que é a de tailscale0
ufw delete allow in on tailscale0 to any port 8080 proto tcp
```

(Se o `ufw` pedir confirmação, responda `y` só depois de conferir a regra listada.)

Conferência: `ufw status | grep 8080` não imprime nada; `ufw status` continua listando 22 e 41641/udp; a
sessão SSH aberta segue de pé. Rollback: `ufw allow in on tailscale0 to any port 8080 proto tcp`.

## Rollback do deploy da etapa 2

Depois do `git revert` do merge e de rodar de novo o `34-pmo.sh`, desfaça também a publicação da tailnet,
senão o `tailscale serve` continua apontando para o socket e para o OpenCode (a configuração persiste):

```sh
tailscale serve reset             # ou, por porta: tailscale serve --https=8443 off; tailscale serve --https=443 off
tailscale serve status            # esperado: sem configuração
```

## Fechamento

`health.sh` verde de novo; registre a data da execução e o resultado no relatório da etapa.
