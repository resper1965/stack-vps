import importlib.util
import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / "scripts/35-projeto-standards.py"

class BootstrapTests(unittest.TestCase):
    def test_preview_and_exclusive_creation(self):
        with tempfile.TemporaryDirectory() as d:
            project = Path(d)
            cmd = [sys.executable, str(SCRIPT), d, "--provider", "gcp", "--provider", "cloudflare"]
            preview = subprocess.run(cmd, capture_output=True, text=True, check=True)
            self.assertIn("PREVIEW", preview.stdout)
            self.assertFalse((project / ".standards.json").exists())
            subprocess.run(cmd + ["--apply"], check=True, capture_output=True, text=True)
            cfg = json.loads((project / ".standards.json").read_text())
            self.assertEqual(cfg["deployment_targets"], ["gcp", "cloudflare"])
            self.assertEqual(cfg["status"], "proposed")
            repeated = subprocess.run(cmd + ["--apply"], capture_output=True, text=True)
            self.assertNotEqual(repeated.returncode, 0)

if __name__ == "__main__":
    unittest.main()
