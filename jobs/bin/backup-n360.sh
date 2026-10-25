#!/usr/bin/env bash
# Backup do banco do n.360-alternative: pg_dump (formato custom) -> openssl (aes-256-cbc, pbkdf2) direto em pipe,
# sem texto claro em disco -> /srv/dev/backups/n360-alt/AAAA-MM-DD.dump.enc (0600, pasta 0700). Valida cada dump
# (descriptografa em pipe + pg_restore -l); segunda-feira confere tambem o tamanho minimo. Retencao: 14 dumps.
# Segredos so do ambiente: DATABASE_URL e BACKUP_PASSPHRASE. A URL vira um arquivo de servico do libpq (0600,
# PGSERVICEFILE) para nao aparecer em argv; a passphrase vai por "-pass env:". Nada disso e impresso.
# Nao restaura em Postgres efemero (validacao estrutural apenas) e NAO ha copia fora da VPS (restic/R2 adiado).
# Uso: backup-n360.sh
# rc 0 ok | 1 dump/validacao/tamanho falhou | 2 pre-requisito ausente.
# Sobrescreviveis nos testes (so com STACK_TESTE=1): BACKUP_DIR BACKUP_HOJE (AAAA-MM-DD) BACKUP_DIA_SEMANA (1=segunda).
set -uo pipefail
umask 077
DIR=/srv/dev/backups/n360-alt; HOJE=$(date -u +%F); DIA=$(date -u +%u)
if [[ ${STACK_TESTE:-} == 1 ]]; then DIR=${BACKUP_DIR:-$DIR}; HOJE=${BACKUP_HOJE:-$HOJE}; DIA=${BACKUP_DIA_SEMANA:-$DIA}; fi
MIN_BYTES=${BACKUP_MIN_BYTES:-20480}
RETENCAO=14
AVISO="sem copia fora da VPS (restic/R2 adiado)"

[[ -n ${DATABASE_URL:-} && -n ${BACKUP_PASSPHRASE:-} ]] || { echo "backup n360-alt: faltam DATABASE_URL/BACKUP_PASSPHRASE no ambiente (43-segredos-guiado.sh job n360-alt-backup)"; exit 2; }
for t in pg_dump pg_restore openssl python3; do command -v "$t" >/dev/null 2>&1 || { echo "backup n360-alt: falta $t"; exit 2; }; done
[[ $HOJE =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]] || { echo "backup n360-alt: data invalida"; exit 2; }
install -d -m 700 "$DIR" || { echo "backup n360-alt: nao criei $DIR"; exit 2; }
chmod 700 "$DIR"

tmp=$(mktemp -d "$DIR/.tmp.XXXXXX") || { echo "backup n360-alt: sem espaco/permissao em $DIR"; exit 2; }
trap 'rm -rf "$tmp"' EXIT

# URL -> arquivo de servico (chaves host/port/user/password/dbname/sslmode); a URL nao passa por argv
python3 -I -c '
import sys, os
from urllib.parse import urlsplit, unquote, parse_qsl
u = urlsplit(os.environ["DATABASE_URL"])
if u.scheme not in ("postgres", "postgresql") or not u.hostname: sys.exit(1)
c = {"host": u.hostname, "port": u.port or 5432, "user": unquote(u.username or ""), "password": unquote(u.password or ""),
     "dbname": unquote(u.path.lstrip("/")) or "postgres", "sslmode": "require"}
for k, v in parse_qsl(u.query):
    if k in ("sslmode", "connect_timeout", "sslrootcert"): c[k] = v
bad = [k for k, v in c.items() if "\n" in str(v) or "\r" in str(v)]
if bad: sys.exit(1)
with open(sys.argv[1], "w") as f:
    f.write("[n360]\n" + "".join("%s=%s\n" % kv for kv in c.items()))
' "$tmp/pg_service.conf" 2>/dev/null || { echo "backup n360-alt: DATABASE_URL invalida (esperado postgres://usuario:senha@host:porta/banco)"; exit 2; }
export PGSERVICEFILE=$tmp/pg_service.conf PGSERVICE=n360
unset DATABASE_URL

alvo=$DIR/$HOJE.dump.enc
parcial=$tmp/dump.enc
pg_dump -Fc --no-password 2>"$tmp/pg_dump.err" | openssl enc -aes-256-cbc -pbkdf2 -iter 600000 -salt -pass env:BACKUP_PASSPHRASE -out "$parcial"
rcs=("${PIPESTATUS[@]}")
if (( rcs[0] != 0 || rcs[1] != 0 )); then
  # o stderr do pg_dump nao e repetido (pode citar host/usuario); so o codigo
  echo "backup n360-alt: FALHOU o dump/criptografia (pg_dump rc=${rcs[0]}, openssl rc=${rcs[1]}); backups anteriores mantidos"; exit 1
fi

# validacao estrutural: descriptografa em pipe (sem claro em disco) e lista o sumario do dump
if ! openssl enc -d -aes-256-cbc -pbkdf2 -iter 600000 -pass env:BACKUP_PASSPHRASE -in "$parcial" 2>/dev/null | pg_restore -l >/dev/null 2>&1; then
  echo "backup n360-alt: FALHOU a validacao (pg_restore -l nao leu o dump); dump descartado, anteriores mantidos"; exit 1
fi
tam=$(stat -c %s "$parcial")
if [[ $DIA == 1 ]] && (( tam < MIN_BYTES )); then
  echo "backup n360-alt: FALHOU a checagem semanal de tamanho ($tam bytes < minimo $MIN_BYTES); dump descartado"; exit 1
fi
chmod 600 "$parcial"
mv -f "$parcial" "$alvo"

# retencao: mantem os $RETENCAO mais novos (o nome AAAA-MM-DD ordena por data)
mapfile -t todos < <(find "$DIR" -maxdepth 1 -type f -name '????-??-??.dump.enc' -printf '%f\n' | sort)
if (( ${#todos[@]} > RETENCAO )); then
  for f in "${todos[@]:0:${#todos[@]}-RETENCAO}"; do rm -f -- "$DIR/$f"; done
  mapfile -t todos < <(find "$DIR" -maxdepth 1 -type f -name '????-??-??.dump.enc' -printf '%f\n' | sort)
fi
velho=${todos[0]%.dump.enc}
idade=$(( ( $(date -u -d "$HOJE" +%s) - $(date -u -d "$velho" +%s) ) / 86400 ))
echo "backup n360-alt ok: $HOJE.dump.enc $tam bytes, ${#todos[@]} dumps, mais antigo $velho ($idade dias); $AVISO"
