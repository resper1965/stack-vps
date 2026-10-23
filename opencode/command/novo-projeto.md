---
description: Cria um projeto novo (agente, parecer ou sistema) a partir dos templates do stack-vps
---
<!-- stack-vps -->
Voce vai criar um projeto **novo**. Siga na ordem e pare em qualquer duvida.

1. Defina a pasta: `/srv/dev/projetos/<nome>`. Se ela ja existe e tem conteudo, e projeto existente: pare e avise. Nunca aplique o gerador a projeto existente.
2. Pergunte, em uma unica mensagem curta: natureza (`agente`, `parecer` ou `sistema`), nome (slug `[a-z0-9-]`) e destino(s) de implantacao (perfis de `standards/profiles.json`). Nao presuma destino.
3. Rode a previa, sem `--apply`, e mostre a saida inteira:
   `python3 /opt/stack-vps/scripts/42-novo-projeto.py /srv/dev/projetos/<nome> --natureza <natureza> --nome <nome> --destino <destino>`
   (repita `--destino` para mais de um).
4. So depois de um "sim" explicito, rode o mesmo comando com `--apply`.
5. Pergunte a parte se deve criar repositorio privado (`gh repo create --private`). Nunca presuma; sem "sim", nao crie.
6. Nao crie GitHub Actions, chaves, assinaturas nem deploy.
7. No fim, indique a pasta nova e o proximo passo que esta no `STATE.md` dela.
