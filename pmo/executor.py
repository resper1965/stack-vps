"""Executor das acoes do painel (usuario pmo, timer de 1 minuto).

Le os pedidos da fila (do pmo, 700), executa, registra no log e grava os ajustes que o servidor aplica
ao painel. Protecoes:
- roda sem privilegio; pastas do agente so sao mexidas COMO agente, pelo pmo-pasta (pmo/pasta.py);
- dono precisa estar em donos.txt (do root); organizacao de cliente (nessenergy) nunca e excluida;
- excluir exige o nome do repositorio digitado; mesmo pedido repetido em 10 minutos executa uma vez;
- pedido que nao e arquivo comum do proprio pmo, ou com caractere de controle, e recusado.
"""
import json
import os
import re
import stat
import subprocess
import sys
from datetime import datetime, timezone

from pmo.coleta import mapear_locais
from pmo.pasta import NOME
from pmo.regras import aplicar_classes

CLIENTES = {"nessenergy/alupdatalake", "nessenergy/sitealupar"}  # so arquivar; o resto da nessenergy e da Ness
JANELA_DUPLICADO = 600
DIAS_LIXEIRA = 30
PASTA = "/usr/local/bin/pmo-pasta"


class Recusado(Exception):
    pass


def _pasta_como_agente(*args, entrada=None, saida=None):
    dados = entrada if isinstance(entrada, bytes) else None
    r = subprocess.run(["sudo", "-n", "-u", "agente", PASTA, *args], input=dados,
                       stdin=None if dados is not None else entrada,
                       stdout=saida or subprocess.DEVNULL, stderr=subprocess.PIPE, timeout=1800)
    msg = r.stderr.decode("utf-8", "replace").strip()
    if r.returncode:
        raise RuntimeError(msg[-300:] or f"pmo-pasta saiu com {r.returncode}")
    return msg.splitlines()[-1] if msg else "OK"


def _ler_pedido(caminho):
    """Abre sem seguir atalho e exige arquivo comum do proprio usuario."""
    fd = os.open(caminho, os.O_RDONLY | os.O_NOFOLLOW)
    with os.fdopen(fd, encoding="utf-8") as f:
        st = os.fstat(f.fileno())
        if not stat.S_ISREG(st.st_mode) or st.st_uid != os.getuid():
            raise ValueError("pedido de outro dono")
        return json.load(f)


def aplicar_ajustes(painel, ajustes):
    """Move no painel os itens que o executor ja tratou; coleta mais nova que a acao prevalece."""
    gerado = painel.get("gerado_em") or ""
    for alvo, a in ajustes.items():
        if a["em"] <= gerado:
            continue
        if a["de"] and a["de"] == a["para"]:  # so atualiza campos (ex.: pasta depois de clonar)
            for x in painel.get(a["de"], []):
                if x["id"] == alvo:
                    x.update(a.get("campos") or {})
            continue
        achados = []
        for de in [a["de"]] if a["de"] else ["projetos", "arquivados"]:  # de=None: sai de qualquer lista
            achados += [x for x in painel.get(de, []) if x["id"] == alvo]
            painel[de] = [x for x in painel.get(de, []) if x["id"] != alvo]
        if a["para"]:
            for x in achados:
                x["arquivado"] = a["para"] == "arquivados"
                painel.setdefault(a["para"], []).append(x)
    return painel


