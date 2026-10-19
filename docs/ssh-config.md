# Acesso à VPS a partir do laptop

Dois caminhos para a mesma VPS: `stack` pela tailnet (principal) e `stack-cf` pelo Cloudflare
Tunnel (reserva). Se os dois caírem, o console do hPanel é a emergência. Nenhuma porta da VPS
responde no IP público.

Na tailnet, o OpenCode e o PMO abrem direto no navegador (`tailscale serve`, script 37):
`https://stack.<tailnet>.ts.net` para o OpenCode e `https://stack.<tailnet>.ts.net:8443` para o PMO.

O caminho principal é o **Windows**, não o WSL: em 05/10/2026 o WSL travou e deixou de responder,
e o acesso não deve depender dele.

**Qual conexão usar:** `stack-agente` é a estação de trabalho (você e os agentes, VS Code
Remote-SSH aqui). `stack` (usuário `dev`) é só para administração: sudo, `data/`, forense,
`admin.env`. Não abra repositórios pela `stack`.

## Pré-requisitos no Windows

- Tailscale instalado e logado na mesma tailnet.
- `cloudflared`, para o `stack-cf`: `winget install --id Cloudflare.cloudflared -e`.
- Chave `%USERPROFILE%\.ssh\id_ed25519_stackvps`.

## Blocos em `%USERPROFILE%\.ssh\config`

```text
Host stack
    HostName 100.76.167.6
    User dev
    IdentityFile ~/.ssh/id_ed25519_stackvps
    IdentitiesOnly yes
    StrictHostKeyChecking accept-new
    ServerAliveInterval 30
    ServerAliveCountMax 3

Host stack-agente
    HostName 100.76.167.6
    User agente
    IdentityFile ~/.ssh/id_ed25519_stackvps
    IdentitiesOnly yes
    StrictHostKeyChecking accept-new
    ServerAliveInterval 30
    ServerAliveCountMax 3

Host stack-cf
    HostName ssh.esper.ws
    User dev
    IdentityFile ~/.ssh/id_ed25519_stackvps
    IdentitiesOnly yes
    StrictHostKeyChecking accept-new
    ProxyCommand "C:\Program Files (x86)\cloudflared\cloudflared.exe" access ssh --hostname %h
    LocalForward 4096 127.0.0.1:4096
    LocalForward 8080 /run/pmo/pmo.sock
    ServerAliveInterval 30
    ServerAliveCountMax 3
```

O `HostName` de `stack` é o IP da VPS na tailnet, não o nome: o Windows deste laptop não usa o DNS
do Tailscale (MagicDNS), então `stack` não resolve. O IP é fixo no painel do Tailscale (Edit machine
IPv4) e é reaplicado no nó novo quando a VPS é reinstalada.

No WSL, os mesmos blocos servem no `~/.ssh/config` dele, trocando o `ProxyCommand` por
`cloudflared access ssh --hostname %h` (com o `cloudflared` instalado pelo apt).

Sem a tailnet não há `tailscale serve`, então o `stack-cf` leva o OpenCode em `http://localhost:4096` e o PMO
em `http://localhost:8080` por `LocalForward`. O PMO fica só leitura por aqui, porque esse caminho não traz o
cabeçalho de identidade da tailnet. `LocalForward` para socket Unix exige OpenSSH 6.7 ou mais novo no cliente;
no cliente OpenSSH do Windows, confirmar.

## Login do Access (só para `stack-cf`)

O token do Access vale 24h. Quando expirar, o `ssh stack-cf` abre o navegador sozinho no Windows.
Para renovar antes:

```powershell
& "C:\Program Files (x86)\cloudflared\cloudflared.exe" access login https://ssh.esper.ws
```

`ssh.esper.ws` é um CNAME *proxied* para o tunnel `stack-vps`, e a regra de redirecionamento
"esper.ws-> canonico" da zona exclui esse host (`http.host ne "ssh.esper.ws"`). Se alguém
voltar o registro para A ou a regra para `true`, o `stack-cf` para de funcionar.

## Portas de desenvolvimento

Com a tailnet, um serviço na porta 3000 da VPS abre no navegador do laptop em
`http://100.76.167.6:3000`. No Docker, publique só no loopback ou no IP da tailnet
(`-p 127.0.0.1:3000:3000`): porta publicada pelo Docker ignora o UFW.
