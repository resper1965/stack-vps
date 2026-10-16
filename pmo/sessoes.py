"""Sessões do OpenCode 2 para o painel: METADADO apenas, pelo `opencode api`.

Roda como agente (ExecStartPost do pmo-coleta.service). O `opencode api` faz a
descoberta do servidor e usa a autenticação do próprio cliente: nenhuma porta,
senha ou modelo é fixado. De cada sessão guarda só id, agent, outcome,
criada/atualizada e projeto — o id dono/repo (minúsculo, igual às chaves de
mapear_locais) do clone sob /srv/dev/projetos que contém o diretório da sessão.
Título, caminho absoluto e conteúdo de mensagens (nunca consultado) ficam de
fora; os tipos recebidos da API são validados com rigor. Cursor repetido,
sessão duplicada, item de tipo errado ou paginação que não termina marcam a
coleta como incompleta — e só coleta completa substitui o anterior (0600,
gravado em atômica). API indisponível não derruba a coleta diária.
"""
import json
import os
import shutil
import subprocess
import sys
import tempfile
import urllib.parse
from datetime import datetime, timezone

from pmo.coleta import mapear_locais

SAIDA = "/srv/dev/state/pmo/sessoes.json"
RAIZ = "/srv/dev/projetos"
LIMITE_PAGINA = 100
LIMITE_PAGINAS = 50
TIMEOUT = 20


class ColetaFalhada(Exception):
    pass


def _binario():
    return os.environ.get("OPENCODE_BIN") or shutil.which("opencode") or "/home/agente/.opencode/bin/opencode"


def _get(caminho):
    """GET pelo opencode api; timeout, saída com erro ou resposta não-JSON levanta ColetaFalhada."""
    try:
        r = subprocess.run([_binario(), "api", "get", caminho], capture_output=True, timeout=TIMEOUT)
    except (subprocess.TimeoutExpired, OSError) as e:
        raise ColetaFalhada(f"opencode api indisponível: {e}")
    if r.returncode != 0:
        erro = r.stderr.decode("utf-8", errors="replace").strip()[:200]
        raise ColetaFalhada(f"opencode api saiu com {r.returncode}: {erro}")
    try:
        d = json.loads(r.stdout.decode("utf-8", errors="replace"))
    except ValueError as e:
        raise ColetaFalhada(f"resposta inválida: {e}")
    if not isinstance(d, dict) or not isinstance(d.get("data"), list):
        raise ColetaFalhada("estrutura inesperada da API")
    return d


def _str(v):
    return v if isinstance(v, str) else None


def _int(v):
    return v if isinstance(v, int) and not isinstance(v, bool) else None


def _validado(d):
    """Diretório resolvido com realpath — usado apenas para associar; nunca persistido."""
    return os.path.realpath(d) if isinstance(d, str) and d else None


def _metadado(s):
    """Tipos rígidos: id str não vazio; agent/outcome str; tempo int; diretório str.
    Item sem id (ou estrutura inesperada) fica de fora; campo de tipo errado vira None."""
    if not isinstance(s, dict) or not isinstance(s.get("id"), str) or not s.get("id"):
        return None
    t = s.get("time") or {}
    loc = s.get("location") or {}
    return {"id": s["id"], "agent": _str(s.get("agent")), "outcome": _str(s.get("outcome")),
            "criada": _int(t.get("created")) if isinstance(t, dict) else None,
            "atualizada": _int(t.get("updated")) if isinstance(t, dict) else None,
            "diretorio": _validado(loc.get("directory")) if isinstance(loc, dict) else None}


def _degradado(s, m):
    """Campo presente na resposta mas de tipo errado: a sessão fica com None e marca incompleta."""
    t, loc = s.get("time"), s.get("location")
    return ((s.get("agent") is not None and m["agent"] is None)
            or (s.get("outcome") is not None and m["outcome"] is None)
            or (t is not None and (not isinstance(t, dict)
                or (t.get("created") is not None and m["criada"] is None)
                or (t.get("updated") is not None and m["atualizada"] is None)))
            or (loc is not None and (not isinstance(loc, dict) or m["diretorio"] is None)))


