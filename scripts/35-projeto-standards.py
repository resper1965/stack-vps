#!/usr/bin/env python3
"""Create standards selection exclusively for new, empty project directories."""
import argparse
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
PROFILES = json.loads((ROOT / "standards/profiles.json").read_text(encoding="utf-8"))["profiles"]

def main():
    parser = argparse.ArgumentParser(description="Choose deployment standards for a new project")
    parser.add_argument("project", type=Path, help="new empty project directory")
    parser.add_argument("--provider", action="append", choices=sorted(PROFILES), required=True)
    parser.add_argument("--apply", action="store_true", help="write the new selection; default preview")
    args = parser.parse_args()
    p = args.project.expanduser().resolve()
    if p.exists() and (not p.is_dir() or any(p.iterdir())):
        parser.error("only a new or empty directory is supported; existing projects stay unchanged")
    target = p / ".standards.json"
    result = {
        "schema_version": 1,
        "deployment_targets": list(dict.fromkeys(args.provider)),
        "standards": {"authentication": "oidc-server-session",
                      "authorization": "deny-by-default", "design_system": "ness-design",
                      "secrets": "scoped", "ci": "local-vps"},
        "overrides": {}, "status": "proposed"
    }
    rendered = json.dumps(result, indent=2, ensure_ascii=False) + "\n"
    if not args.apply:
        print(f"PREVIEW {target}\n{rendered}")
        return
    p.mkdir(parents=True, exist_ok=True)
    with target.open("x", encoding="utf-8") as f:
        f.write(rendered)
    print(f"CREATED {target} (review before generating application code)")

if __name__ == "__main__":
    main()
