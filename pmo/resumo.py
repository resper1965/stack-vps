"""Resumo semanal de projetos esquecidos (segunda 08:00), pelos canais do alertar.sh."""
import json
import subprocess

PAINEL = "/srv/dev/state/pmo/painel.json"
LINK = "http://100.76.167.6:8080"
MAX = 12


def texto(painel):
    esq = sorted((p for p in painel.get("projetos", []) if p.get("esquecido")), key=lambda p: -p.get("dias", 0))
    if not esq:
        return None
    linhas = [f"• {p['nome']} — {p['esquecido']}" for p in esq[:MAX]]
    if len(esq) > MAX:
        linhas.append(f"… e mais {len(esq) - MAX}")
    return f"PMO: {len(esq)} projetos esquecidos", "\n".join(linhas) + f"\n\nAbrir o painel: {LINK}"


def main():
    r = texto(json.load(open(PAINEL, encoding="utf-8")))
    if r:
        subprocess.run(["/usr/local/lib/stack-vps/alertar.sh", r[0], r[1]], check=False)


if __name__ == "__main__":
    main()
