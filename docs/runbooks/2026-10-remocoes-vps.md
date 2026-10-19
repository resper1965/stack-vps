# Remoções na VPS (outubro de 2026)

> **Nada deste runbook foi executado.** Cada bloco destrutivo só roda com aprovação expressa do dono.
> Origem: o repositório deixou de ter OpenRig, sysbox, rede de containers, runners e Continue; a VPS ainda
> carrega o que esses scripts instalaram (estado lido em 2026-10-18, ver `docs/development-hub-continuity.md`).

## Pré-requisito (antes de qualquer bloco)

1. Snapshot novo: `sudo hostinger.sh snapshot --sim` (sem `--sim` só mostra o que faria). A Hostinger guarda
   **um** snapshot por VM: o novo **sobrescreve** o anterior.
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
(hoje não há container). Rollback: restaurar o snapshot (o script foi apagado do repositório; está no histórico do Git).

## 2. Containers e imagens de runner — root, DESTRUTIVO (só se existirem)

```sh
docker ps -a --filter name=runner
docker compose ls | grep runners-          # projetos runners-<org>
# para cada projeto listado:
docker compose -p runners-<org> down -v
docker images | grep -i runner             # remover as imagens listadas
rm -rf /srv/runners                        # envs com RUNNER_TOKEN: apague e revogue o token no GitHub
```

Conferência: `docker ps -a` vazio; `ls /srv/runners` retorna "No such file". Perde: runners efêmeros do
GitHub Actions (`runs-on: [self-hosted, stack]` deixa de ter quem execute). Rollback: sem volta pelo repositório
(`33-runners.sh` e `compose/runners.yml` foram removidos); restaurar o snapshot.

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

## Fechamento

`health.sh` verde de novo; registre a data da execução e o resultado no relatório da etapa.
