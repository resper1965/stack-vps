#!/usr/bin/env bash
# OpenRig (github.com/mvschwarz/openrig): dupla principal (Claude) + revisor (Codex) em tmux.
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

# Spec propria, copiada da embutida a cada execucao (acompanha a versao instalada).
# Tira dos perfis os fragmentos que setam acceptEdits e ligam Exa/Context7;
# mantem so o hook de atividade, que alimenta o painel do rig.
S=$H/specs
rm -rf "$S"; mkdir -p "$S/agents/development" "$S/rigs/dupla"
cp -r "$PKG/daemon/specs/agents/shared" "$S/agents/"
cp -r "$PKG/daemon/specs/agents/development/implementer" "$PKG/daemon/specs/agents/development/qa" "$S/agents/development/"
for a in implementer qa; do
  f="$S/agents/development/$a/agent.yaml"
  sed -i 's/^\( *runtime_resources:\).*/\1 [shared:claude-activity-hooks]/' "$f"
  grep -q 'runtime_resources: \[shared:claude-activity-hooks\]$' "$f" || { echo "formato de $f mudou; revise o sed"; exit 1; }
done
cp "$PKG/daemon/specs/rigs/launch/first-project/CULTURE.md" "$S/rigs/dupla/"
cat > "$S/rigs/dupla/rig.yaml" <<'EOF'
version: "0.2"
name: dupla
summary: >
  Agente principal (Claude Code) e agente revisor (Codex) no mesmo repositorio,
  conforme a secao 3 do CLAUDE.md. O revisor nunca faz merge.
culture_file: CULTURE.md

pods:
  - id: dev
    label: Projeto
    members:
      - id: principal
        agent_ref: "local:../../agents/development/implementer"
        runtime: claude-code
        profile: default
        cwd: "."
      - id: revisor
        agent_ref: "local:../../agents/development/qa"
        runtime: codex
        profile: default
        cwd: "."
    edges:
      - kind: delegates_to
        from: principal
        to: revisor

edges: []
EOF

echo "openrig: $(rig --version) | home: $H | spec: $S/rigs/dupla/rig.yaml"
echo "subir num projeto (nunca em main/master):"
echo "  cd /srv/dev/repos/<arvore>/<projeto> && git switch -c chore/<tarefa>"
echo "  rig up $S/rigs/dupla/rig.yaml --cwd . --plan   # revisar, depois sem --plan"
echo "  rig tui --shared"
