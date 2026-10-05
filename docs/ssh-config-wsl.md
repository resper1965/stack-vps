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

```text
Host stack
    HostName 100.76.167.6
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

O `HostName` é o IP da VPS na tailnet, não o nome: o Windows deste laptop não usa o DNS do
Tailscale (MagicDNS), então `stack` não resolve. O IP é fixo no painel do Tailscale (Edit machine
IPv4) e é reaplicado no nó novo quando a VPS é reinstalada.

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
`http://100.76.167.6:3000`. No Docker, publique só no loopback ou no IP da tailnet
(`-p 127.0.0.1:3000:3000`): porta publicada pelo Docker ignora o UFW.
