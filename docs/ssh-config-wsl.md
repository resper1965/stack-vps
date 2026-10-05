# ~/.ssh/config na máquina local (dentro do WSL)

Dois caminhos para a mesma VPS: `stack` pela tailnet (principal) e `stack-cf` pelo Cloudflare
Tunnel (reserva). Se os dois caírem, o console do hPanel é a emergência.

## Pré-requisitos

- Tailscale no Windows, logado na mesma tailnet. O WSL usa a rede do Windows.
- Para o `stack-cf`, o `cloudflared` dentro do WSL:

```sh
curl -fsSL https://pkg.cloudflare.com/cloudflare-main.gpg | sudo tee /usr/share/keyrings/cloudflare-main.gpg >/dev/null
echo 'deb [signed-by=/usr/share/keyrings/cloudflare-main.gpg] https://pkg.cloudflare.com/cloudflared any main' | sudo tee /etc/apt/sources.list.d/cloudflared.list
sudo apt update && sudo apt install -y cloudflared
```

## Blocos

```
Host stack
    HostName stack
    User dev
    IdentityFile ~/.ssh/id_ed25519_stackvps
    IdentitiesOnly yes
    ServerAliveInterval 30
    ServerAliveCountMax 3

Host stack-cf
    HostName ssh.esper.ws
    User dev
    IdentityFile ~/.ssh/id_ed25519_stackvps
    IdentitiesOnly yes
    ProxyCommand cloudflared access ssh --hostname %h
    ServerAliveInterval 30
    ServerAliveCountMax 3
```

Se `ssh stack` disser que não resolve o nome, o WSL está em modo NAT e o MagicDNS não chega
nele. Troque `HostName stack` pelo IP `100.x` que aparece em `tailscale status` no Windows.

## Login do Access (só para `stack-cf`)

O WSL não abre navegador sozinho. Antes do primeiro `ssh stack-cf`, rode:

```sh
cloudflared access login https://ssh.esper.ws
```

Ele imprime uma URL: abra no navegador do Windows, autentique, e o token vale 24h.
Sem esse passo o `ssh stack-cf` fica parado esperando, sem mensagem.

## VS Code

Remote-SSH apontando para `stack`. Com a extensão WSL ativa, o VS Code do Windows usa este mesmo
perfil — não duplique a configuração no `%USERPROFILE%\.ssh\config`.

## Portas de desenvolvimento

Com a tailnet, um serviço na porta 3000 da VPS abre no navegador do laptop em
`http://stack:3000`. No Docker, publique só no loopback ou no IP da tailnet
(`-p 127.0.0.1:3000:3000`): porta publicada pelo Docker ignora o UFW.
