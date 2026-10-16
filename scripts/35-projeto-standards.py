#!/usr/bin/env python3
"""Opt-in adoption of standards for new or existing projects. Never edits application code."""
import argparse
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
PROFILES = json.loads((ROOT / "standards/profiles.json").read_text(encoding="utf-8"))["profiles"]

def config(providers, existing=False):
    return {
        "schema_version": 1,
        "adoption": "existing" if existing else "new",
        "deployment_targets": providers,
        "standards": {
            "authentication": "oidc-server-session",
            "authorization": "deny-by-default",
            "design_system": "ness-design",
            "secrets": "scoped",
            "ci": "local-vps"
        },
        "overrides": {},
        "status": "proposed"
    }

def main():
    parser = argparse.ArgumentParser(description="Adopt stack-vps standards without modifying application code")
    parser.add_argument("project", type=Path, help="existing project directory")
    parser.add_argument("--provider", action="append", choices=sorted(PROFILES), required=True)
    parser.add_argument("--apply", action="store_true", help="create standards.json; default: preview only")
    args = parser.parse_args()
    p = args.project.expanduser().resolve(strict=True)
    if not p.is_dir():
        parser.error("project must be a directory")
    target = p / ".standards.json"
    if target.exists():
        parser.error(f"existing config preserved: {target}")
    result = config(args.provider, existing=(p / ".git").exists())
    rendered = json.dumps(result, indent=2, ensure_ascii=False) + "\n"
    if not args.apply:
        print(f"PREVIEW {target}\n{rendered}")
        return
    # Exclusive create avoids overwrites, even if another process writes meanwhile.
    with target.open("x", encoding="utf-8") as f:
        f.write(rendered)
    print(f"CREATED {target} (proposed; review before adoption)")

if __name__ == "__main__":
    main()
