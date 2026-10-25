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
            self.assertTrue("{{" not in t or a == "promptfoo/promptfooconfig.yaml", a)
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

    def test_sistema_docs_auth_opcional(self):
        for destino in DEPLOY:
            with self.subTest(destino=destino):
                out, _ = self.confere("sistema", destino, {"docs/AUTH.md"})
                texto = (out / "docs/AUTH.md").read_text(encoding="utf-8")
                self.assertIn("@ness/auth", texto)
                self.assertIn(destino, texto)
                self.assertIsNone(SEGREDO.search(texto))
                # o template só documenta: não adiciona a dependência
                pj = json.loads((out / "package.json").read_text())
                self.assertNotIn("@ness/auth", {**pj["dependencies"], **pj["devDependencies"]})

    def test_package_e_dockerfile(self):
        out, _ = self.confere("sistema", "gcp")
        pj = json.loads((out / "package.json").read_text())
        self.assertEqual(pj["type"], "module")
        self.assertIn("test", pj["scripts"])
        self.assertLessEqual({"hono", "vitest", "@types/node"}, set(pj["dependencies"]) | set(pj["devDependencies"]))
        df = (out / "Dockerfile").read_text(encoding="utf-8")
        self.assertIn("USER node", df)
        self.assertNotIn("npm ci", df)

    def test_multi_destino(self):
        d = tempfile.TemporaryDirectory()
        self.addCleanup(d.cleanup)
        out = Path(d.name) / "multi"
        cmd = [sys.executable, str(SCRIPT), str(out), "--natureza", "sistema", "--nome", "multi", "--apply",
               "--destino", "gcp", "--destino", "fora-das-nuvens"]
        r = subprocess.run(cmd, capture_output=True, text=True)
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertTrue((out / "Dockerfile").exists() and (out / "config/deploy.yml").exists())

    def _fake(self, divergir=False, link=False):
        d = tempfile.TemporaryDirectory()
        self.addCleanup(d.cleanup)
        base = Path(d.name)
        t = base / "tpl/sistema/_destinos"
        for x, c in (("gcp", "a"), ("fora-das-nuvens", "b" if divergir else "a")):
            (t / x).mkdir(parents=True)
            (t / x / "Dockerfile").write_text(c)
        if link:
            os.rename(t / "gcp", base / "real")
            os.symlink(base / "real", t / "gcp")
        env = dict(os.environ, STACK_TESTE="1", TEMPLATES_DIR=str(base / "tpl"))
        cmd = [sys.executable, str(SCRIPT), str(base / "o"), "--natureza", "sistema", "--nome", "x", "--apply",
               "--destino", "gcp", "--destino", "fora-das-nuvens"]
        r = subprocess.run(cmd, capture_output=True, text=True, env=env)
        return r, sorted(p.name for p in base.iterdir())

    def test_conteudo_divergente_falha(self):
        r, itens = self._fake(divergir=True)
        self.assertNotEqual(r.returncode, 0)
        self.assertIn("divergente", r.stderr)
        self.assertEqual(itens, ["tpl"])

    def test_destinos_symlink_recusado(self):
        try:
            r, itens = self._fake(link=True)
        except (OSError, NotImplementedError):
            self.skipTest("symlink indisponível")
        self.assertNotEqual(r.returncode, 0)
        self.assertIn("symlink", r.stderr)
        self.assertNotIn("o", itens)

    def test_kamal(self):
        out, _ = self.confere("sistema", "fora-das-nuvens")
        y = (out / "config/deploy.yml").read_text(encoding="utf-8")
        self.assertRegex(y, r"(?m)^image:")
        self.assertRegex(y, r"(?m)^servers:")
        self.assertIn("app_port: 8080", y)
        self.assertIn("healthcheck:", y)

    def test_agente(self):
        out, arqs = self.confere("agente", "gcp")
        self.assertTrue(any(a.startswith("promptfoo/casos/") for a in arqs))
        src = (out / "src/index.ts").read_text(encoding="utf-8")
        self.assertIn("eval", json.loads((out / "package.json").read_text())["scripts"])
        cfg = (out / "promptfoo/promptfooconfig.yaml").read_text(encoding="utf-8")
        prov = re.search(r"file://(\S+\.cjs)", cfg)
        self.assertTrue(prov and (out / "promptfoo" / prov.group(1)).is_file())
        self.assertIn("NINE_ROUTER_API_KEY", src)
        self.assertIn("process.env.MODELO", src)
        self.assertNotIn('"default"', src)
        self.assertRegex(src, r"if \(!modelo\) throw")
        self.assertIn("MODELO", (out / "README.md").read_text(encoding="utf-8"))
        self.assertIn("http://127.0.0.1:20128/v1", src)

    def test_sistema_dockerignore_e_placeholders(self):
        out, _ = self.confere("sistema", "fora-das-nuvens")
        di = (out / ".dockerignore").read_text(encoding="utf-8").split()
        for item in ("node_modules", ".env", ".env.*", ".kamal/secrets", ".git"):
            self.assertIn(item, di)
        self.assertIn("placeholders", (out / "README.md").read_text(encoding="utf-8"))

    def test_parecer_gitignore(self):
        out, _ = self.confere("parecer", "gcp")
        gi = (out / ".gitignore").read_text(encoding="utf-8").split()
        for item in ("*.pdf", "*.docx", "parecer.md", "fontes.md"):
            self.assertIn(item, gi)
        self.assertIn("não vai ao Git", (out / "README.md").read_text(encoding="utf-8").replace("\n", " "))

    def test_parecer(self):
        out, _ = self.confere("parecer", "gcp")
        self.assertIn("citação | verificada | fonte", (out / "fontes.md").read_text(encoding="utf-8"))
        self.assertRegex((out / "Makefile").read_text(encoding="utf-8"), r"(?m)^pdf:")
        self.assertIn("/srv/dev/pareceres/proj-teste", (out / "README.md").read_text(encoding="utf-8"))


if __name__ == "__main__":
    print("nota: sem rede; npm install não é executado, package.json só é validado com json.load")
    unittest.main()
