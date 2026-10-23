#!/usr/bin/env python3
"""Gera um projeto novo a partir de templates/<natureza>/ (sem IA): marcadores, STATE.md e .standards.json."""
import argparse
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
TIPO = {"sistema": "app", "agente": "agente", "parecer": "documento"}
NOME_OK = re.compile(r"^[a-z][a-z0-9-]{0,49}$")
MARCADOR = re.compile(r"\{\{[^{}]*\}\}")


def templates_dir():
    # o override existe só para teste; em produção os templates são sempre os do repositório
    if os.environ.get("STACK_TESTE") == "1" and os.environ.get("TEMPLATES_DIR"):
        return Path(os.environ["TEMPLATES_DIR"])
    return ROOT / "templates"


def falha(msg):
    sys.exit(f"ERRO: {msg}")


def copiar(origem, tmp, valores, sobrepor=None):
    for dirpath, dirnames, filenames in os.walk(origem, followlinks=False):
        rel = Path(dirpath).relative_to(origem)
        if sobrepor is None and rel == Path("."):
            dirnames[:] = [d for d in dirnames if d != "_destinos"]  # só entra por destino, abaixo
        for nome in dirnames + filenames:
            if (Path(dirpath) / nome).is_symlink():
                falha(f"template contém symlink: {rel / nome}")
        for d in dirnames:
            (tmp / rel / d).mkdir(parents=True, exist_ok=True)
        for f in filenames:
            if not (Path(dirpath) / f).is_file():
                falha(f"template contém item que não é arquivo comum: {rel / f}")
            alvo = tmp / rel / (f[:-5] if f.endswith(".tmpl") else f)
            dados = (Path(dirpath) / f).read_bytes()
            try:
                texto = dados.decode("utf-8")
            except UnicodeDecodeError:
                final = dados
            else:
                for k, v in valores.items():
                    texto = texto.replace("{{" + k + "}}", v)
                texto = texto.replace("{{abre}}", "@@ABRE@@")  # {{abre}} escreve um "{{" literal (ex.: variável do promptfoo)
                sobra = MARCADOR.search(texto)
                if sobra:
                    falha(f"marcador indefinido {sobra.group(0)} em {rel / f}")
                final = texto.replace("@@ABRE@@", "{{").encode("utf-8")
            if alvo.exists():
                # só um arquivo vindo de outro destino, com conteúdo idêntico, pode ser repetido
                if sobrepor is None or sobrepor.get(alvo) != final:
                    falha(f"arquivo duplicado ou divergente entre destinos: {rel / alvo.name}")
                continue
            alvo.write_bytes(final)
            shutil.copymode(Path(dirpath) / f, alvo)  # preserva o bit de execução
            if sobrepor is not None:
                sobrepor[alvo] = final


def montar(tmp, a, origem, valores):
    # o 35 grava o .standards.json em pasta vazia; os templates entram depois
    cmd = [sys.executable, str(ROOT / "scripts/35-projeto-standards.py"), str(tmp), "--apply"]
    for d in a.destino:
        cmd += ["--provider", d]
    r = subprocess.run(cmd, capture_output=True, text=True)
    if r.returncode:
        falha(f"35-projeto-standards falhou: {r.stderr.strip()}")
    copiar(origem, tmp, valores)
    # _destinos/<perfil>/ entra por cima da raiz; destinos só podem repetir um arquivo (ex.: Dockerfile) se o conteúdo for idêntico
    escritos = {}
    for d in dict.fromkeys(a.destino):
        if (origem / "_destinos" / d).is_dir():
            copiar(origem / "_destinos" / d, tmp, valores, sobrepor=escritos)
    (tmp / "STATE.md").write_text(
        f"# {a.nome}\n\n**Tipo:** {TIPO[a.natureza]}\n**Estágio:** ideia\n"
        "**Próximo passo:** definir o escopo e abrir a primeira tarefa\n",
        encoding="utf-8", newline="\n")


def main():
    ap = argparse.ArgumentParser(description="Cria um projeto novo a partir de templates")
    ap.add_argument("pasta", type=Path)
    ap.add_argument("--natureza", required=True, choices=sorted(TIPO))
    ap.add_argument("--nome", required=True)
    ap.add_argument("--destino", action="append", required=True,
                    help="obrigatório, pelo menos um perfil de standards/profiles.json (repetível)")
    ap.add_argument("--apply", action="store_true", help="grava; sem isso só mostra a prévia")
    a = ap.parse_args()
    if not NOME_OK.fullmatch(a.nome):
        falha("--nome deve ser [a-z0-9-], começar com letra e ter até 50 caracteres")
    perfis = json.loads((ROOT / "standards/profiles.json").read_text(encoding="utf-8"))["profiles"]
    if not set(a.destino) <= set(perfis):
        falha(f"--destino desconhecido: {sorted(set(a.destino) - set(perfis))}")
    origem = templates_dir() / a.natureza
    if not origem.is_dir() or origem.is_symlink():
        falha(f"template ausente: {origem}")
    dest = origem / "_destinos"
    if dest.is_symlink() or any((dest / d).is_symlink() for d in a.destino):
        falha("_destinos do template não pode ser symlink")
    if a.pasta.expanduser().is_symlink():
        falha("a pasta de destino não pode ser um symlink")
    p = a.pasta.expanduser().resolve()
    if p.exists() and (not p.is_dir() or any(p.iterdir())):
        falha("a pasta já existe e não está vazia")
    if not p.parent.is_dir():
        falha(f"pasta-mãe inexistente: {p.parent}")
    valores = {"nome": a.nome, "destino": ", ".join(dict.fromkeys(a.destino))}
    if not a.apply:
        print(f"PREVIEW {p} natureza={a.natureza} tipo={TIPO[a.natureza]} nome={a.nome} destino={','.join(a.destino)}")
        with tempfile.TemporaryDirectory() as t:  # monta de verdade e descarta: a lista é a que o --apply criaria
            montar(Path(t), a, origem, valores)
            for f in sorted(x.relative_to(t).as_posix() for x in Path(t).rglob("*") if x.is_file()):
                print(f"  {f}")
        return
    tmp = Path(tempfile.mkdtemp(prefix=f".{a.nome}.", dir=p.parent))
    umask = os.umask(0)
    os.umask(umask)
    tmp.chmod(0o777 & ~umask)  # mkdtemp cria 0700; a pasta final segue o umask
    try:
        montar(tmp, a, origem, valores)
        tmp.rename(p)  # em POSIX substitui uma pasta vazia já existente
    except BaseException:
        shutil.rmtree(tmp, ignore_errors=True)
        raise
    print(f"CREATED {p} (revise o .standards.json antes de gerar código)")


if __name__ == "__main__":
    main()
