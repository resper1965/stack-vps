"""Gera o painel.json a partir da coleta; CLI roda a coleta completa."""
import json
import os
import sys
import tempfile
from datetime import datetime, timezone

from pmo.regras import contar

SAIDA = "/srv/dev/state/pmo/painel.json"


def a_destinar(raiz="/srv/dev/laptop"):
    """Pastas sem git vindas do laptop/WSL: a mais alta, a partir do 2o nivel, que tenha arquivo direto."""
    itens = []

    def visitar(caminho, nivel):
        if os.path.isdir(os.path.join(caminho, ".git")):
            return
        try:
            entradas = list(os.scandir(caminho))
        except OSError:
            return
        if nivel >= 2 and any(e.is_file() for e in entradas):
            n = sum(len(f) for _, _, f in os.walk(caminho))
            itens.append({"id": "destinar:" + os.path.relpath(caminho, raiz).replace(os.sep, "/"),
                          "caminho": os.path.relpath(caminho, raiz).replace(os.sep, "/"), "arquivos": n})
            return
        if nivel < 3:
            for e in sorted(entradas, key=lambda e: e.name):
                if e.is_dir() and e.name not in ("node_modules", ".venv"):
                    visitar(e.path, nivel + 1)

    if os.path.isdir(raiz):
        visitar(raiz, 0)
    return itens


def gerar(registros, destinar, anterior, agora):
    incompleta = registros is None
    if incompleta:
        registros = (anterior or {}).get("projetos", []) + (anterior or {}).get("arquivados", [])
    ativos = sorted((r for r in registros if not r.get("arquivado")), key=lambda r: r["id"].lower())
    arquivados = sorted((r for r in registros if r.get("arquivado")), key=lambda r: r["id"].lower())
    est = lambda r: r.get("estagio") or r.get("estagio_sugerido")
    contadores = contar(ativos, len(destinar))
    antes = {r["id"]: r for r in (anterior or {}).get("projetos", [])}
    mudou = {"novos": [], "mudou_estagio": [], "viraram_esquecidos": []}
    if anterior and not incompleta:
        for r in ativos:
            a = antes.get(r["id"])
            if a is None:
                mudou["novos"].append(r["id"])
            else:
                if est(a) != est(r):
                    mudou["mudou_estagio"].append(r["id"])
                if r.get("esquecido") and not a.get("esquecido"):
                    mudou["viraram_esquecidos"].append(r["id"])
    return {"gerado_em": agora.isoformat(), "coleta_incompleta": incompleta, "contadores": contadores,
            "mudou_desde_ontem": mudou, "projetos": ativos, "arquivados": arquivados, "a_destinar": destinar}


def gravar(dados, caminho=SAIDA):
    os.makedirs(os.path.dirname(caminho), exist_ok=True)
    fd, tmp = tempfile.mkstemp(dir=os.path.dirname(caminho), suffix=".json")
    with os.fdopen(fd, "w", encoding="utf-8") as f:
        json.dump(dados, f, ensure_ascii=False, indent=1)
    os.chmod(tmp, 0o644)
    os.replace(tmp, caminho)


def main():
    from pmo.coleta import coletar, mapear_locais
    from pmo.github import GitHub
    token = os.environ.get("GITHUB_TOKEN") or sys.exit("falta GITHUB_TOKEN")
    donos = open(os.path.join(os.path.dirname(__file__), "donos.txt"), encoding="utf-8").read().split()
    try:
        anterior = json.load(open(SAIDA, encoding="utf-8"))
    except (OSError, ValueError):
        anterior = None
    agora = datetime.now(timezone.utc)
    try:
        regs = coletar(GitHub(token), donos, mapear_locais("/srv/dev/projetos"), agora, anterior)
    except Exception as e:  # noqa: BLE001 — qualquer falha da API mantem o painel anterior
        print(f"coleta incompleta: {e}", file=sys.stderr)
        regs = None
    dados = gerar(regs, a_destinar(), anterior, agora)
    gravar(dados)
    c = dados["contadores"]
    print(f"painel: {c['projetos']} projetos | {c['esquecidos']} esquecidos | {c['a_destinar']} a destinar"
          + (" | COLETA INCOMPLETA" if dados["coleta_incompleta"] else ""))


if __name__ == "__main__":
    main()
