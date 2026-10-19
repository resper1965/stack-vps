"""Espelho de mão única PMO -> Linear: uma lista, um projeto por linha, só o ESTÁGIO é enviado.
Nunca apaga nada no Linear; arquivado vira status do tipo canceled, uma vez."""
import argparse
import fcntl
import json
import os
import sys
import tempfile
import unicodedata
import urllib.error
import urllib.request
from contextlib import contextmanager

URL = "https://api.linear.app/graphql"
TIPO_DO_ESTAGIO = {"ideia": "backlog", "em andamento": "started", "em revisão": "started", "parado": "paused",
                   "congelado": "paused", "entregue": "completed", "encerrado": "completed", "arquivado": "canceled"}
LIMITE_LOTE = 20
TOKEN, TIME = "/etc/pmo/linear-token", "/etc/pmo/linear-team"
VINCULOS, TRAVA = "/var/lib/pmo/linear.json", "/var/lib/pmo/linear.lock"
PAINEL, AJUSTES, CLASSES = "/srv/dev/state/pmo/painel.json", "/var/lib/pmo/ajustes.json", "/var/lib/pmo/classes.json"


class LoteGrande(Exception):
    pass


def _norm(s):
    return unicodedata.normalize("NFD", s).encode("ascii", "ignore").decode().lower().strip()


def escolher_status(estagio, statuses):
    for s in statuses:
        if _norm(s["name"]) == _norm(estagio):
            return s["id"]
    for s in statuses:
        if s["type"] == TIPO_DO_ESTAGIO[estagio]:
            return s["id"]
    raise ValueError(f"sem status no Linear para o estágio '{estagio}'")


def desejado(painel):
    itens = [(p["id"], p["nome"], p.get("estagio") or p.get("estagio_sugerido") or "em andamento")
             for p in painel.get("projetos", [])]
    itens += [(p["id"], p["nome"], "arquivado") for p in painel.get("arquivados", [])]
    nomes = [n for _, n, _ in itens]
    # nome repetido entre projetos: usa dono/repo para a lista do Linear não ter duas linhas iguais
    return {i: (i if nomes.count(n) > 1 else n, e) for i, n, e in itens}


def planejar(desejado, vinculos):
    ops = []
    for id, (nome, estagio) in desejado.items():
        v = vinculos.get(id)
        if v is None:
            if estagio != "arquivado":
                ops.append({"op": "criar", "id": id, "nome": nome, "estagio": estagio})
        elif v["enviado"] != estagio:
            ops.append({"op": "atualizar", "id": id, "linear_id": v["linear_id"], "estagio": estagio})
    return ops


def verificar_lote(ops, confirmar_lote):
    n = sum(1 for o in ops if o["op"] == "criar")
    if n > LIMITE_LOTE and not confirmar_lote:
        raise LoteGrande(f"{n} projetos a criar (limite {LIMITE_LOTE}); confira a prévia e use --confirmar-lote")


def _post_http(url, headers, corpo):
    req = urllib.request.Request(url, data=json.dumps(corpo).encode(), headers=headers, method="POST")
    try:
        with urllib.request.urlopen(req, timeout=10) as r:
            return json.load(r)
    except urllib.error.HTTPError as e:
        raise RuntimeError(f"HTTP {e.code}: {e.read(200).decode('utf-8', 'replace')}") from None
    except (urllib.error.URLError, OSError, ValueError) as e:
        raise RuntimeError(f"falha de rede: {e}") from None


