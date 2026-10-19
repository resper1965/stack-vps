"""Servidor do painel: serve a pagina e o painel.json, e grava pedidos de acao na fila.

Nao executa nada: so valida e grava arquivos de pedido. Quem executa e o pmo.executor.
Classificar (empresa, area, cliente, tipo) grava na hora em classes.json, sem fila.
Roda como pmo. Aceita so o Host da lista (contra DNS rebinding) e, no POST, exige JSON com o cabecalho X-PMO e
Origin ausente ou propria (contra CSRF: forca preflight, que nao e respondido).
Modo socket (producao): escuta em socket Unix e o tailscale serve faz proxy; o POST exige o cabecalho
Tailscale-User-Login com login da lista. O socket NAO autentica: quem o abre forja o cabecalho, entao a
fronteira e o diretorio/grupo pmo (o agente fica fora). Modo TCP (legado/testes): recusa pedido do IP local.
Uso: python3 -m pmo.servidor --socket /run/pmo/pmo.sock --hosts h1,h2 --logins a@b.c
     python3 -m pmo.servidor [--host 100.76.167.6] [--porta 8080]
"""
import argparse
import hashlib
import json
import os
import socketserver
import stat
import threading
import time
from datetime import datetime, timezone
from http.server import ThreadingHTTPServer, SimpleHTTPRequestHandler
from urllib.parse import unquote, urlsplit

from pmo.executor import aplicar_ajustes
from pmo.painel import ler_saude
from pmo.pasta import NOME
from pmo.regras import EMPRESAS, ESTAGIOS, TIPOS, aplicar_classes

ACOES = {"arquivar", "excluir", "restaurar", "trazer", "descartar", "clonar"}


def _ler_json(caminho, padrao):
    try:
        with open(caminho, encoding="utf-8") as f:
            return json.load(f)
    except (OSError, ValueError):
        return padrao


def _classe_valida(c):
    """Classe vinda do painel: empresa, tipo e estagio da lista; area, cliente e linear texto curto."""
    campos = ("empresa", "area", "cliente", "tipo", "linear", "estagio")
    assert isinstance(c, dict) and set(c) <= set(campos)
    assert (c.get("empresa") or "") in EMPRESAS + ("",) and (c.get("tipo") or "") in TIPOS + ("",)
    assert (c.get("estagio") or "") in ESTAGIOS + ("",)
    for k in ("area", "cliente", "linear"):
        v = c.get(k) or ""
        assert isinstance(v, str) and len(v) <= 60 and (not v or NOME.fullmatch(v))
    return {k: (c.get(k) or "").strip() for k in campos}


class _UnixHTTP(socketserver.ThreadingMixIn, socketserver.UnixStreamServer):
    daemon_threads = True


