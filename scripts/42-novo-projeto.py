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


def copiar(origem, tmp, valores, sobrepor=False):
    for dirpath, dirnames, filenames in os.walk(origem, followlinks=False):
        rel = Path(dirpath).relative_to(origem)
        if not sobrepor and rel == Path("."):
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
            if alvo.exists() and not sobrepor:
                falha(f"arquivo duplicado no template: {rel / alvo.name}")
            dados = (Path(dirpath) / f).read_bytes()
            try:
                texto = dados.decode("utf-8")
            except UnicodeDecodeError:
                alvo.write_bytes(dados)
                shutil.copymode(Path(dirpath) / f, alvo)
                continue
            for k, v in valores.items():
                texto = texto.replace("{{" + k + "}}", v)
            sobra = MARCADOR.search(texto)
            if sobra:
                falha(f"marcador indefinido {sobra.group(0)} em {rel / f}")
            alvo.write_text(texto, encoding="utf-8", newline="\n")
            shutil.copymode(Path(dirpath) / f, alvo)  # preserva o bit de execução


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
    if a.pasta.expanduser().is_symlink():
        falha("a pasta de destino não pode ser um symlink")
    p = a.pasta.expanduser().resolve()
    if p.exists() and (not p.is_dir() or any(p.iterdir())):
        falha("a pasta já existe e não está vazia")
    if not p.parent.is_dir():
        falha(f"pasta-mãe inexistente: {p.parent}")
    if not a.apply:
        print(f"PREVIEW {p} natureza={a.natureza} tipo={TIPO[a.natureza]} nome={a.nome} destino={','.join(a.destino)}")
        return
    valores = {"nome": a.nome, "destino": ", ".join(dict.fromkeys(a.destino))}
    tmp = Path(tempfile.mkdtemp(prefix=f".{a.nome}.", dir=p.parent))
    umask = os.umask(0)
    os.umask(umask)
    tmp.chmod(0o777 & ~umask)  # mkdtemp cria 0700; a pasta final segue o umask
    try:
        # o 35 grava o .standards.json em pasta vazia; os templates entram depois
        cmd = [sys.executable, str(ROOT / "scripts/35-projeto-standards.py"), str(tmp), "--apply"]
        for d in a.destino:
            cmd += ["--provider", d]
        r = subprocess.run(cmd, capture_output=True, text=True)
        if r.returncode:
            falha(f"35-projeto-standards falhou: {r.stderr.strip()}")
        copiar(origem, tmp, valores)
        # _destinos/<perfil>/ entra por cima da raiz; destinos que repetem um arquivo (ex.: Dockerfile) o sobrescrevem
        for d in dict.fromkeys(a.destino):
            if (origem / "_destinos" / d).is_dir():
                copiar(origem / "_destinos" / d, tmp, valores, sobrepor=True)
        (tmp / "STATE.md").write_text(
            f"# {a.nome}\n\n**Tipo:** {TIPO[a.natureza]}\n**Estágio:** ideia\n"
            "**Próximo passo:** definir o escopo e abrir a primeira tarefa\n",
            encoding="utf-8", newline="\n")
        tmp.rename(p)  # em POSIX substitui uma pasta vazia já existente
    except BaseException:
        shutil.rmtree(tmp, ignore_errors=True)
        raise
    print(f"CREATED {p} (revise o .standards.json antes de gerar código)")


if __name__ == "__main__":
    main()
