"""Executor das acoes do painel (roda como root, pelo timer de 1 minuto).

Le os pedidos da fila, executa, registra no log e atualiza o painel.json. Protecoes:
- excluir exige o nome do repositorio digitado; organizacao de cliente (nessenergy) nunca e excluida;
- mesmo pedido repetido em 10 minutos executa uma vez;
- "a destinar" so age dentro da raiz do laptop;
- nunca roda git nas arvores do agente: so API do GitHub e mover/compactar pastas.
"""
import json
import os
import shutil
import subprocess
import sys
import tarfile
import time
from datetime import datetime, timezone

from pmo.coleta import mapear_locais

CLIENTES = {"nessenergy"}
JANELA_DUPLICADO = 600
DIAS_LIXEIRA = 30


class Recusado(Exception):
    pass


def _dentro(base, caminho):
    base, caminho = os.path.realpath(base), os.path.realpath(caminho)
    return caminho == base or caminho.startswith(base + os.sep)


def _repo(alvo):
    if alvo.startswith("destinar:") or alvo.count("/") != 1:
        raise Recusado(f"alvo invalido para repositorio: {alvo}")
    return alvo.split("/")


def _painel_mover(painel, alvo, de, para, item=None):
    try:
        d = json.load(open(painel, encoding="utf-8"))
    except (OSError, ValueError):
        return
    achados = [x for x in d.get(de, []) if x["id"] == alvo]
    d[de] = [x for x in d.get(de, []) if x["id"] != alvo]
    if para:
        for x in achados or ([item] if item else []):
            x["arquivado"] = para == "arquivados"
            d.setdefault(para, []).append(x)
    tmp = painel + ".tmp"
    json.dump(d, open(tmp, "w", encoding="utf-8"), ensure_ascii=False, indent=1)
    os.replace(tmp, painel)


def processar(fila, gh, raiz_projetos, raiz_laptop, arquivo, log, painel, agora, trazer=None):
    feitos = os.path.join(fila, "feitos")
    lixeira = os.path.join(arquivo, "excluidos")
    for d in (feitos, arquivo, lixeira):
        os.makedirs(d, exist_ok=True)
    data = agora.strftime("%Y%m%d-%H%M%S")

    def registrar(acao, alvo, resultado):
        with open(log, "a", encoding="utf-8") as f:
            f.write(f"{agora.isoformat()}\t{acao}\t{alvo}\t{resultado}\n")

    recentes = {}
    for nome in os.listdir(feitos):
        try:
            p = json.load(open(os.path.join(feitos, nome), encoding="utf-8"))
            recentes[(p["acao"], p["alvo"])] = max(recentes.get((p["acao"], p["alvo"]), 0), p.get("pedido_em", 0))
        except (OSError, ValueError, KeyError):
            pass

    for nome in sorted(n for n in os.listdir(fila) if n.endswith(".json") and not n.startswith(".")):
        caminho = os.path.join(fila, nome)
        try:
            ped = json.load(open(caminho, encoding="utf-8"))
            acao, alvo, conf = ped["acao"], ped["alvo"], ped.get("confirmacao")
        except (OSError, ValueError, KeyError):
            os.replace(caminho, os.path.join(feitos, nome))
            continue
        chave = (acao, alvo)
        if ped.get("pedido_em", 0) - recentes.get(chave, -1e18) < JANELA_DUPLICADO:
            resultado = "duplicado (ignorado)"
        else:
            try:
                resultado = _executar(acao, alvo, conf, gh, raiz_projetos, raiz_laptop, arquivo, lixeira, painel, data, trazer)
            except Recusado as e:
                resultado = f"recusado: {e}"
            except Exception as e:  # noqa: BLE001 — falha de uma acao nao para a fila
                resultado = f"erro: {e}"
            recentes[chave] = ped.get("pedido_em", 0)
        registrar(acao, alvo, resultado)
        ped["resultado"] = resultado
        json.dump(ped, open(os.path.join(feitos, nome), "w", encoding="utf-8"), ensure_ascii=False)
        os.remove(caminho)

    limite = agora.timestamp() - DIAS_LIXEIRA * 86400
    for n in os.listdir(lixeira):
        p = os.path.join(lixeira, n)
        if os.path.getmtime(p) < limite:
            shutil.rmtree(p) if os.path.isdir(p) else os.remove(p)