def criar(host, porta, web, painel, fila, ajustes, bloquear_local=True, classes="/var/lib/pmo/classes.json",
          *, socket=None, hosts=(), logins=(), saude=None, atalhos=None, timeout=10):
    if socket and not (hosts and logins):
        raise ValueError("modo socket exige hosts e logins nao vazios (fail closed)")
    os.makedirs(fila, mode=0o700, exist_ok=True)
    trava = threading.Lock()
    _timeout = timeout

    def ler_painel():
        with open(painel, encoding="utf-8") as f:
            d = json.load(f)
        d = aplicar_classes(aplicar_ajustes(d, _ler_json(ajustes, {})), _ler_json(classes, {}))
        if saude:  # lido a cada GET: tempo real, sem esperar a coleta diaria
            d["saude"] = ler_saude(saude, datetime.now(timezone.utc))
        if atalhos is not None:
            # vira href no front: so https
            d["atalhos"] = {k: v if isinstance(v, str) and v.startswith("https://") else None for k, v in atalhos.items()}
        return d

    def classificar(alvo, classe):
        with trava:
            todas = _ler_json(classes, {})
            todas[alvo] = classe
            tmp = classes + ".tmp"
            with open(tmp, "w", encoding="utf-8") as f:
                json.dump(todas, f, ensure_ascii=False)
            os.replace(tmp, classes)

    class Handler(SimpleHTTPRequestHandler):
        # leitura parada nao prende a thread: o corpo e lido antes da autenticacao
        timeout = _timeout

        def __init__(self, *a, **k):
            super().__init__(*a, directory=web, **k)

        def log_message(self, *a):
            pass

        def list_directory(self, path):
            self.send_error(404)

        def _caminho_seguro(self):
            p = unquote(urlsplit(self.path).path)
            return ".." not in p.split("/")

        def _host_ok(self):
            if hosts:
                return self.headers.get("Host") in hosts
            return self.headers.get("Host") == "%s:%d" % self.server.server_address[:2]

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
            try:  # le o corpo antes de qualquer resposta (recusar sem ler faz o cliente tomar RST); limitado e com timeout
                n = max(0, min(int(self.headers.get("Content-Length") or 0), 4096))
                bruto = self.rfile.read(n)
            except ValueError:
                bruto = b""
            except OSError:  # timeout ou conexao quebrada: so fecha, sem traceback
                self.close_connection = True
                return
            origem = self.headers.get("Origin")
            if not socket and bloquear_local:
                cliente = self.client_address[0]
                if cliente == self.server.server_address[0] or cliente.startswith("127."):
                    # pedido de dentro da VPS (agente, container) nunca vira acao; so o laptop pela tailnet
                    return self._resposta(403, "recusado: pedido de dentro da VPS")
            host = self.headers.get("Host")
            if (not self._host_ok() or self.headers.get("X-PMO") != "1"
                    or (self.headers.get("Content-Type") or "").split(";")[0].strip() != "application/json"
                    or origem not in (None, "http://" + host, "https://" + host)
                    or (logins and self.headers.get("Tailscale-User-Login") not in logins)):
                return self._resposta(403, "recusado")
            if urlsplit(self.path).path != "/acao":
                return self.send_error(404)
            try:
                ped = json.loads(bruto or b"null")
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

    if not socket:
        return ThreadingHTTPServer((host, porta), Handler)
    if os.path.lexists(socket):
        if not stat.S_ISSOCK(os.lstat(socket).st_mode):
            raise ValueError(f"{socket} existe e nao e um socket; nao vou apagar")
        os.unlink(socket)
    srv = _UnixHTTP(socket, Handler)
    os.chmod(socket, 0o660)
    return srv


def main():
    a = argparse.ArgumentParser()
    a.add_argument("--host", default="100.76.167.6")
    a.add_argument("--porta", type=int, default=8080)
    a.add_argument("--web", default=os.path.join(os.path.dirname(__file__), "web"))
    a.add_argument("--painel", default="/srv/dev/state/pmo/painel.json")
    a.add_argument("--fila", default="/var/lib/pmo/fila")
    a.add_argument("--ajustes", default="/var/lib/pmo/ajustes.json")
    a.add_argument("--classes", default="/var/lib/pmo/classes.json")
    a.add_argument("--saude", default="/srv/dev/state/health.txt")
    a.add_argument("--socket")
    a.add_argument("--hosts", default="")
    a.add_argument("--logins", default="")
    o = a.parse_args()
    lista = lambda t: tuple(x.strip() for x in t.split(",") if x.strip())  # noqa: E731
    hosts, logins = lista(o.hosts), lista(o.logins)
    if o.socket and not logins:
        a.error("--socket exige --logins nao vazio (sem lista, nenhuma acao seria autenticada)")
    if o.socket and not hosts:
        a.error("--socket exige --hosts nao vazio (sem lista, todo pedido seria recusado)")
    criar(o.host, o.porta, o.web, o.painel, o.fila, o.ajustes, classes=o.classes,
          socket=o.socket, hosts=hosts, logins=logins, saude=o.saude,
          atalhos={"opencode": os.environ.get("PMO_ATALHO_OPENCODE")}).serve_forever()


if __name__ == "__main__":
    main()
