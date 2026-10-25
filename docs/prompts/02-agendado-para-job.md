# Prompt 02: transformar um workflow agendado em job da VPS

**Quando usar:** depois do prompt 01 (passo 4), para cada workflow com `schedule` que você quer rodar na VPS em vez do GitHub Actions.
**Onde colar:** OpenCode ou Claude Code, com a sessão aberta **dentro da pasta de UM projeto** (um workflow agendado por vez, ou um projeto por vez).
**O que ele faz:** só lê o workflow e produz a **definição** do job. Não toca no projeto, não habilita nada, não cria segredo.

---

```
Você vai descrever, para a VPS da stack, o(s) workflow(s) agendado(s) DESTE projeto como "job agendado". Só leitura: entregue texto e arquivos propostos, nada aplicado.
Regras que valem o tempo todo:
- Não altere NENHUM arquivo deste projeto, não abra PR nem issue, não faça push, não habilite workflow, não crie segredo.
- Nunca imprima valor de segredo; cite apenas NOMES de secrets.* e vars.*.
- Não mexa em outros repositórios. A proposta é para o repositório stack-vps (pasta jobs/), que você NÃO edita agora.
- O job só LÊ o projeto (clone raso, somente leitura, apagado ao final). Se o workflow escreve no repositório (commit, issue, release, comentário), diga isso e proponha trocar por arquivo de resultado e alerta.

PASSO 1: leitura
Para cada .github/workflows/*.yml com gatilho schedule: o cron (lembre: o GitHub usa UTC), os passos, as ferramentas e versões, os NOMES de segredos e variáveis, o que o workflow grava e onde, o tempo máximo e os recursos (RAM, rede, Docker). Diga se depende de algo que só existe no GitHub (Code scanning, artefatos, issues, GITHUB_TOKEN, dependency-review, service containers).

PASSO 2: a definição do job (formato de jobs/README.md do stack-vps)
Entregue o arquivo jobs/<nome>.job, com nome em [a-z0-9-]+, exatamente neste formato (CHAVE=valor, sem aspas, sem $, sem crase):
  DESCRICAO=...            texto curto, sem $ ` \ %
  AGENDA=...               OnCalendar do systemd, em UTC (ex.: Mon *-*-* 06:00:00 UTC)
  COMANDO=jobs/bin/<script> [argumentos fixos]
  TIMEOUT_MIN=...          de 1 a 1440
  REPO=dono/nome           deste projeto (git remote get-url origin)
  SEGREDOS=<nome-do-arquivo>   só se precisar de segredo
  CHAVES=NOME1,NOME2?      nomes das variáveis desse arquivo; o sufixo ? marca a opcional
  HABILITADO=nao           SEMPRE nao
Se já existir um script em jobs/bin/ do stack-vps que resolve (varredura.sh, dnscheck.sh, backup-n360.sh), reaproveite e diga qual. Se não existir, escreva a proposta do script jobs/bin/<nome>.sh: bash, set -uo pipefail, roda dentro do clone (diretório atual), usa só as variáveis de ambiente dos segredos, imprime no máximo uma linha de resumo (contagens, nunca conteúdo sensível), e sai com 0 (ok), 1 (achado/falha do alvo) ou 2 (erro de execução). Sem sudo, sem escrever dentro do clone além de pastas temporárias.

PASSO 3: segredos
Liste só os NOMES (os mesmos de CHAVES), o que cada um acessa e o escopo mínimo que o token precisa (ex.: token Cloudflare somente de leitura de DNS). Diga quais são opcionais. Não peça valores.

PASSO 4: riscos
Liste o que muda em relação ao workflow original (cobertura perdida, ferramenta trocada, falha silenciosa, consumo de RAM, tráfego contra produção, dados sensíveis gravados em /srv/dev/state/jobs) e o que depende de decisão minha.

PASSO 5: entrega
Termine com: (a) o conteúdo de jobs/<nome>.job; (b) o script de jobs/bin, se novo; (c) a lista de NOMES de segredos; (d) os riscos; (e) o que fazer com o workflow original (continuar desligado; ele só será apagado quando eu mandar). Pergunte: "Quer que eu prepare isto como PR no stack-vps?". Só depois do meu "sim".
```

---

## Depois de rodar: como você liga o job

1. O PR com `jobs/<nome>.job` (e o script, se novo) entra no stack-vps. O job nasce com `HABILITADO=nao`.
2. Se o job tem segredos, no servidor, como `dev`: `/opt/stack-vps/scripts/43-segredos-guiado.sh job <nome>` (pede cada valor oculto; grava `/srv/dev/secrets/jobs/<arquivo>.env`).
3. Teste à mão, como agente: `sudo -u agente /opt/stack-vps/bin/stack-job <nome>` e leia `/srv/dev/state/jobs/<nome>.json` e `.log`.
4. Num PR no stack-vps, troque para `HABILITADO=sim` no `.job`.
5. Depois do merge e do deploy: `sudo /opt/stack-vps/scripts/45-jobs.sh` (instala o timer). Confira com `stack-doctor`.

O passo a passo completo, com rollback, está em `docs/runbooks/2026-10-jobs-agendados.md`.
