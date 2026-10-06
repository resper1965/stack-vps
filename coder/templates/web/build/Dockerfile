# Imagem do workspace "web": Node 24, Docker interno (sysbox), gh, e os tres agentes.
FROM ubuntu:24.04
ENV DEBIAN_FRONTEND=noninteractive LANG=C.UTF-8
RUN apt-get update && apt-get install -y --no-install-recommends \
      ca-certificates curl git sudo jq unzip ripgrep fd-find tmux build-essential python3 python3-venv \
      openssh-client gnupg iproute2 netcat-openbsd \
 && install -m 0755 -d /etc/apt/keyrings \
 && curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc \
 && echo "deb [arch=amd64 signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu noble stable" > /etc/apt/sources.list.d/docker.list \
 && curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg -o /etc/apt/keyrings/gh.gpg \
 && echo "deb [signed-by=/etc/apt/keyrings/gh.gpg] https://cli.github.com/packages stable main" > /etc/apt/sources.list.d/gh.list \
 && apt-get update && apt-get install -y --no-install-recommends docker-ce docker-ce-cli containerd.io \
      docker-compose-plugin docker-buildx-plugin gh \
 && rm -rf /var/lib/apt/lists/* \
 && ln -s "$(command -v fdfind)" /usr/local/bin/fd
# root no container nao e root no host (sysbox): sudo aqui e seguro
RUN useradd -m -s /bin/bash -G docker coder && echo 'coder ALL=(ALL) NOPASSWD:ALL' > /etc/sudoers.d/coder
USER coder
WORKDIR /home/coder
ENV PATH=/home/coder/.local/bin:/home/coder/.local/share/mise/shims:$PATH
RUN curl -fsSL https://mise.run | sh && ~/.local/bin/mise use -g node@24 \
 && echo 'eval "$(~/.local/bin/mise activate bash)"' >> ~/.bashrc \
 && npm i -g --allow-scripts=@anthropic-ai/claude-code @anthropic-ai/claude-code @openai/codex wrangler vercel supabase \
 && ~/.local/bin/mise reshim \
 && (curl -fsSL https://antigravity.google/cli/install.sh | bash) || true
