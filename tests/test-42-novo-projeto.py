import json
import os
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / "scripts/42-novo-projeto.py"
sys.path.insert(0, str(ROOT))
from pmo.regras import ler_state  # noqa: E402


class GeradorTests(unittest.TestCase):
    def setUp(self):
        self._d = tempfile.TemporaryDirectory()
        self.d = Path(self._d.name)
        self.tpl = self.d / "tpl"
        (self.tpl / "sistema/src").mkdir(parents=True)
        (self.tpl / "sistema/README.md.tmpl").write_text("# {{nome}}\nDestino: {{destino}}\n")
        (self.tpl / "sistema/src/a.txt").write_text("fixo\n")
        self.out = self.d / "meu-app"

    def tearDown(self):
        self._d.cleanup()

    def run42(self, nome="meu-app", natureza="sistema", destino=("gcp",), pasta=None, apply=True):
        cmd = [sys.executable, str(SCRIPT), str(pasta or self.out), "--natureza", natureza, "--nome", nome]
        for x in destino:
            cmd += ["--destino", x]
        cmd += ["--apply"] if apply else []
        env = dict(os.environ, STACK_TESTE="1", TEMPLATES_DIR=str(self.tpl))
        return subprocess.run(cmd, capture_output=True, text=True, env=env)

    def sobras(self):
        return [p.name for p in self.d.iterdir() if p.name != "tpl"]

    def test_previa(self):
        r = self.run42(apply=False)
        self.assertEqual(r.returncode, 0)
        self.assertIn("PREVIEW", r.stdout)
        self.assertEqual(self.sobras(), [])

    def test_apply(self):
        r = self.run42(destino=("gcp", "cloudflare"))
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertEqual((self.out / "README.md").read_text(), "# meu-app\nDestino: gcp, cloudflare\n")
        self.assertTrue((self.out / "src/a.txt").exists())
        st = ler_state((self.out / "STATE.md").read_text(encoding="utf-8"))
        self.assertEqual((st["tipo"], st["estagio"]), ("app", "ideia"))
        self.assertTrue(st["proximo"])
        cfg = json.loads((self.out / ".standards.json").read_text())
        self.assertEqual(cfg["deployment_targets"], ["gcp", "cloudflare"])
        self.assertEqual(self.sobras(), ["meu-app"])

    def test_tipo_por_natureza(self):
        for nat, tipo in (("agente", "agente"), ("parecer", "documento")):
            (self.tpl / nat).mkdir()
            out = self.d / nat
            r = self.run42(natureza=nat, pasta=out)
            self.assertEqual(r.returncode, 0, r.stderr)
            self.assertEqual(ler_state((out / "STATE.md").read_text(encoding="utf-8"))["tipo"], tipo)

    def test_pasta_existente(self):
        self.out.mkdir()
        (self.out / "x").write_text("meu")
        self.assertNotEqual(self.run42().returncode, 0)
        self.assertEqual(os.listdir(self.out), ["x"])

    def test_pasta_vazia_ok(self):
        self.out.mkdir()
        self.assertEqual(self.run42().returncode, 0)
        self.assertTrue((self.out / "STATE.md").exists())

    def test_nome_invalido(self):
        for nome in ("a/b", "..", "a b", "Abc", "1abc", "", "-x"):
            self.assertNotEqual(self.run42(nome=nome).returncode, 0, nome)
        self.assertEqual(self.sobras(), [])

    def test_desconhecidos(self):
        self.assertNotEqual(self.run42(destino=("azure",)).returncode, 0)
        self.assertNotEqual(self.run42(natureza="foo").returncode, 0)
        self.assertEqual(self.sobras(), [])

    def test_marcador_indefinido(self):
        (self.tpl / "sistema/src/b.txt.tmpl").write_text("{{segredo}}\n")
        r = self.run42()
        self.assertNotEqual(r.returncode, 0)
        self.assertIn("segredo", r.stderr)
        self.assertEqual(self.sobras(), [])

    def test_symlink_no_template(self):
        try:
            os.symlink(self.d, self.tpl / "sistema/link")
        except (OSError, NotImplementedError):
            self.skipTest("symlink indisponível")
        self.assertNotEqual(self.run42().returncode, 0)
        self.assertEqual(self.sobras(), [])

    def test_override_ignorado_sem_stack_teste(self):
        env = {k: v for k, v in os.environ.items() if k != "STACK_TESTE"}
        env["TEMPLATES_DIR"] = str(self.tpl)
        cmd = [sys.executable, str(SCRIPT), str(self.out), "--natureza", "sistema", "--nome", "x",
               "--destino", "gcp", "--apply"]
        r = subprocess.run(cmd, capture_output=True, text=True, env=env)
        self.assertFalse((self.out / "src").exists())  # templates do teste não foram usados


if __name__ == "__main__":
    unittest.main()
