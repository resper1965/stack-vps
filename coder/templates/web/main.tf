# Modelo "web": apps Node/Next/Workers/Supabase. Container sysbox (Docker interno sem modo
# privilegiado), sem acesso ao docker.sock do host, limite de memoria, desliga ocioso.
terraform {
  required_providers {
    coder  = { source = "coder/coder" }
    docker = { source = "kreuzwerker/docker" }
  }
}

provider "docker" {}

data "coder_provisioner" "me" {}
data "coder_workspace" "me" {}
data "coder_workspace_owner" "me" {}

resource "coder_agent" "main" {
  arch = data.coder_provisioner.me.arch
  os   = "linux"
  # logins dos agentes moram num volume por pessoa: login uma vez, vale para todos os workspaces dela
  startup_script = <<-EOT
    set -e
    for d in claude claude-ionic codex gemini; do
      mkdir -p "$HOME/.persist/$d"
      [ -L "$HOME/.$d" ] || { rm -rf "$HOME/.$d"; ln -s "$HOME/.persist/$d" "$HOME/.$d"; }
    done
    sudo sh -c 'nohup dockerd >/tmp/dockerd.log 2>&1 &'
  EOT
  env = {
    GIT_AUTHOR_NAME     = coalesce(data.coder_workspace_owner.me.full_name, data.coder_workspace_owner.me.name)
    GIT_AUTHOR_EMAIL    = data.coder_workspace_owner.me.email
    GIT_COMMITTER_NAME  = coalesce(data.coder_workspace_owner.me.full_name, data.coder_workspace_owner.me.name)
    GIT_COMMITTER_EMAIL = data.coder_workspace_owner.me.email
  }
}

module "code-server" {
  count    = data.coder_workspace.me.start_count
  source   = "registry.coder.com/coder/code-server/coder"
  version  = "~> 1.0"
  agent_id = coder_agent.main.id
  order    = 1
}

resource "docker_volume" "home" {
  name = "coder-${data.coder_workspace.me.id}-home"
  lifecycle { ignore_changes = all }
}

resource "docker_volume" "agentes" {
  name = "coder-${data.coder_workspace_owner.me.id}-agentes"
  lifecycle { ignore_changes = all }
}

resource "docker_image" "web" {
  name = "stack/web:${substr(sha1(file("${path.module}/build/Dockerfile")), 0, 12)}"
  build {
    context = "${path.module}/build"
  }
  keep_locally = true
}

resource "docker_container" "workspace" {
  count      = data.coder_workspace.me.start_count
  image      = docker_image.web.image_id
  name       = "coder-${data.coder_workspace_owner.me.name}-${lower(data.coder_workspace.me.name)}"
  hostname   = data.coder_workspace.me.name
  runtime    = "sysbox-runc"
  memory     = 6144
  cpu_shares = 1024
  entrypoint = ["sh", "-c", coder_agent.main.init_script]
  env        = ["CODER_AGENT_TOKEN=${coder_agent.main.token}"]
  volumes {
    container_path = "/home/coder"
    volume_name    = docker_volume.home.name
  }
  volumes {
    container_path = "/home/coder/.persist"
    volume_name    = docker_volume.agentes.name
  }
}