class Linear:
    def __init__(self, token, post=_post_http):
        self.token, self._post = token, post

    def _q(self, query, variaveis=None):
        # chave pessoal vai sem "Bearer" (spike 2026-10-18)
        cab = {"Authorization": self.token, "Content-Type": "application/json", "User-Agent": "stack-pmo"}
        try:
            r = self._post(URL, cab, {"query": query, "variables": variaveis or {}})
            if r.get("errors"):
                raise RuntimeError("; ".join(str(e.get("message")) for e in r["errors"]))
            return r["data"]
        except RuntimeError as e:
            raise RuntimeError(str(e).replace(self.token, "***")) from None

    def statuses(self):
        return self._q("{ projectStatuses(first: 100) { nodes { id name type } } }")["projectStatuses"]["nodes"]

    def time(self, key):
        nos = self._q("query($k: String!) { teams(filter: {key: {eq: $k}}) { nodes { id } } }",
                      {"k": key})["teams"]["nodes"]
        if not nos:
            raise RuntimeError(f"time '{key}' não encontrado no Linear")
        return nos[0]["id"]

    def criar(self, nome, time_id, status_id):
        return self._q("mutation($n: String!, $t: String!, $s: String!) { projectCreate(input: "
                       "{name: $n, teamIds: [$t], statusId: $s}) { project { id } } }",
                       {"n": nome, "t": time_id, "s": status_id})["projectCreate"]["project"]["id"]

    def atualizar(self, linear_id, status_id):
        d = self._q("mutation($id: String!, $s: String!) { projectUpdate(id: $id, input: {statusId: $s}) "
                    "{ success } }", {"id": linear_id, "s": status_id})
        if not d["projectUpdate"]["success"]:
            raise RuntimeError("projectUpdate sem sucesso")


def _ler_vinculos(caminho):
    try:
        with open(caminho, encoding="utf-8") as f:
            return json.load(f)
    except FileNotFoundError:
        return {}


def _gravar(dados, caminho):
    fd, tmp = tempfile.mkstemp(dir=os.path.dirname(caminho), suffix=".tmp")
    with os.fdopen(fd, "w", encoding="utf-8") as f:
        json.dump(dados, f, ensure_ascii=False, indent=1)
    os.replace(tmp, caminho)


@contextmanager
def _trava(caminho):
    fd = os.open(caminho, os.O_CREAT | os.O_RDWR, 0o600)
    try:
        fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
    except BlockingIOError:
        os.close(fd)
        yield False
        return
    try:
        yield True
    finally:
        os.close(fd)  # fechar solta o flock


def sincronizar(api, painel, vinculos_path, trava_path, previa, confirmar_lote, time_key):
    with _trava(trava_path) as livre:
        if not livre:
            return []
        vinculos = _ler_vinculos(vinculos_path)
        ops = planejar(desejado(painel), vinculos)
        if previa or not ops:
            return ops
        verificar_lote(ops, confirmar_lote)
        statuses = api.statuses()
        time_id = api.time(time_key) if any(o["op"] == "criar" for o in ops) else None
        for o in ops:
            status = escolher_status(o["estagio"], statuses)
            if o["op"] == "criar":
                vinculos[o["id"]] = {"linear_id": api.criar(o["nome"], time_id, status), "enviado": o["estagio"]}
            else:
                api.atualizar(o["linear_id"], status)
                vinculos[o["id"]]["enviado"] = o["estagio"]
            _gravar(vinculos, vinculos_path)
        return ops


def _json(caminho, padrao=None):
    try:
        with open(caminho, encoding="utf-8") as f:
            return json.load(f)
    except (OSError, ValueError):
        if padrao is None:
            raise
        return padrao


def main(argv=None):
    a = argparse.ArgumentParser()
    a.add_argument("--previa", action="store_true")
    a.add_argument("--confirmar-lote", action="store_true")
    o = a.parse_args(argv)
    try:
        from pmo.painel import montar
        token = open(TOKEN, encoding="utf-8").read().strip()
        time_key = open(TIME, encoding="utf-8").read().strip()
        # montar muta a entrada: sempre dicts recém-lidos do disco, uma única vez
        painel = montar(_json(PAINEL), _json(AJUSTES, {}), _json(CLASSES, {}))
        ops = sincronizar(Linear(token), painel, VINCULOS, TRAVA, o.previa, o.confirmar_lote, time_key)
    except LoteGrande as e:
        print(f"linear: {e}", file=sys.stderr)
        return 2
    except Exception as e:  # noqa: BLE001 — o espelho nunca bloqueia o PMO; a unidade falha e o health avisa
        print(f"linear: {type(e).__name__}: {e}", file=sys.stderr)
        return 1
    nomes = desejado(painel)
    for op in ops:
        print(f"{op['op']} {nomes[op['id']][0]} -> {op['estagio']}")
    if not ops:
        print("linear: nada a fazer (ou outra corrida em andamento)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
