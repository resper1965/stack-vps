#!/usr/bin/env bash
# Secrets compartilhados: um arquivo so para todos os projetos, carregado no shell do agente.
# Decisao do Ricardo em 30/09/2026: um arquivo para tudo, sem separar por vertical.
# Tokens de infraestrutura (GitHub, Cloudflare) ficam em secrets/admin.env, lidos so pelos scripts:
# nao entram no ambiente dos agentes.
# Roda COMO agente. Idempotente.
set -euo pipefail
[[ $(id -un) == agente ]] || { echo "rode como agente: sudo -u agente -H $0"; exit 1; }
P=/srv/dev/secrets/projetos.env

[[ -r $P ]] || { echo "sem $P legivel: rode 02-layout.sh (cria 640 dev:agente)"; exit 1; }

# no topo do .bashrc: o Ubuntu sai cedo em shell nao interativo, e o que fica embaixo nao roda.
# Le linha a linha em vez de dar source: valor com espaco funciona e nada do arquivo e executado.
if ! grep -q '^# >>> projetos.env' ~/.bashrc; then
  { cat <<'EOF'
# >>> projetos.env (27-secrets.sh)
if [ -r /srv/dev/secrets/projetos.env ]; then
  while IFS= read -r _l || [ -n "$_l" ]; do
    [[ $_l =~ ^[[:space:]]*(export[[:space:]]+)?([A-Za-z_][A-Za-z0-9_]*)=(.*)$ ]] || continue
    _k=${BASH_REMATCH[2]}; _v=${BASH_REMATCH[3]%$'\r'}
    if [[ $_v =~ ^\"(.*)\"$ ]] || [[ $_v =~ ^\'(.*)\'$ ]]; then _v=${BASH_REMATCH[1]}; fi
    export "$_k=$_v"
  done < /srv/dev/secrets/projetos.env
  unset _l _k _v
fi
# <<< projetos.env
EOF
    cat ~/.bashrc; } > ~/.bashrc.novo && mv ~/.bashrc.novo ~/.bashrc
fi

n=$(grep -cE '^[[:space:]]*(export[[:space:]]+)?[A-Za-z_][A-Za-z0-9_]*=' "$P" || true)
echo "projetos.env: $n chave(s) | carregado em shell novo (ou: source ~/.bashrc)"