def _projeto(diretorio, bases):
    """id dono/repo do clone (sob RAIZ) que contém o caminho: longest-prefix por subida de nível."""
    raiz = os.path.realpath(RAIZ)
    if not diretorio or not (diretorio == raiz or diretorio.startswith(raiz + os.sep)):
        return None
    while diretorio != raiz:
        if diretorio in bases:
            return bases[diretorio]
        diretorio = os.path.dirname(diretorio)
    return None


def listar(api, limite=LIMITE_PAGINA, max_paginas=LIMITE_PAGINAS):
    """Sessões com paginação por cursor. Falha da API na 1a página (ou sem item válido) levanta;
    cursor repetido, sessão duplicada, item ou cursor de tipo errado e limite de páginas marcam
    incompleta. Quem grava é rodar: só coleta completa substitui o anterior."""
    itens, vistos, cursores, incompleta = [], set(), set(), False
    caminho = f"/api/session?limit={limite}"
    for pagina in range(1, max_paginas + 1):
        try:
            d = api(caminho)
        except ColetaFalhada:
            if pagina == 1 or not itens:
                raise
            return itens, True
        for s in d["data"]:
            m = _metadado(s)
            if m is None:
                incompleta = True
            elif m["id"] in vistos:
                incompleta = True  # sessão repetida — a listagem está em loop
            else:
                if _degradado(s, m):
                    incompleta = True
                vistos.add(m["id"])
                itens.append(m)
        cursor = d.get("cursor")
        if "cursor" in d and not isinstance(cursor, dict):
            incompleta = True  # cursor de tipo errado
            cursor = {}
        proximo = _str(cursor.get("next")) if isinstance(cursor, dict) else None
        if not (proximo and d["data"]):
            return itens, incompleta
        if proximo in cursores:
            return itens, True  # cursor repetido — a listagem está em loop
        cursores.add(proximo)
        caminho = f"/api/session?limit={limite}&cursor={urllib.parse.quote(proximo, safe='')}"
    return itens, True


def coletar(api, locais, agora):
    """dados do sessoes.json; locais = {dono/repo (minúsculo): base} do coleta.mapear_locais.
    O caminho absoluto entra e sai: vira projeto (id dono/repo) e nada de caminho é persistido."""
    bases = {os.path.realpath(base): rid for rid, base in locais.items()}
    sessoes, incompleta = listar(api)
    for m in sessoes:
        m["projeto"] = _projeto(m.pop("diretorio"), bases)
    sessoes.sort(key=lambda m: m["atualizada"] or 0, reverse=True)
    return {"gerado_em": agora.isoformat(), "coleta_incompleta": incompleta,
            "contadores": {"sessoes": len(sessoes), "com_projeto": sum(1 for m in sessoes if m["projeto"])},
            "sessoes": sessoes}


def gravar(dados, caminho=SAIDA):
    os.makedirs(os.path.dirname(caminho), exist_ok=True)
    fd, tmp = tempfile.mkstemp(dir=os.path.dirname(caminho), suffix=".json")
    with os.fdopen(fd, "w", encoding="utf-8") as f:
        json.dump(dados, f, ensure_ascii=False, indent=1)
    os.chmod(tmp, 0o600)
    os.replace(tmp, caminho)


def rodar(api, locais, agora, saida=SAIDA):
    """Grava só coleta completa; falha, incompleta ou resposta inválida mantém o anterior
    e não derruba a coleta diária."""
    try:
        dados = coletar(api, locais, agora)
    except ColetaFalhada as e:
        print(f"sessões indisponíveis (mantendo o anterior): {e}", file=sys.stderr)
        return
    if dados["coleta_incompleta"]:
        print("sessões: coleta incompleta (mantendo o anterior)", file=sys.stderr)
        return
    gravar(dados, saida)
    c = dados["contadores"]
    print(f"sessões: {c['sessoes']} | {c['com_projeto']} com projeto")


def main():
    rodar(_get, mapear_locais(RAIZ), datetime.now(timezone.utc))


if __name__ == "__main__":
    main()
