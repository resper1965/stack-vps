"""Servidor do painel: serve a pagina e o painel.json, e grava pedidos de acao na fila.

Nao executa nada: so valida e grava arquivos de pedido. Quem executa e o pmo.executor.
Classificar (empresa, area, cliente, tipo) grava na hora em classes.json, sem fila.
Roda como pmo. Recusa acao pedida de dentro da propria VPS. Aceita so o Host da tailnet (contra DNS
rebinding) e, no POST, exige JSON com o cabecalho X-PMO e Origin ausente ou propria (contra CSRF: forca preflight, que nao e respondido).
Uso: python3 -m pmo.servidor [--host 100.76.167.6] [--porta 8080]
"""
import argparse
import hashlib
import json
import os
import threading
import time
from http.server import ThreadingHTTPServer, SimpleHTTPRequestHandler
from urllib.parse import unquote, urlsplit

from pmo.executor import aplicar_ajustes
from pmo.pasta import NOME
from pmo.regras import EMPRESAS, TIPOS, aplicar_classes

ACOES = {"arquivar", "excluir", "restaurar", "trazer", "descartar", "clonar"}


def _ler_json(caminho, padrao):
    try:
        with open(caminho, encoding="utf-8") as f:
            return json.load(f)
    except (OSError, ValueError):
        return padrao


def _classe_valida(c):
    """Classe vinda do painel: empresa e tipo da lista; area e cliente texto curto de uma linha."""
    assert isinstance(c, dict) and set(c) <= {"empresa", "area", "cliente", "tipo"}
    assert (c.get("empresa") or "") in EMPRESAS + ("",) and (c.get("tipo") or "") in TIPOS + ("",)
    for k in ("area", "cliente"):
        v = c.get(k) or ""
        assert isinstance(v, str) and len(v) <= 60 and (not v or NOME.fullmatch(v))
    return {k: (c.get(k) or "").strip() for k in ("empresa", "area", "cliente", "tipo")}


def criar(host, porta, web, painel, fila, ajustes, bloquear_local=True, classes="/var/lib/pmo/classes.json"):
    os.makedirs(fila, mode=0o700, exist_ok=True)
    trava = threading.Lock()

    def ler_painel():
        with open(painel, encoding="utf-8") as f:
            d = json.load(f)
        return aplicar_classes(aplicar_ajustes(d, _ler_json(ajustes, {})), _ler_json(classes, {}))

    def classificar(alvo, classe):
        with trava:
            todas = _ler_json(classes, {})
            todas[alvo] = classe
            tmp = classes + ".tmp"
            with open(tmp, "w", encoding="utf-8") as f:
                json.dump(todas, f, ensure_ascii=False)
            os.replace(tmp, classes)

    class Handler(SimpleHTTPRequestHandler):
        def __init__(self, *a, **k):
            super().__init__(*a, directory=web, **k)

        def log_message(self, *a):
            pass

        def list_directory(self, path):
            self.send_error(404)

        def _caminho_seguro(self):
            p = unquote(urlsplit(self.path).path)
            return ".." not in p.split("/")

        def _proprio(self):
            return "%s:%d" % self.server.server_address[:2]

        def _host_ok(self):
            return self.headers.get("Host") == self._proprio()

        def do_GET(self):
            if not self._host_ok():
                return self.send_error(403)
            if not self._caminho_seguro():
                return self.send_error(404)
            if urlsplit(self.path).path == "/painel.json":
                try:
                    corpo = json.dumps(ler_painel(), ensure_ascii=False).encode()
                except (OSError, ValueError):
                    return self.send_error(503, "painel ainda nao gerado")
                self.send_response(200)
                self.send_header("Content-Type", "application/json; charset=utf-8")
                self.send_header("Cache-Control", "no-store")
                self.end_headers()
                return self.wfile.write(corpo)
            return super().do_GET()

        def do_POST(self):
            origem = self.headers.get("Origin")
            cliente = self.client_address[0]
            if bloquear_local and (cliente == self.server.server_address[0] or cliente.startswith("127.")):
                # pedido de dentro da VPS (agente, container) nunca vira acao; so o laptop pela tailnet
                return self._resposta(403, "recusado: pedido de dentro da VPS")
            if (not self._host_ok() or self.headers.get("X-PMO") != "1"
                    or (self.headers.get("Content-Type") or "").split(";")[0].strip() != "application/json"
                    or origem not in (None, "http://" + self._proprio())):
                return self._resposta(403, "recusado")
            if urlsplit(self.path).path != "/acao":
                return self.send_error(404)
            try:
                tam = min(int(self.headers.get("Content-Length") or 0), 4096)
                ped = json.loads(self.rfile.read(tam) or b"null")
                acao, alvo = ped["acao"], ped["alvo"]
                conf = ped.get("confirmacao")
                assert (acao in ACOES or acao == "classificar") and isinstance(alvo, str) and alvo.isprintable() and len(alvo) < 300
                assert conf is None or isinstance(conf, str) and len(conf) < 200
                d = ler_painel()
                if acao == "classificar":
                    assert alvo in {x["id"] for k in ("projetos", "arquivados") for x in d.get(k, [])}
                    classificar(alvo, _classe_valida(ped.get("classe")))
                    return self._resposta(200, "classificado")
                validos = {x["id"] for chave in ("projetos", "arquivados", "a_destinar") for x in d.get(chave, [])}
                assert alvo in validos
                destino = ped.get("pasta")
                assert acao != "clonar" or isinstance(destino, str) and NOME.fullmatch(destino)
            except Exception:  # noqa: BLE001 — qualquer pedido malformado e recusado igual
                return self._resposta(400, "pedido invalido")
            nome = f"{int(time.time() * 1000)}-{acao}-{hashlib.sha1(alvo.encode()).hexdigest()[:10]}.json"
            tmp = os.path.join(fila, "." + nome)
            with open(tmp, "w", encoding="utf-8") as f:
                json.dump({"acao": acao, "alvo": alvo, "confirmacao": conf, "pedido_em": time.time(),
                           **({"pasta": destino} if acao == "clonar" else {})}, f, ensure_ascii=False)
            os.replace(tmp, os.path.join(fila, nome))
            return self._resposta(202, "registrado")

        def _resposta(self, codigo, texto):
            self.send_response(codigo)
            self.send_header("Content-Type", "text/plain; charset=utf-8")
            self.end_headers()
            self.wfile.write(texto.encode())

    return ThreadingHTTPServer((host, porta), Handler)


def main():
    a = argparse.ArgumentParser()
    a.add_argument("--host", default="100.76.167.6")
    a.add_argument("--porta", type=int, default=8080)
    a.add_argument("--web", default=os.path.join(os.path.dirname(__file__), "web"))
    a.add_argument("--painel", default="/srv/dev/state/pmo/painel.json")
    a.add_argument("--fila", default="/var/lib/pmo/fila")
    a.add_argument("--ajustes", default="/var/lib/pmo/ajustes.json")
    a.add_argument("--classes", default="/var/lib/pmo/classes.json")
    o = a.parse_args()
    criar(o.host, o.porta, o.web, o.painel, o.fila, o.ajustes, classes=o.classes).serve_forever()


if __name__ == "__main__":
    main()
