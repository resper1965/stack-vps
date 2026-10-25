"""Resumo semanal de projetos esquecidos (segunda 08:00), pelos canais do alertar.sh."""
import json
import os
import subprocess

PAINEL = "/srv/dev/state/pmo/painel.json"
MAX = 12


def texto(painel, url=None):
    esq = sorted((p for p in painel.get("projetos", []) if p.get("esquecido")), key=lambda p: -p.get("dias", 0))
    if not esq:
        return None
    linhas = [f"• {p['nome']} — {p['esquecido']}" for p in esq[:MAX]]
    if len(esq) > MAX:
        linhas.append(f"… e mais {len(esq) - MAX}")
    # PMO_URL vem do servidor.env (gravado pelo 34-pmo.sh); sem ela o resumo sai sem link
    return f"PMO: {len(esq)} projetos esquecidos", "\n".join(linhas) + (f"\n\nAbrir o painel: {url}" if url else "")


def main():
    with open(PAINEL, encoding="utf-8") as f:
        r = texto(json.load(f), os.environ.get("PMO_URL"))
    if r:
        subprocess.run(["/usr/local/lib/stack-vps/alertar.sh", r[0], r[1]], check=False)


if __name__ == "__main__":
    main()
