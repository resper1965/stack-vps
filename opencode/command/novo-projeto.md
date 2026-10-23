---
description: Cria um projeto novo (agente, parecer ou sistema) a partir dos templates do stack-vps
---
<!-- stack-vps -->
Você vai criar um projeto **novo**. Este comando só vale para projeto novo: nunca o aplique a um projeto existente. Siga na ordem e pare em qualquer dúvida.

1. Pergunte, em uma única mensagem curta: natureza (`agente`, `parecer` ou `sistema`), nome (slug `[a-z0-9-]`) e destino(s) de implantação (perfis de `standards/profiles.json`). Não presuma destino.
2. Verifique `/srv/dev/projetos/<nome>`. Se a pasta já existe e tem conteúdo, é projeto existente: pare e avise.
3. Rode a prévia, sem `--apply`, e mostre a saída inteira:
   `python3 /opt/stack-vps/scripts/42-novo-projeto.py /srv/dev/projetos/<nome> --natureza <natureza> --nome <nome> --destino <destino>`
   (repita `--destino` para mais de um).
4. Só depois de um "sim" explícito, rode o mesmo comando com `--apply`.
5. Pergunte à parte se deve criar repositório privado (`gh repo create --private`). Nunca presuma; sem "sim", não crie.
6. Não crie GitHub Actions, chaves, assinaturas nem deploy.
7. No fim, informe o caminho da pasta nova, para o dono abrir a sessão do OpenCode nela, e o próximo passo que está no `STATE.md` dela.
