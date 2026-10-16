"""Sessões do OpenCode 2 para o painel: METADADO apenas, pelo `opencode api`.

Roda como agente (ExecStartPost do pmo-coleta.service). O `opencode api` faz a
descoberta do servidor e usa a autenticação do próprio cliente: nenhuma porta,
senha ou modelo é fixado. De cada sessão guarda só id, agent, outcome,
criada/atualizada, título (até 300) e diretório resolvido com realpath; projeto
é o id dono/repo (minúsculo, igual às chaves de mapear_locais) do clone sob
/srv/dev/projetos que contém o caminho. Nunca prompts, transcrições, custo,
tokens ou secrets. API indisponível na 1a página não grava (preserva o arquivo
anterior) e não derruba a coleta diária.
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
LIMITE_TITULO = 300
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


def _validado(loc):
    """Diretório da sessão resolvido com realpath; ausente ou não-texto vira None."""
    d = loc.get("directory") if isinstance(loc, dict) else None
    return os.path.realpath(d) if isinstance(d, str) and d else None


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


def _metadado(s):
    """Só metadado; item sem id ou com estrutura inesperada fica de fora (vira coleta incompleta)."""
    if not isinstance(s, dict) or not isinstance(s.get("id"), str):
        return None
    t = s.get("time") or {}
    titulo = (s.get("title") or "").strip()
    if len(titulo) > LIMITE_TITULO:
        titulo = titulo[:LIMITE_TITULO - 1] + "…"
    return {"id": s["id"], "agent": s.get("agent") or None, "outcome": s.get("outcome") or None,
            "criada": t.get("created"), "atualizada": t.get("updated"), "titulo": titulo or None,
            "diretorio": _validado(s.get("location") or {})}


def listar(api, limite=LIMITE_PAGINA, max_paginas=LIMITE_PAGINAS):
    """Sessões com paginação por cursor. Falha na 1a página (ou sem item válido) levanta;
    falha no meio devolve o que tem. Cursor que não termina dentro do limite vira incompleta."""
    itens, incompleta = [], False
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
            else:
                itens.append(m)
        proximo = (d.get("cursor") or {}).get("next")
        if not (proximo and d["data"]):
            return itens, incompleta
        caminho = f"/api/session?limit={limite}&cursor={urllib.parse.quote(proximo, safe='')}"
    return itens, True


def coletar(api, locais, agora):
    """dados do sessoes.json; locais = {dono/repo (minúsculo): base} do coleta.mapear_locais."""
    bases = {os.path.realpath(base): rid for rid, base in locais.items()}
    sessoes, incompleta = listar(api)
    for m in sessoes:
        m["projeto"] = _projeto(m["diretorio"], bases)
    sessoes.sort(key=lambda m: m["atualizada"] or 0, reverse=True)
    return {"gerado_em": agora.isoformat(), "coleta_incompleta": incompleta,
            "contadores": {"sessoes": len(sessoes), "com_projeto": sum(1 for m in sessoes if m["projeto"])},
            "sessoes": sessoes}


def gravar(dados, caminho=SAIDA):
    os.makedirs(os.path.dirname(caminho), exist_ok=True)
    fd, tmp = tempfile.mkstemp(dir=os.path.dirname(caminho), suffix=".json")
    with os.fdopen(fd, "w", encoding="utf-8") as f:
        json.dump(dados, f, ensure_ascii=False, indent=1)
    os.chmod(tmp, 0o644)
    os.replace(tmp, caminho)


def rodar(api, locais, agora, saida=SAIDA):
    """Coleta e grava; indisponibilidade total (ou resposta só com itens inválidos)
    retorna sem gravar — o arquivo anterior fica de pé e a coleta diária segue."""
    try:
        dados = coletar(api, locais, agora)
    except ColetaFalhada as e:
        print(f"sessões indisponíveis (mantendo o anterior): {e}", file=sys.stderr)
        return
    if dados["coleta_incompleta"] and not dados["sessoes"]:
        print("sessões: resposta só com itens inválidos (mantendo o anterior)", file=sys.stderr)
        return
    gravar(dados, saida)
    c = dados["contadores"]
    print(f"sessões: {c['sessoes']} | {c['com_projeto']} com projeto"
          + (" | COLETA INCOMPLETA" if dados["coleta_incompleta"] else ""))


def main():
    rodar(_get, mapear_locais(RAIZ), datetime.now(timezone.utc))


if __name__ == "__main__":
    main()
