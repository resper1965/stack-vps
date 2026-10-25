---
description: Cria um projeto novo (agente, parecer ou sistema) a partir dos templates do stack-vps
---
<!-- stack-vps -->
Você vai criar um projeto **novo**. Este comando só vale para projeto novo: nunca o aplique a um projeto existente. Siga na ordem e pare em qualquer dúvida.

1. Pergunte, em uma única mensagem curta: natureza (`agente`, `parecer` ou `sistema`), nome (slug `[a-z0-9-]`) e destino(s) de implantação (perfis de `standards/profiles.json`). Não presuma destino.
2. A pasta do projeto é `<pasta>`: `/srv/dev/pareceres/<nome>` quando a natureza é `parecer` (o conteúdo do parecer fica fora do Git) e `/srv/dev/projetos/<nome>` nas demais. Verifique `<pasta>`. Se a pasta já existe e tem conteúdo, é projeto existente: pare e avise. Se a pasta-mãe (`/srv/dev/pareceres` ou `/srv/dev/projetos`) não existir, pare e peça ao dono que a crie com escrita para o `agente`.
3. Rode a prévia, sem `--apply`, e mostre a saída inteira:
   `python3 /opt/stack-vps/scripts/42-novo-projeto.py <pasta> --natureza <natureza> --nome <nome> --destino <destino>`
   (repita `--destino` para mais de um).
4. Só depois de um "sim" explícito, rode o mesmo comando com `--apply`.
5. Para `agente` e `sistema`, pergunte à parte se deve criar repositório privado (`gh repo create --private`). Nunca presuma; sem "sim", não crie. Para `parecer`, **nunca** ofereça nem rode `gh repo create`: o conteúdo do parecer não vai ao Git (só o template, que vive em `templates/parecer` no repositório stack-vps, é versionado).
6. Não crie GitHub Actions, chaves, assinaturas nem deploy.
7. No fim, informe o caminho da pasta nova, para o dono abrir a sessão do OpenCode nela, e o próximo passo que está no `STATE.md` dela.
