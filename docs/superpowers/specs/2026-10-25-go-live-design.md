# Go-live: instalação completa e funcionando (9router, OpenCode, CLIs, CI)

**Data:** 2026-10-25 · **Estado:** aprovado pelo Ricardo em 2026-10-25 ("sim")
**Complementa** `2026-10-18-lugar-de-trabalho-design.md`, `2026-10-19-ci-sem-creditos-design.md` e
`2026-10-23-9router-e-novo-projeto-design.md`. Este documento não muda decisões: fecha a distância entre o código e a VPS.

## Problema

O código das etapas 2 a 6 está pronto e revisado, mas na VPS só rodam o PMO, o OpenCode Web, o `tailscale serve` e as permissões
apertadas. O 9router, o `/novo-projeto`, o CI isolado e os CLIs de assinatura não estão instalados, não há um critério único de
"está tudo funcionando", e os segredos precisam entrar na VPS sem passar pela conversa.

## Decisões

| Tema | Decisão |
|---|---|
| Critério de pronto | `bin/stack-doctor` (só leitura) devolve zero `FALTA`. Cada linha é `ok`, `pend` (depende do dono) ou `FALTA` |
| Segredos | `scripts/43-segredos-guiado.sh` roda **na VPS**, pede cada valor com entrada oculta (ou gera aleatório), grava em arquivo 0600 do usuário certo. Nenhum valor passa pelo Claude, por argv ou por log |
| Ordem | 1) código no `main` (dono faz o merge); 2) 9router + OpenCode de ponta a ponta; 3) CLIs de assinatura; 4) CI (piloto `bekaa-trusted-advisors`); 5) restos do runbook de remoções; 6) abertos antigos |
| Passos na VPS | Um comando por vez, com aprovação; o que o classificador barra (merge de PR, concessão de acesso, regra de firewall) fica com o dono, que executa ou autoriza de forma explícita |
| Execução | Fases com portão: a fase só termina quando as linhas do `stack-doctor` daquela fase estão `ok` (ou `pend` com dono nomeado) |

## 1. `bin/stack-doctor`

Só leitura, sem rede externa, saída por seção (como o `health.sh`), exit 1 se houver `FALTA`. Roda como `dev` (usa `sudo -n` só para
o que exige). Seções e verificações:

- **código:** `/opt/stack-vps` na branch `main` e sem alteração local; scripts 41, 42 e o comando `novo-projeto.md` presentes.
- **acesso:** `tailscale serve` com 443, 8443 e 20128; MagicDNS resolve o nome da máquina.
- **permissões:** `/srv/dev` 751, `projetos` e `state` 750, `pareceres` 750 do `agente`; `pmo` no grupo `agente`; conta `ci` sem leitura de `projetos`.
- **opencode:** unidade ativa, HTTP 200/302/401, `jq` instalado, `opencode.json` com o provedor `9router` e sem `model` definido pelo script, comando `novo-projeto.md` instalado com o marcador.
- **9router:** pacote `0.5.104`, `~/.config/9router/9router.env` 0600 do `agente`, unidade ativa, `/api/health` 200, `/v1/models` sem chave 401, `client.env` 0600, nada escutando em `0.0.0.0:20128`.
- **modelos:** `NINE_ROUTER_API_KEY` presente em `agente.env`; um `GET /v1/models` **com** a chave devolve ao menos um modelo (a chave é lida pelo próprio doctor do arquivo e nunca impressa).
- **clis:** `claude`, `codex` e `agy` no PATH do `agente` (login é `pend`: o doctor só confere a presença do diretório de configuração, não o conteúdo).
- **ci:** `ci-conta`, rede por UID, unidade `stack-ci-runners` (instalada, ativa e `status.json` fresco); `pend` se ainda não instalado.
- **restos:** sysbox, `~/.continue`, OpenRig, regra 8080 do UFW, imagem de runner, `/srv/coder`, `/srv/runners` ausentes.

Overrides de teste só com `STACK_TESTE=1`. Nenhum valor de segredo é impresso.

## 2. `scripts/43-segredos-guiado.sh`

