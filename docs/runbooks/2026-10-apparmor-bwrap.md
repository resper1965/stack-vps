# Runbook: liberar user namespaces para o bwrap (Codex)

> **Status: preparado, NÃO aplicado na VPS.** Só aplicar depois da aprovação do dono.

## Por que

O Ubuntu 24.04 liga `kernel.apparmor_restrict_unprivileged_userns=1`: processos sem perfil
AppArmor com a permissão `userns` não conseguem criar user namespaces. O isolamento do Codex usa
bubblewrap (`/usr/bin/bwrap`, pacote `bubblewrap`, não-setuid, 0755 root:root) e por isso avisa
"Codex's Linux sandbox uses bubblewrap and needs access to create user namespaces". Sem a
liberação, o Codex roda sem o isolamento. O molde já existe na VPS para o rootlesskit
(`/etc/apparmor.d/usr.bin.rootlesskit`).

## O que muda

1. `apparmor/usr.bin.bwrap` vira `/etc/apparmor.d/usr.bin.bwrap` (0644 root): perfil
   `flags=(unconfined)` para `/usr/bin/bwrap` com **apenas** a regra `userns,` e o include local
   (`local/usr.bin.bwrap`) para ajustes do dono.
2. `dpkg-statoverride` deixa `/usr/bin/bwrap` em **0750 root:agente**. O statoverride sobrevive a
   atualizações do pacote.

## O que o perfil permite e o que NÃO permite

- Permite: o `bwrap` criar user namespaces.
- Não concede nenhuma outra permissão; o `bwrap` continua sem confinamento, como já estava.
- Não altera o sysctl `kernel.apparmor_restrict_unprivileged_userns`: a restrição segue ligada
  para todo o resto do sistema.
- Não libera outros binários (um `unshare` ou um interpretador qualquer continua barrado).

## Risco aceito

User namespaces sem privilégio ampliam a superfície de ataque do kernel (é a razão da restrição
existir). Para conter isso, só root e o grupo `agente` conseguem executar o `bwrap`; outras contas
locais (por exemplo `ci` e `dev`) deixam de poder rodá-lo. Quem usa o `bwrap` hoje além do agente
precisa ser verificado antes de aplicar.

## Aplicar

```
sudo /opt/stack-vps/scripts/47-apparmor-bwrap.sh --status
sudo /opt/stack-vps/scripts/47-apparmor-bwrap.sh --instalar
```

O `--instalar` recusa se `/usr/bin/bwrap` não existir, se o grupo `agente` não existir, se o
perfil do repo for inválido (`apparmor_parser -Q -T`), se já houver um statoverride diferente do
bwrap ou se `/etc/apparmor.d/usr.bin.bwrap` existir e diferir do repo. É idempotente e imprime o
comando de rollback.

## Conferir

```
sudo -u agente -H bash -lc 'bwrap --ro-bind / / true && echo ok'
```

Deve imprimir `ok`. Depois, `codex-9r exec ...` não deve mais mostrar o aviso de user namespaces.
Conferir também que outra conta (`sudo -u dev bwrap --version`) recebe "Permission denied".

## Rollback

```
sudo /opt/stack-vps/scripts/47-apparmor-bwrap.sh --remover
```

Descarrega e remove o perfil, remove o statoverride e restaura 0755 root:root. Só mexe no que o
`--instalar` criou: recusa se o perfil instalado diferir do repo (arquivo do dono) ou se o
statoverride não for o nosso.
