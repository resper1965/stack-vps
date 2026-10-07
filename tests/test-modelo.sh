#!/usr/bin/env bash
# shellcheck source=tests/lib.sh
. "$(dirname "$0")/lib.sh"
M=$RAIZ_REPO/bin/modelo
echo "modelo"
novo_tmp
# API falsa compativel com OpenAI: devolve o modelo, a chave e o texto recebidos
cat > "$T/api.py" <<'PY'
import json, sys
from http.server import BaseHTTPRequestHandler, HTTPServer
class H(BaseHTTPRequestHandler):
    def log_message(self, *a): pass
    def do_POST(self):
        d = json.loads(self.rfile.read(int(self.headers["Content-Length"])))
        r = f'{self.path}|{d["model"]}|{self.headers["Authorization"]}|{d["messages"][-1]["content"]}'
        b = json.dumps({"choices": [{"message": {"content": r}}]}).encode()
        self.send_response(200); self.send_header("Content-Type", "application/json"); self.end_headers(); self.wfile.write(b)
s = HTTPServer(("127.0.0.1", 0), H); print(s.server_address[1], flush=True); s.serve_forever()
PY
python3 "$T/api.py" > "$T/porta" & API=$!
for _ in $(seq 50); do [[ -s $T/porta ]] && break; sleep 0.1; done
P=$(cat "$T/porta")
printf 'apelido\tprovedor\tmodelo\tuso\nrapido\topenrouter\tdeepseek/deepseek-chat\tdia a dia\nrabbit\tfeatherless\tWhiteRabbitNeo/X-7B\tpentest\n' > "$T/modelos.tsv"
printf 'OPENROUTER_API_KEY=chave-or\nFEATHERLESS_API_KEY=chave-fl\n' > "$T/agente.env"
export MODELOS_TSV=$T/modelos.tsv MODELOS_ENV=$T/agente.env \
  MODELO_BASE_OPENROUTER=http://127.0.0.1:$P/or MODELO_BASE_FEATHERLESS=http://127.0.0.1:$P/fl
unset OPENROUTER_API_KEY FEATHERLESS_API_KEY

r=$(python3 "$M" rapido "ola" </dev/null)
[[ $r == "/or/chat/completions|deepseek/deepseek-chat|Bearer chave-or|ola" ]]; afirma $? "openrouter: modelo, chave do agente.env e pergunta"
r=$(echo "nmap 80/tcp open" | python3 "$M" rabbit "analise")
[[ $r == *"/fl/chat/completions|WhiteRabbitNeo/X-7B|Bearer chave-fl|analise"* && $r == *"nmap 80/tcp open"* ]]; afirma $? "featherless: entrada do pipe vai junto da pergunta"
r=$(FEATHERLESS_API_KEY=do-ambiente python3 "$M" rabbit "x" </dev/null)
[[ $r == *"Bearer do-ambiente"* ]]; afirma $? "chave do ambiente vence a do arquivo"
python3 "$M" -l | grep -q "rabbit.*featherless.*pentest"; afirma $? "-l lista os apelidos"
python3 "$M" inexistente "x" </dev/null >/dev/null 2>&1; afirma_rc $? 2 "apelido desconhecido sai com 2"
c=$(python3 "$M" --continue)
grep -q 'model: WhiteRabbitNeo/X-7B' <<< "$c" && grep -q 'apiBase: https://api.featherless.ai/v1' <<< "$c" \
  && grep -q 'apiKey: ${{ secrets.FEATHERLESS_API_KEY }}' <<< "$c"; afirma $? "config do Continue com provedor e chave por referencia"
nega=$(grep -c 'chave-' <<< "$c"); afirma_rc "$nega" 0 "config do Continue nao contem chave"
kill "$API" 2>/dev/null
fim
