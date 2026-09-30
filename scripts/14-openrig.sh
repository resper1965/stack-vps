#!/usr/bin/env bash
# OpenRig (github.com/mvschwarz/openrig): dupla principal + revisor em tmux, papeis do STATE.md.
# Roda COMO dev, depois do 04-agents.sh. Idempotente. Uso: ./14-openrig.sh [versao]
# Nao sobe equipe nenhuma: so instala, configura e gera a spec. Subir e manual (ver fim).
set -euo pipefail
[[ $(id -un) == dev ]] || { echo "rode como dev"; exit 1; }
export PATH="$HOME/.local/bin:$HOME/.local/share/mise/shims:$PATH"
VER=${1:-latest}

# OpenRig so suporta Node 22 e 24; node@lts vira 26 em out/2026 e quebra o better-sqlite3
case $(node -p 'process.versions.node.split(".")[0]') in
  22|24) ;; *) echo "node $(node --version) nao suportado; rode 03-tooling.sh (fixa node@24)"; exit 1;;
esac

# npm 11 bloqueia postinstall; o do cli checa ABI e o better-sqlite3 baixa o binario nativo
npm i -g --allow-scripts=@openrig/cli,better-sqlite3 "@openrig/cli@$VER" >/dev/null
mise reshim
PKG="$(npm root -g)/@openrig/cli"
node "$PKG/scripts/check-abi.mjs" >/dev/null

# Estado da instancia fica em /srv/dev/state, junto do resto que os agentes escrevem.
# Kernel desligado: ele sobe agentes proprios com a config padrao (acceptEdits, MCP externo).
# Hooks do Codex desligados: o daemon nao reescreve ~/.codex/config.toml curado pelo 04.
H=/srv/dev/state/openrig
mkdir -p "$H/shared-docs"
grep -q 'OPENRIG_HOME' ~/.bashrc || cat >> ~/.bashrc <<EOF
export OPENRIG_HOME=$H
export OPENRIG_SHARED_DOCS_ROOT=$H/shared-docs
export OPENRIG_NO_KERNEL=1
export OPENRIG_RUNTIME_CODEX_HOOKS_ENABLED=false
EOF
export OPENRIG_HOME=$H OPENRIG_SHARED_DOCS_ROOT=$H/shared-docs OPENRIG_NO_KERNEL=1 OPENRIG_RUNTIME_CODEX_HOOKS_ENABLED=false

# Agentes proprios, copiados dos embutidos a cada execucao (acompanham a versao instalada).
# Tira dos perfis os fragmentos que setam acceptEdits e ligam Exa/Context7;
# mantem so o hook de atividade, que alimenta o painel do rig.
# O papel de cada um ganha as regras do ambiente (openrig/principal.md e revisor.md).
R=$(cd "$(dirname "$0")/.." && pwd)
S=$H/specs
rm -rf "$S/agents"; mkdir -p "$S/agents/development" "$S/rigs"
cp -r "$PKG/daemon/specs/agents/shared" "$S/agents/"
cp -r "$PKG/daemon/specs/agents/development/implementer" "$PKG/daemon/specs/agents/development/qa" "$S/agents/development/"
for par in implementer:principal qa:revisor; do
  a=${par%%:*}; f="$S/agents/development/$a/agent.yaml"
  sed -i 's/^\( *runtime_resources:\).*/\1 [shared:claude-activity-hooks]/' "$f"
  grep -q 'runtime_resources: \[shared:claude-activity-hooks\]$' "$f" || { echo "formato de $f mudou; revise o sed"; exit 1; }
  cat "$R/openrig/${par##*:}.md" >> "$S/agents/development/$a/guidance/role.md"
done
cp "$PKG/daemon/specs/rigs/launch/first-project/CULTURE.md" "$S/"

# Cada projeto ganha seu rig na hora de subir, com os papeis do STATE.md
install -m 755 "$R/bin/rig-dupla" /srv/dev/bin/rig-dupla
ln -sfn /srv/dev/bin/rig-dupla ~/.local/bin/rig-dupla

echo "openrig: $(rig --version) | home: $H"
echo "subir num projeto (STATE.md com principal/revisor definidos, nunca em main/master):"
echo "  cd /srv/dev/repos/<arvore>/<projeto> && git switch -c chore/<tarefa>"
echo "  rig-dupla --plan   # revisar, depois sem --plan"
echo "  rig tui --shared"
