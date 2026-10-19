"""Gera o painel.json a partir da coleta; CLI roda a coleta completa."""
import json
import os
import sys
import tempfile
from datetime import datetime, timezone

from pmo.regras import contar

SAIDA = "/srv/dev/state/pmo/painel.json"
SESSOES = "/srv/dev/state/pmo/sessoes.json"   # 0600, escrito pelo coletor do próprio agente
DEFAZAGEM = 2 * 86400
SAUDE = "/srv/dev/state/health.txt"   # saida do health.sh, gravada pelo vigia-health
SAUDE_VELHA = 90 * 60   # 1,5x o periodo do stack-health.timer (OnCalendar=hourly)
_ESTADOS = {"ok": "ok", "FALHA": "falha", "pend": "pend"}


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


def fundir(dados, sessoes, agora):
    """Consolida sessões do OpenCode aos projetos: join projeto -> id.lower().
    Ausente, corrupta, incompleta (o coletor só grava coleta completa — tratada como ausente)
    ou defasada não derrubam a geração; só agregados por projeto (contagem, última atividade,
    id completo da mais recente, para o comando opencode -s) — a lista bruta (0600, do agente)
    nunca vem para o painel. Muta e retorna."""
    if not isinstance(sessoes, dict) or not isinstance(sessoes.get("sessoes"), list):
        return dados
    if sessoes.get("coleta_incompleta"):
        return dados
    por_id = {}
    for s in sessoes["sessoes"]:
        if not isinstance(s, dict):
            continue
        projeto, sid = s.get("projeto"), s.get("id")
        if not isinstance(projeto, str) or not isinstance(sid, str):
            continue
        atualizada = s.get("atualizada")
        if not isinstance(atualizada, int) or isinstance(atualizada, bool):
            atualizada = 0
        por_id.setdefault(projeto.lower(), []).append((atualizada, sid))
    if not por_id:
        return dados
    projetos = {x["id"].lower(): x for k in ("projetos", "arquivados") for x in dados.get(k, [])}
    com = 0
    for id, lista in por_id.items():
        p = projetos.get(id)
        if p is None:
            continue
        atualizada, sid = max(lista)
        p["sessoes"] = len(lista)
        p["ultima_sessao"] = atualizada or None
        p["sessao_id"] = sid
        com += 1
    if isinstance(dados.get("contadores"), dict):
        dados["contadores"]["projetos_com_sessao"] = com
    gerado = sessoes.get("gerado_em")
    gerado = gerado.strip() if isinstance(gerado, str) else ""
    dados["sessoes_gerado_em"] = gerado or None
    try:
        g = datetime.fromisoformat(gerado)
        if (agora - g).total_seconds() > DEFAZAGEM:
            dados["sessoes_defasada"] = True
    except (ValueError, TypeError):
        pass
    return dados


def ler_sessoes(caminho=SESSOES):
    """sessoes.json (0600, do próprio agente); ausente, corrupto ou fora de contrato vira None."""
    try:
        with open(caminho, encoding="utf-8") as f:
            d = json.load(f)
    except (OSError, ValueError):
        return None
    return d if isinstance(d, dict) and isinstance(d.get("sessoes"), list) else None


def ler_saude(caminho, agora):
    """health.txt: linha sem indentacao abre secao; '  ok|FALHA|pend texto' e item. Linha estranha e ignorada."""
    vazio = {"gerado_em": None, "velho": True, "itens": []}
    try:
        with open(caminho, encoding="utf-8", errors="replace") as f:
            linhas = f.read().splitlines()
        mtime = datetime.fromtimestamp(os.stat(caminho).st_mtime, timezone.utc)
    except OSError:
        return vazio
    itens, secao = [], ""
    for ln in linhas:
        if not ln.strip():
            continue
        if not ln[0].isspace():
            secao = ln.strip()
            continue
        estado, _, texto = ln.strip().partition(" ")
        if estado in _ESTADOS and texto.strip():
            itens.append({"secao": secao, "estado": _ESTADOS[estado], "texto": texto.strip()})
    if not itens:
        return vazio
    return {"gerado_em": mtime.isoformat(), "velho": (agora - mtime).total_seconds() > SAUDE_VELHA, "itens": itens}


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
    fundir(dados, ler_sessoes(), agora)
    gravar(dados)
    c = dados["contadores"]
    com = c.get("projetos_com_sessao")
    extra = ""
    if com is not None:
        n = sum(p["sessoes"] for k in ("projetos", "arquivados") for p in dados[k] if "sessoes" in p)
        extra = f" | sessões: {n} em {com} projetos" + (" | DEFAZADA" if dados.get("sessoes_defasada") else "")
    print(f"painel: {c['projetos']} projetos | {c['esquecidos']} esquecidos | {c['a_destinar']} a destinar"
          + (" | COLETA INCOMPLETA" if dados["coleta_incompleta"] else "") + extra)


if __name__ == "__main__":
    main()