def processar(fila, gh, raiz_projetos, raiz_laptop, arquivo, log, ajustes, agora, donos, pasta=_pasta_como_agente,
              painel=None, classes=None, verticais_estado=None):
    feitos = os.path.join(fila, "feitos")
    lixeira = os.path.join(arquivo, "excluidos")
    for d in (feitos, arquivo, lixeira):
        os.makedirs(d, mode=0o700, exist_ok=True)
    data = agora.strftime("%Y%m%d-%H%M%S")
    try:
        ajustados = json.load(open(ajustes, encoding="utf-8"))
    except (OSError, ValueError):
        ajustados = {}

    def registrar(acao, alvo, resultado):
        limpo = [re.sub(r"[\x00-\x1f\x7f]", "?", str(x)) for x in (acao, alvo, resultado)]
        with open(log, "a", encoding="utf-8") as f:
            f.write(f"{agora.isoformat()}\t" + "\t".join(limpo) + "\n")

    def ajustar(alvo, de, para, campos=None):
        ajustados[alvo] = {"de": de, "para": para, "em": agora.isoformat(), **({"campos": campos} if campos else {})}

    recentes = {}
    for nome in os.listdir(feitos):
        try:
            p = json.load(open(os.path.join(feitos, nome), encoding="utf-8"))
            if not str(p.get("resultado", "")).startswith("erro"):
                recentes[(p["acao"], p["alvo"])] = max(recentes.get((p["acao"], p["alvo"]), 0), p.get("pedido_em", 0))
        except (OSError, ValueError, KeyError):
            pass

    for nome in sorted(n for n in os.listdir(fila) if n.endswith(".json") and not n.startswith(".")):
        caminho = os.path.join(fila, nome)
        try:
            ped = _ler_pedido(caminho)
            acao, alvo, conf = ped["acao"], ped["alvo"], ped.get("confirmacao")
            if not isinstance(acao, str) or not isinstance(alvo, str) or re.search(r"[\x00-\x1f\x7f]", acao + alvo):
                raise ValueError("pedido com caractere de controle")
        except (OSError, ValueError, KeyError, TypeError) as e:
            registrar("?", nome, f"recusado: pedido invalido ({e})")
            os.remove(caminho)
            continue
        chave = (acao, alvo)
        if ped.get("pedido_em", 0) - recentes.get(chave, -1e18) < JANELA_DUPLICADO:
            resultado = "duplicado (ignorado)"
        else:
            try:
                resultado = _executar(acao, alvo, conf, gh, raiz_projetos, raiz_laptop, arquivo, lixeira,
                                      data, donos, pasta, ajustar, ped.get("pasta"))
            except Recusado as e:
                resultado = f"recusado: {e}"
            except Exception as e:  # noqa: BLE001 — falha de uma acao nao para a fila
                resultado = f"erro: {e}"
            if not resultado.startswith("erro"):
                recentes[chave] = ped.get("pedido_em", 0)
        registrar(acao, alvo, resultado)
        ped["resultado"] = resultado
        json.dump(ped, open(os.path.join(feitos, nome), "w", encoding="utf-8"), ensure_ascii=False)
        os.remove(caminho)

    tmp = ajustes + ".tmp"
    json.dump(ajustados, open(tmp, "w", encoding="utf-8"), ensure_ascii=False)
    os.replace(tmp, ajustes)

    if painel and classes and verticais_estado:
        try:
            _sincronizar_verticais(painel, ajustados, classes, verticais_estado, pasta)
        except Exception as e:  # noqa: BLE001 — atalho e conveniencia; nao derruba as acoes
            registrar("verticais", "-", f"erro: {e}")

    limite = agora.timestamp() - DIAS_LIXEIRA * 86400
    for n in os.listdir(lixeira):
        p = os.path.join(lixeira, n)
        if os.path.isfile(p) and not os.path.islink(p) and os.path.getmtime(p) < limite:
            os.remove(p)


def _sincronizar_verticais(painel, ajustados, classes, estado, pasta):
    """Refaz /srv/dev/verticais (como agente) so quando o mapa empresa/area/pasta mudou."""
    d = aplicar_ajustes(json.load(open(painel, encoding="utf-8")), ajustados)
    try:
        cls = json.load(open(classes, encoding="utf-8"))
    except (OSError, ValueError):
        cls = {}
    aplicar_classes(d, cls)
    mapa = sorted(({"empresa": p["classe"]["empresa"], "area": p["classe"]["area"], "pasta": p["pasta"]}
                   for p in d.get("projetos", []) if p.get("pasta") and p["classe"]["empresa"]),
                  key=lambda x: x["pasta"])
    novo = json.dumps(mapa, ensure_ascii=False, sort_keys=True)
    try:
        if open(estado, encoding="utf-8").read() == novo:
            return
    except OSError:
        pass
    pasta("verticais", "-", entrada=novo.encode())
    with open(estado, "w", encoding="utf-8") as f:
        f.write(novo)


def _guardar(pasta, local, destino):
    """Compacta a pasta (como agente) em destino, do pmo, e so entao remove a original."""
    with open(destino, "wb") as f:
        pasta("compactar", local, saida=f)
    pasta("remover", local)


