import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / "scripts/35-projeto-standards.py"

class BootstrapTests(unittest.TestCase):
    def test_new_project(self):
        with tempfile.TemporaryDirectory() as d:
            project = Path(d) / "novo"
            cmd = [sys.executable, str(SCRIPT), str(project), "--provider", "gcp", "--provider", "cloudflare"]
            preview = subprocess.run(cmd, capture_output=True, text=True, check=True)
            self.assertIn("PREVIEW", preview.stdout)
            self.assertFalse(project.exists())
            subprocess.run(cmd + ["--apply"], check=True, capture_output=True, text=True)
            cfg = json.loads((project / ".standards.json").read_text())
            self.assertEqual(cfg["deployment_targets"], ["gcp", "cloudflare"])
            self.assertEqual(cfg["status"], "proposed")
            self.assertNotEqual(subprocess.run(cmd + ["--apply"], capture_output=True).returncode, 0)

    def test_existing_project_rejected(self):
        with tempfile.TemporaryDirectory() as d:
            project = Path(d)
            (project / "README.md").write_text("existing")
            r = subprocess.run([sys.executable, str(SCRIPT), d, "--provider", "gcp", "--apply"], capture_output=True)
            self.assertNotEqual(r.returncode, 0)
            self.assertFalse((project / ".standards.json").exists())

    def test_profiles(self):
        with tempfile.TemporaryDirectory() as d:
            project = Path(d) / "novo"
            ok = subprocess.run([sys.executable, str(SCRIPT), str(project), "--provider", "fora-das-nuvens"], capture_output=True)
            self.assertEqual(ok.returncode, 0)
            for old in ("azure", "local"):
                r = subprocess.run([sys.executable, str(SCRIPT), str(project), "--provider", old], capture_output=True)
                self.assertNotEqual(r.returncode, 0, old)

if __name__ == "__main__":
    unittest.main()