def _executar(acao, alvo, conf, gh, raiz_projetos, raiz_laptop, arquivo, lixeira, painel, data, trazer):
    if acao == "reanalisar":
        d = os.path.join(os.path.dirname(painel), "reanalisar")
        os.makedirs(d, exist_ok=True)
        open(os.path.join(d, alvo.replace("/", "__")), "w").close()
        return "OK: na fila da proxima analise"

    if acao in ("trazer", "descartar"):
        if not alvo.startswith("destinar:"):
            raise Recusado("so vale para itens a destinar")
        pasta = os.path.join(raiz_laptop, alvo[len("destinar:"):])
        if not _dentro(raiz_laptop, pasta) or not os.path.isdir(pasta):
            raise Recusado(f"pasta fora do laptop ou inexistente: {alvo}")
        if acao == "trazer":
            res = (trazer or _trazer)(pasta)
            if res.startswith("OK"):
                _painel_mover(painel, alvo, "a_destinar", None)
            return res
        shutil.move(pasta, os.path.join(lixeira, f"destinar-{os.path.basename(pasta)}-{data}"))
        _painel_mover(painel, alvo, "a_destinar", None)
        return "OK: na lixeira por 30 dias"

    dono, repo = _repo(alvo)
    local = mapear_locais(raiz_projetos).get(alvo.lower())

    if acao == "arquivar":
        gh.arquivar(dono, repo, True)
        if local:
            tgz = os.path.join(arquivo, f"{dono}__{repo}-{data}.tar.gz")
            with tarfile.open(tgz, "w:gz") as t:
                t.add(local, arcname=os.path.relpath(local, raiz_projetos))
            shutil.rmtree(local)
        _painel_mover(painel, alvo, "projetos", "arquivados")
        return "OK: arquivado" + (" (pasta compactada)" if local else "")

    if acao == "restaurar":
        gh.arquivar(dono, repo, False)
        copias = sorted(f for f in os.listdir(arquivo) if f.startswith(f"{dono}__{repo}-") and f.endswith(".tar.gz"))
        if copias:
            with tarfile.open(os.path.join(arquivo, copias[-1])) as t:
                for m in t.getmembers():
                    if not _dentro(raiz_projetos, os.path.join(raiz_projetos, m.name)):
                        raise Recusado("arquivo compactado com caminho fora da raiz")
                t.extractall(raiz_projetos, filter="tar")
        _painel_mover(painel, alvo, "arquivados", "projetos")
        return "OK: restaurado" + (" (pasta de volta)" if copias else "")

    if acao == "excluir":
        if dono.lower() in CLIENTES:
            raise Recusado("repositorio de cliente: so pode ser arquivado")
        if conf != repo:
            raise Recusado("nome digitado nao confere")
        gh.excluir(dono, repo)
        if local:
            shutil.move(local, os.path.join(lixeira, f"{dono}__{repo}-{data}"))
        _painel_mover(painel, alvo, "projetos", None)
        _painel_mover(painel, alvo, "arquivados", None)
        return "OK: excluido (GitHub guarda 90 dias; copia local 30 dias)"

    raise Recusado(f"acao desconhecida: {acao}")


def _trazer(pasta):
    """Vira repositorio privado em resper1965 pelo 20-laptop-github.sh, como agente (as mesmas travas)."""
    nome = "".join(c if c.isalnum() or c in "-_." else "-" for c in os.path.basename(pasta)).strip("-").lower()
    tsv = f"/tmp/pmo-trazer-{int(time.time())}.tsv"
    with open(tsv, "w", encoding="utf-8") as f:
        f.write("origem\tcaminho\tdono\trepo\tarvore\tacao\n")
        f.write(f"vps\t{pasta}\tresper1965\t{nome}\tapps\tcriar\n")
    os.chmod(tsv, 0o644)
    r = subprocess.run(["sudo", "-u", "agente", "-H", "bash", "-c",
                        f"cd ~ && set -a && . /srv/dev/secrets/agente.env && set +a && "
                        f"bash /opt/stack-vps/scripts/20-laptop-github.sh {tsv}"],
                       capture_output=True, text=True, timeout=1800)
    linha = next((x for x in r.stdout.splitlines() if x.startswith(("OK", "PENDENTE"))), r.stderr.strip()[-200:])
    return ("OK: " if linha.startswith("OK") else "erro: ") + linha


def main():
    from pmo.github import GitHub
    token = os.environ.get("GITHUB_TOKEN") or sys.exit("falta GITHUB_TOKEN")
    processar("/srv/dev/state/pmo/fila", GitHub(token), "/srv/dev/projetos", "/srv/dev/laptop",
              "/srv/dev/arquivo", "/srv/dev/state/pmo/acoes.log", "/srv/dev/state/pmo/painel.json",
              datetime.now(timezone.utc))


if __name__ == "__main__":
    main()
