"""Gera cada natureza/destino num diretório temporário e confere o resultado.
Sem rede: package.json só passa por json.load; npm install NÃO é executado aqui."""
import json
import os
import re
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / "scripts/42-novo-projeto.py"
sys.path.insert(0, str(ROOT))
from pmo.regras import ler_state  # noqa: E402

SEGREDO = re.compile(r"sk-[A-Za-z0-9]|AKIA[0-9A-Z]|-----BEGIN")
DEPLOY = {"gcp": {"Dockerfile"}, "vercel": {"vercel.json"}, "cloudflare": {"wrangler.jsonc"},
          "fora-das-nuvens": {"Dockerfile", "config/deploy.yml"}}
TODOS = {"Dockerfile", "vercel.json", "wrangler.jsonc", "config/deploy.yml"}
ESPERADO = {
    "sistema": {"package.json", "src/index.ts", "README.md", ".standards.json", "STATE.md"},
    "agente": {"package.json", "src/index.ts", "promptfoo/promptfooconfig.yaml", "README.md", ".standards.json", "STATE.md"},
    "parecer": {"parecer.md", "fontes.md", "typst/parecer.typ", "Makefile", ".gitignore", "README.md", ".standards.json", "STATE.md"},
}
TIPO = {"sistema": "app", "agente": "agente", "parecer": "documento"}


class TemplatesTests(unittest.TestCase):
    def gerar(self, natureza, destino):
        d = tempfile.TemporaryDirectory()
        self.addCleanup(d.cleanup)
        out = Path(d.name) / "proj-teste"
        r = subprocess.run([sys.executable, str(SCRIPT), str(out), "--natureza", natureza, "--nome", "proj-teste",
                            "--destino", destino, "--apply"], capture_output=True, text=True)
        self.assertEqual(r.returncode, 0, r.stderr)
        return out, {p.relative_to(out).as_posix() for p in out.rglob("*") if p.is_file()}

    def confere(self, natureza, destino, extra=()):
        out, arqs = self.gerar(natureza, destino)
        self.assertLessEqual(ESPERADO[natureza] | set(extra), arqs)
        self.assertFalse([a for a in arqs if a.startswith(".github") or "_destinos" in a], arqs)
        for a in arqs:
            t = (out / a).read_text(encoding="utf-8")
            self.assertNotIn("{{", t, a)
            self.assertIsNone(SEGREDO.search(t), a)
        self.assertEqual(ler_state((out / "STATE.md").read_text(encoding="utf-8"))["tipo"], TIPO[natureza])
        if (out / "package.json").exists():
            self.assertEqual(json.loads((out / "package.json").read_text())["name"], "proj-teste")
        return out, arqs

    def test_sistema_por_destino(self):
        for destino, deploy in DEPLOY.items():
            with self.subTest(destino=destino):
                _, arqs = self.confere("sistema", destino, deploy)
                self.assertEqual(arqs & TODOS, deploy)
                self.assertTrue(any(a.startswith("src/") and a.endswith(".test.ts") for a in arqs))

    def test_kamal(self):
        out, _ = self.confere("sistema", "fora-das-nuvens")
        y = (out / "config/deploy.yml").read_text(encoding="utf-8")
        self.assertRegex(y, r"(?m)^image:")
        self.assertRegex(y, r"(?m)^servers:")

    def test_agente(self):
        out, arqs = self.confere("agente", "gcp")
        self.assertTrue(any(a.startswith("promptfoo/casos/") for a in arqs))
        src = (out / "src/index.ts").read_text(encoding="utf-8")
        self.assertIn("NINE_ROUTER_API_KEY", src)
        self.assertIn("http://127.0.0.1:20128/v1", src)

    def test_parecer(self):
        out, _ = self.confere("parecer", "gcp")
        self.assertIn("citação | verificada | fonte", (out / "fontes.md").read_text(encoding="utf-8"))
        self.assertRegex((out / "Makefile").read_text(encoding="utf-8"), r"(?m)^pdf:")
        self.assertIn("/srv/dev/pareceres/proj-teste", (out / "README.md").read_text(encoding="utf-8"))


if __name__ == "__main__":
    print("nota: sem rede; npm install não é executado, package.json só é validado com json.load")
    unittest.main()
