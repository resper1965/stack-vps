"""Operacoes de pasta do executor do PMO, rodando COMO agente (sudo -u agente /usr/local/bin/pmo-pasta).

O executor (usuario pmo) nunca toca nas arvores do agente: pede aqui. Rodando como agente, um atalho
plantado nessas arvores so alcanca o que o proprio agente ja podia mexer.

  pmo-pasta compactar <pasta>   tar.gz no stdout (caminhos relativos a raiz)
  pmo-pasta remover <pasta>
  pmo-pasta extrair <raiz>      tar.gz no stdin
  pmo-pasta trazer <pasta>      vira repositorio privado pelo 20-laptop-github.sh
  pmo-pasta clonar <dono/repo> <destino>   destino = <projetos>/<pasta>/<repo>, ainda inexistente
  pmo-pasta verticais -         mapa JSON no stdin; refaz os atalhos /srv/dev/verticais/<empresa>/<area>/<projeto>
"""
import json
import os
import re
import shutil
import subprocess
import sys
import tarfile
import tempfile

RAIZES = ("/srv/dev/projetos", "/srv/dev/laptop")
BASE_GIT = "https://github.com/"
VERTICAIS = "/srv/dev/verticais"
NOME = re.compile(r"[\w][\w .-]{0,59}")  # empresa, area, pasta: um nivel, sem / e sem comecar por . ou -


class Recusado(Exception):
    pass


def _validar(caminho, raizes):
    """Pasta real estritamente dentro de uma raiz, a pelo menos 2 niveis dela. Devolve (real, raiz)."""
    real = os.path.realpath(caminho)
    for r in map(os.path.realpath, raizes):
        rel = os.path.relpath(real, r)
        partes = rel.split(os.sep)
        if ".." not in partes and rel != "." and len(partes) >= 2:
            if not os.path.isdir(real):
                raise Recusado(f"pasta inexistente: {caminho}")
            return real, r
    raise Recusado(f"pasta fora das raizes ou rasa demais: {caminho}")


def executar(args, entrada=None, saida=None, raizes=RAIZES, base_git=BASE_GIT, verticais=VERTICAIS):
    if args[:1] == ["clonar"] and len(args) == 3:
        return _clonar(args[1], args[2], raizes[0], base_git)
    if args == ["verticais", "-"]:
        return _verticais(json.load(entrada), raizes[0], verticais)
    if len(args) != 2:
        raise Recusado("uso: compactar|remover|trazer <pasta>, extrair <raiz>, clonar <dono/repo> <destino> ou verticais -")
    cmd, alvo = args
    if cmd == "extrair":
        if os.path.realpath(alvo) not in map(os.path.realpath, raizes):
            raise Recusado(f"raiz desconhecida: {alvo}")
        with tarfile.open(fileobj=entrada, mode="r|gz") as t:
            t.extractall(alvo, filter="data")  # data: recusa caminho absoluto, .. e atalho para fora
        return "OK"
    if cmd not in ("compactar", "remover", "trazer"):
        raise Recusado(f"comando desconhecido: {cmd}")
    real, raiz = _validar(alvo, raizes)
    if cmd == "compactar":
        with tarfile.open(fileobj=saida, mode="w|gz") as t:
            t.add(real, arcname=os.path.relpath(real, raiz))
    elif cmd == "remover":
        shutil.rmtree(real)
    else:
        return _trazer(real)
    return "OK"


def _clonar(alvo, destino, projetos, base_git):
    if not re.fullmatch(r"[\w.-]+/[\w.-]+", alvo) or ".." in alvo or alvo.startswith(("-", ".")):
        raise Recusado(f"repositorio invalido: {alvo}")
    raiz = os.path.realpath(projetos)
    pai = os.path.realpath(os.path.dirname(destino))
    if (os.path.dirname(pai) != raiz or not NOME.fullmatch(os.path.basename(pai))
            or not NOME.fullmatch(os.path.basename(destino))):
        raise Recusado(f"destino precisa ser <projetos>/<pasta>/<repo>: {destino}")
    final = os.path.join(pai, os.path.basename(destino))
    if os.path.lexists(final):
        raise Recusado(f"destino ja existe: {final}")
    os.makedirs(pai, exist_ok=True)
    r = subprocess.run(["git", "-c", "credential.https://github.com.helper=stack", "clone", "-q", "--",
                        f"{base_git}{alvo}.git", final], capture_output=True, text=True, timeout=1800)
    if r.returncode:
        raise RuntimeError(f"git clone falhou: {r.stderr.strip()[-200:]}")
    return f"OK: clonado em {final}"


def _verticais(mapa, projetos, base):
    """Refaz do zero os atalhos por empresa/area; item invalido e ignorado, nunca vira atalho."""
    os.makedirs(base, exist_ok=True)
    for raiz, dirs, arqs in os.walk(base, topdown=False):
        for n in arqs + dirs:
            c = os.path.join(raiz, n)
            if os.path.islink(c):
                os.remove(c)
            elif os.path.isdir(c) and not os.listdir(c):
                os.rmdir(c)
    feitos = 0
    for item in mapa:
        empresa, area = item.get("empresa") or "", item.get("area") or "geral"
        if not (NOME.fullmatch(empresa) and NOME.fullmatch(area)):
            continue
        try:
            real, _ = _validar(item.get("pasta") or "", (projetos,))
        except Recusado:
            continue
        d = os.path.join(base, empresa, area)
        os.makedirs(d, exist_ok=True)
        link, n = os.path.join(d, os.path.basename(real)), 2
        while os.path.lexists(link):
            link, n = os.path.join(d, f"{os.path.basename(real)}-{n}"), n + 1
        os.symlink(real, link)
        feitos += 1
    return f"OK: {feitos} atalhos"


def _trazer(pasta):
    nome = "".join(c if c.isalnum() or c in "-_." else "-" for c in os.path.basename(pasta)).strip("-").lower()
    with tempfile.NamedTemporaryFile("w", suffix=".tsv", delete=False, encoding="utf-8") as f:
        f.write("origem\tcaminho\tdono\trepo\tarvore\tacao\n")
        f.write(f"vps\t{pasta}\tresper1965\t{nome}\tapps\tcriar\n")
    try:
        r = subprocess.run(["bash", "-c", 'cd ~ && set -a && . /srv/dev/secrets/agente.env && set +a && '
                            'exec bash /opt/stack-vps/scripts/20-laptop-github.sh "$1"', "_", f.name],
                           capture_output=True, text=True, timeout=1800)
    finally:
        os.remove(f.name)
    linha = next((x for x in r.stdout.splitlines() if x.startswith(("OK", "PENDENTE"))), r.stderr.strip()[-200:])
    return ("OK: " if linha.startswith("OK") else "erro: ") + linha


def main():
    try:
        print(executar(sys.argv[1:], sys.stdin.buffer, sys.stdout.buffer), file=sys.stderr)
    except Recusado as e:
        sys.exit(f"recusado: {e}")


if __name__ == "__main__":
    main()
