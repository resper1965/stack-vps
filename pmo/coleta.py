"""Coleta: um registro por repositório dos donos acompanhados."""
import configparser
import os
import re
from datetime import datetime

from pmo.regras import ler_state, estagio_sugerido, esquecido


def _data(iso):
    return datetime.fromisoformat(iso.replace("Z", "+00:00")) if iso else None


def mapear_locais(raiz):
    """dono/repo (minúsculo) -> pasta local, a partir do origin de cada clone (até 3 níveis)."""
    locais = {}
    for base, dirs, _ in os.walk(raiz):
        if base[len(raiz):].count(os.sep) > 3:
            dirs[:] = []
            continue
        if ".git" in dirs:
            cfg = configparser.ConfigParser(strict=False)
            try:
                cfg.read(os.path.join(base, ".git", "config"), encoding="utf-8")
                url = cfg.get('remote "origin"', "url")
            except (configparser.Error, OSError):
                url = ""
            m = re.search(r"github\.com[:/]([^/]+)/([^/]+?)(?:\.git)?/?$", url)
            if m:
                locais[f"{m.group(1)}/{m.group(2)}".lower()] = base
            dirs[:] = []
    return locais


def coletar(gh, donos, locais, agora):
    registros = []
    for dono in donos:
        for r in gh.repos(dono):
            if r.get("fork"):
                continue
            d, nome = r["owner"]["login"], r["name"]
            arq = bool(r.get("archived"))
            st = ler_state(gh.state_md(d, nome))
            res = gh.resumo(d, nome, r.get("open_issues_count", 0))
            ultima = _data(r.get("pushed_at"))
            dias = (agora - ultima).days if ultima else 9999
            sug = estagio_sugerido(dias, res["prs"], arq)
            registros.append({
                "id": f"{d}/{nome}", "nome": nome, "dono": d, "url": r.get("html_url"),
                "privado": bool(r.get("private")), "arquivado": arq,
                "ultima_atividade": r.get("pushed_at"), "dias": dias,
                "tipo": st["tipo"], "estagio": st["estagio"], "estagio_sugerido": sug, "proximo": st["proximo"],
                "prs": res["prs"], "issues": res["issues"], "ci": res["ci"], "wip": res["wip"],
                "pasta": locais.get(f"{d}/{nome}".lower()),
                "esquecido": esquecido(st["estagio"] or sug, dias, st["proximo"], arq, declarado=st["estagio"] is not None),
            })
    return registros