Roda como o usuário-alvo (`agente` para tudo, exceto onde dito). Subcomandos, cada um idempotente e que **recusa sobrescrever** um arquivo
existente sem `--trocar`:

- `9router`: cria `~/.config/9router/9router.env` (0600) com `INITIAL_PASSWORD` (≥ 16; `--gerar` cria aleatório de 24+ caracteres) e
  `JWT_SECRET` (sempre gerado, 48+ caracteres). Com `--gerar` a senha **não** é impressa: o dono a lê uma vez com `cat` do arquivo para entrar no painel.
- `cliente` (como `agente`): pede `NINE_ROUTER_API_KEY` (a chave criada no painel) com entrada oculta e grava em `~/.config/9router/client.env` (0600).
  Ao fim imprime a etapa seguinte, sem valor: `como dev: /opt/stack-vps/scripts/43-segredos-guiado.sh agente`.
- `agente` (como `dev`): pede a mesma chave e grava a linha `NINE_ROUTER_API_KEY=` em `/srv/dev/secrets/agente.env`, sem duplicar (reconhece `export`).
  Existe separado porque o `agente.env` e `dev:agente` 0640 (criado pelo `02-layout.sh`): o `agente` nao escreve nele e o `dev` nao pertence ao grupo `agente`,
  entao o subcomando grava no mesmo inode (`cat > arquivo`), sem `mv` nem `chown`, preservando dono, grupo e modo; restaura o original se a gravacao falhar.
- `linear` (como root): pede `LINEAR_API_KEY` e `LINEAR_TEAM_KEY` e grava `/etc/pmo/linear-token` e `/etc/pmo/linear-team` (root:pmo 0640, valor cru), onde `pmo/linear.py` le;
  sem root o subcomando diz `sudo /opt/stack-vps/scripts/43-segredos-guiado.sh linear`.

Valores recusados: vazios, com aspas no início, com qualquer caractere de controle (CR, quebra de linha, tab), e senha < 16.

## 3. Runbook `docs/runbooks/2026-10-go-live.md`

Fases com portão, comandos exatos, o que o dono faz e o que o Claude faz, e rollback de cada fase:

0. Dono: merge do #19 e do #20; snapshot no hPanel. VPS: `/opt/stack-vps` volta para `main` (`sudo git -C /opt/stack-vps checkout main && sudo git -C /opt/stack-vps pull --ff-only`).
1. 9router: spike (permissão de `~/.9router` depois do primeiro start, `requireApiKey` no painel, túnel embutido desligado, endpoint com chave), `43 9router`, `41-9router.sh`, `37-tailscale-serve.sh`, entrar no painel, cadastrar as chaves (OpenRouter, DeepSeek, Featherless), criar a chave de API, `43 cliente`, `36-opencode.sh`, escolher modelo no OpenCode, testar uma pergunta e `/novo-projeto`.
2. CLIs: instalar `claude`, `codex`, `agy` como `agente`; dono faz os logins (duas contas Claude em `CLAUDE_CONFIG_DIR` separados).
3. CI (Task 8 do plano de CI): `38`, `39`, `40` com `--habilitar`, `bekaa-trusted-advisors`; primeiro job real em repositório descartável.
4. Restos: sysbox, Continue, OpenRig, UFW 8080, `stack-rede-containers` (autorização explícita), imagem `stack/web` (decisão do dono).
5. Abertos: `ssh stack-cf`, `emergencia.esper.ws` (301), Linear (`43 linear` + timer), timers dos jobs parados, revogar o token que estava em `/srv/runners`.

## Fora de escopo

`@ness/auth`/SSO (opcional), restic/R2 (adiado pelo dono para a fase 4), roteamento de assinaturas pelo 9router (decidido contra).

## Testes

`stack-doctor` e `43-segredos-guiado.sh` com stubs (`STACK_TESTE=1`), no `tests/run.sh`. Segredos: o teste confere que nenhum valor aparece
em saída, argv ou log, e os modos dos arquivos. O runbook é revisado contra os scripts reais (nomes, flags, caminhos).
