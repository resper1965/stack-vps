# ~/.ssh/config na maquina local (dentro do WSL)

Pre-requisito no WSL:

```sh
curl -fsSL https://pkg.cloudflare.com/cloudflare-main.gpg | sudo tee /usr/share/keyrings/cloudflare-main.gpg >/dev/null
echo 'deb [signed-by=/usr/share/keyrings/cloudflare-main.gpg] https://pkg.cloudflare.com/cloudflared any main' | sudo tee /etc/apt/sources.list.d/cloudflared.list
sudo apt update && sudo apt install -y cloudflared
```

Depois acrescente ao `~/.ssh/config` **do WSL** (nao do PowerShell):

```
Host stack
    HostName ssh.esper.ws
    User dev
    IdentityFile ~/.ssh/id_ed25519_stackvps
    IdentitiesOnly yes
    ProxyCommand cloudflared access ssh --hostname %h
    ServerAliveInterval 30
    ServerAliveCountMax 3
```

Uso: `ssh stack`. Na primeira conexao o cloudflared abre o navegador para o Zero Trust Access.

VS Code: Remote-SSH apontando para o host `stack`. Com a extensao WSL ativa, o VS Code do Windows
usa este mesmo perfil — nao duplique a configuracao no `%USERPROFILE%\.ssh\config`.

Enquanto o tunnel nao existe, o acesso e direto por IP (`ssh -i ~/.ssh/id_ed25519_stackvps dev@148.230.77.242`).
Esse caminho morre quando o UFW fechar — de proposito.
