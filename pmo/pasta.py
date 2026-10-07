"""Operacoes de pasta do executor do PMO, rodando COMO agente (sudo -u agente /usr/local/bin/pmo-pasta).

O executor (usuario pmo) nunca toca nas arvores do agente: pede aqui. Rodando como agente, um atalho
plantado nessas arvores so alcanca o que o proprio agente ja podia mexer.

  pmo-pasta compactar <pasta>   tar.gz no stdout (caminhos relativos a raiz)
  pmo-pasta remover <pasta>
  pmo-pasta extrair <raiz>      tar.gz no stdin
  pmo-pasta trazer <pasta>      vira repositorio privado pelo 20-laptop-github.sh
"""
import os
import shutil
import subprocess
import sys
import tarfile
import tempfile

RAIZES = ("/srv/dev/projetos", "/srv/dev/laptop")


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


def executar(args, entrada=None, saida=None, raizes=RAIZES):
    if len(args) != 2:
        raise Recusado("uso: compactar|remover|trazer <pasta> ou extrair <raiz>")
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
