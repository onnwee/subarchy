#!/usr/bin/env python3
"""Install the vault's pinned Obsidian community plugins.

Downloads each release asset listed in tools/obsidian/plugins.json from
GitHub, checks its SHA-256, and writes it to .obsidian/plugins/<id>/. Plugin
code is not committed, to keep third-party code out of the repository, so
run this once after cloning, then reload Obsidian.

Usage: python3 tools/obsidian/install-plugins.py [--check]
  --check  verify installed files against the pins without downloading
"""

from __future__ import annotations

import argparse
import hashlib
import json
import sys
import urllib.request
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
PINS = Path(__file__).with_name("plugins.json")
DEST = REPO / ".obsidian/plugins"


def sha256(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--check", action="store_true")
    args = ap.parse_args()

    failed = 0
    for plugin in json.loads(PINS.read_text())["plugins"]:
        pid, repo, version = plugin["id"], plugin["repo"], plugin["version"]
        target = DEST / pid
        for name, expected in plugin["files"].items():
            path = target / name
            if path.exists() and sha256(path.read_bytes()) == expected:
                print(f"ok       {pid}/{name}")
                continue
            if args.check:
                state = "modified" if path.exists() else "missing"
                print(f"{state:8} {pid}/{name}")
                failed += 1
                continue
            url = f"https://github.com/{repo}/releases/download/{version}/{name}"
            with urllib.request.urlopen(url, timeout=60) as resp:
                data = resp.read()
            if sha256(data) != expected:
                print(f"MISMATCH {pid}/{name} from {url}", file=sys.stderr)
                failed += 1
                continue
            target.mkdir(parents=True, exist_ok=True)
            path.write_bytes(data)
            print(f"wrote    {pid}/{name} ({version})")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