def _executar(acao, alvo, conf, gh, raiz_projetos, raiz_laptop, arquivo, lixeira, data, donos, pasta, ajustar,
              pasta_destino=None):
    if acao in ("trazer", "descartar"):
        if not alvo.startswith("destinar:"):
            raise Recusado("so vale para itens a destinar")
        rel = alvo[len("destinar:"):]
        partes = rel.split("/")
        if len(partes) < 2 or any(p in ("", ".", "..") for p in partes):
            raise Recusado(f"pasta invalida (precisa estar dentro de uma pasta do laptop): {alvo}")
        local = os.path.join(raiz_laptop, *partes)
        if acao == "trazer":
            res = pasta("trazer", local)
            if res.startswith("OK"):
                ajustar(alvo, "a_destinar", None)
            return res
        nome = re.sub(r"[^\w.-]", "_", partes[-1])
        _guardar(pasta, local, os.path.join(lixeira, f"destinar-{nome}-{data}.tar.gz"))
        ajustar(alvo, "a_destinar", None)
        return "OK: na lixeira por 30 dias"

    if alvo.count("/") != 1:
        raise Recusado(f"alvo invalido para repositorio: {alvo}")
    dono, repo = alvo.split("/")
    if not re.fullmatch(r"[\w.-]+", dono) or not re.fullmatch(r"[\w.-]+", repo):
        raise Recusado(f"alvo invalido para repositorio: {alvo}")
    if dono.lower() not in {d.lower() for d in donos}:
        raise Recusado(f"dono fora de donos.txt: {dono}")
    local = mapear_locais(raiz_projetos).get(alvo.lower())

    if acao == "clonar":
        if not isinstance(pasta_destino, str) or not NOME.fullmatch(pasta_destino):
            raise Recusado(f"nome de pasta invalido: {pasta_destino!r}")
        if local:
            raise Recusado(f"ja clonado em {local}")
        destino = os.path.join(raiz_projetos, pasta_destino, repo)
        res = pasta("clonar", alvo, destino)
        ajustar(alvo, "projetos", "projetos", {"pasta": destino})
        return res

    if acao == "arquivar":
        gh.arquivar(dono, repo, True)
        if local:
            _guardar(pasta, local, os.path.join(arquivo, f"{dono}__{repo}-{data}.tar.gz"))
        ajustar(alvo, "projetos", "arquivados")
        return "OK: arquivado" + (" (pasta compactada)" if local else "")

    if acao == "restaurar":
        gh.arquivar(dono, repo, False)
        padrao = re.compile(rf"{re.escape(dono)}__{re.escape(repo)}-\d{{8}}-\d{{6}}\.tar\.gz")
        copias = sorted(f for f in os.listdir(arquivo) if padrao.fullmatch(f))
        if copias:
            with open(os.path.join(arquivo, copias[-1]), "rb") as f:
                pasta("extrair", raiz_projetos, entrada=f)
        ajustar(alvo, "arquivados", "projetos")
        return "OK: restaurado" + (" (pasta de volta)" if copias else "")

    if acao == "excluir":
        if alvo.lower() in CLIENTES:
            raise Recusado("repositorio de cliente: so pode ser arquivado")
        if conf != repo:
            raise Recusado("nome digitado nao confere")
        gh.excluir(dono, repo)
        if local:
            _guardar(pasta, local, os.path.join(lixeira, f"{dono}__{repo}-{data}.tar.gz"))
        ajustar(alvo, None, None)
        return "OK: excluido (GitHub guarda 90 dias; copia local 30 dias)"

    raise Recusado(f"acao desconhecida: {acao}")


def main():
    from pmo.github import GitHub
    token = open("/etc/pmo/token", encoding="utf-8").read().strip() or sys.exit("token vazio em /etc/pmo/token")
    donos = open(os.path.join(os.path.dirname(__file__), "donos.txt"), encoding="utf-8").read().split()
    processar("/var/lib/pmo/fila", GitHub(token), "/srv/dev/projetos", "/srv/dev/laptop", "/srv/dev/arquivo",
              "/var/lib/pmo/acoes.log", "/var/lib/pmo/ajustes.json", datetime.now(timezone.utc), donos,
              painel="/srv/dev/state/pmo/painel.json", classes="/var/lib/pmo/classes.json",
              verticais_estado="/var/lib/pmo/verticais.json")


if __name__ == "__main__":
    main()
