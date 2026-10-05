# Ambiente do restic: .env da VPS ou, na VPS recem-formatada, o que ja estiver exportado.
# Fonte: . scripts/lib/restic-env.sh   (STACK_ROOT so existe nos testes)
# shellcheck shell=bash disable=SC2034  # BACKUP_* usados por 14 e 15
R=${STACK_ROOT:-}
ENVF=${STACK_ENV:-$R/srv/dev/secrets/admin.env}
if [[ -s $ENVF ]]; then
  set -a
  # shellcheck source=/dev/null
  . "$ENVF"
  set +a
fi

: "${CLOUDFLARE_ACCOUNT_ID:?falta CLOUDFLARE_ACCOUNT_ID}"
: "${R2_ACCESS_KEY_ID:?falta R2_ACCESS_KEY_ID}"
: "${R2_SECRET_ACCESS_KEY:?falta R2_SECRET_ACCESS_KEY}"
: "${RESTIC_PASSWORD:?falta RESTIC_PASSWORD}"

export RESTIC_REPOSITORY="s3:https://${CLOUDFLARE_ACCOUNT_ID}.r2.cloudflarestorage.com/stack-vps-backup"
export AWS_ACCESS_KEY_ID=$R2_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY=$R2_SECRET_ACCESS_KEY
export AWS_DEFAULT_REGION=auto RESTIC_PASSWORD

# Repositorios ficam de fora: a verdade e o GitHub. Identidade do Tailscale tambem: o no novo
# entra antes do restore. Plugins do Claude sao reinstalados pelo 04.
BACKUP_PATHS=("$R/srv/dev/state" "$R/srv/dev/data" "$R/srv/dev/secrets/admin.env"
              "$R/etc/cloudflared/credentials.json" "$R/home/dev/.claude" "$R/home/dev/.codex")
BACKUP_EXCLUDES=("$R/home/dev/.claude/.credentials.json" "$R/home/dev/.codex/auth.json"
                 "$R/home/dev/.claude/plugins" "node_modules")
