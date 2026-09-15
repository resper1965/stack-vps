#!/usr/bin/env bash
# Cloudflare Tunnel + DNS + Zero Trust Access. Idempotente.
# Uso: sudo ./06-tunnel.sh <email-da-politica>
# Le CLOUDFLARE_API_TOKEN e CLOUDFLARE_ACCOUNT_ID de /srv/dev/secrets/.env — o token nao sai da VPS.
set -euo pipefail
[[ $EUID -eq 0 ]] || { echo "rode como root"; exit 1; }
EMAIL="${1:?informe o e-mail da politica de Access}"
ZONA=esper.ws
HOST=ssh.$ZONA

set -a; . /srv/dev/secrets/.env; set +a
AID="$CLOUDFLARE_ACCOUNT_ID"; H="Authorization: Bearer $CLOUDFLARE_API_TOKEN"
api(){ curl -s -H "$H" -H 'Content-Type: application/json' "$@"; }
jq_(){ python3 -c "import sys,json;d=json.load(sys.stdin);$1"; }

# 1. tunnel (reaproveita se ja existir; o secret so existe no momento da criacao)
TID=$(api "https://api.cloudflare.com/client/v4/accounts/$AID/cfd_tunnel?name=stack-vps&is_deleted=false" \
      | jq_ 'r=d.get("result") or [];print(r[0]["id"] if r else "")')
if [[ -z $TID ]]; then
  SECRET=$(head -c 32 /dev/urandom | base64 -w0)
  R=$(api -X POST "https://api.cloudflare.com/client/v4/accounts/$AID/cfd_tunnel" \
      -d "{\"name\":\"stack-vps\",\"config_src\":\"local\",\"tunnel_secret\":\"$SECRET\"}")
  [[ $(echo "$R" | jq_ 'print(d["success"])') == True ]] || { echo "ERRO ao criar tunnel: $(echo "$R" | jq_ 'print(d["errors"])')"; exit 1; }
  TID=$(echo "$R" | jq_ 'print(d["result"]["id"])')
  install -d -m 700 /etc/cloudflared
  (umask 077; printf '{"AccountTag":"%s","TunnelID":"%s","TunnelSecret":"%s"}' "$AID" "$TID" "$SECRET" > /etc/cloudflared/credentials.json)
fi
echo "tunnel: $TID"

# 2. ingress local — servico novo entra aqui, nunca como porta aberta
cat > /etc/cloudflared/config.yml <<YML
tunnel: $TID
credentials-file: /etc/cloudflared/credentials.json
ingress:
  - hostname: $HOST
    service: ssh://localhost:22
  - service: http_status:404
YML

# 3. DNS: CNAME proxied para o tunnel
ZID=$(api "https://api.cloudflare.com/client/v4/zones?name=$ZONA" | jq_ 'print((d["result"] or [{}])[0].get("id",""))')
REC=$(api "https://api.cloudflare.com/client/v4/zones/$ZID/dns_records?name=$HOST" | jq_ 'r=d.get("result") or [];print(r[0]["id"] if r else "")')
BODY="{\"type\":\"CNAME\",\"name\":\"$HOST\",\"content\":\"$TID.cfargotunnel.com\",\"proxied\":true}"
if [[ -n $REC ]]; then api -X PUT "https://api.cloudflare.com/client/v4/zones/$ZID/dns_records/$REC" -d "$BODY" >/dev/null
else api -X POST "https://api.cloudflare.com/client/v4/zones/$ZID/dns_records" -d "$BODY" >/dev/null; fi
echo "dns: $HOST -> $TID.cfargotunnel.com"

# 4. Access: aplicacao + politica de e-mail
APP=$(api "https://api.cloudflare.com/client/v4/accounts/$AID/access/apps" \
      | jq_ "r=[x for x in (d.get('result') or []) if x.get('domain')=='$HOST'];print(r[0]['id'] if r else '')")
APPBODY="{\"name\":\"SSH stack-vps\",\"domain\":\"$HOST\",\"type\":\"self_hosted\",\"session_duration\":\"24h\"}"
if [[ -z $APP ]]; then
  APP=$(api -X POST "https://api.cloudflare.com/client/v4/accounts/$AID/access/apps" -d "$APPBODY" | jq_ 'print(d["result"]["id"] if d["success"] else "")')
fi
POL=$(api "https://api.cloudflare.com/client/v4/accounts/$AID/access/apps/$APP/policies" \
      | jq_ "r=[x for x in (d.get('result') or []) if x['name']=='so-o-dono'];print(r[0]['id'] if r else '')")
POLBODY="{\"name\":\"so-o-dono\",\"decision\":\"allow\",\"include\":[{\"email\":{\"email\":\"$EMAIL\"}}]}"
if [[ -z $POL ]]; then api -X POST "https://api.cloudflare.com/client/v4/accounts/$AID/access/apps/$APP/policies" -d "$POLBODY" >/dev/null
else api -X PUT "https://api.cloudflare.com/client/v4/accounts/$AID/access/apps/$APP/policies/$POL" -d "$POLBODY" >/dev/null; fi
echo "access: $HOST liberado apenas para $EMAIL"

# 5. servico
cloudflared service install >/dev/null 2>&1 || true
systemctl enable --now cloudflared
sleep 3
systemctl is-active --quiet cloudflared && echo "cloudflared: ativo" || { journalctl -u cloudflared -n 20 --no-pager; exit 1; }

echo
echo "Valide o acesso pelo tunnel ANTES de fechar o UFW:"
echo "  ssh -o ProxyCommand='cloudflared access ssh --hostname $HOST' dev@$HOST"
