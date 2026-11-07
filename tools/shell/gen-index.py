#!/usr/bin/env python3
"""Write shell/widgets/index.json from every widget's manifest (ADR 0068).

The shell cannot list a directory cheaply at start, so the index is
generated here and committed; `--check` fails when it is stale. The rules
match shell/Commons/ManifestModel.js.

Usage: tools/shell/gen-index.py [--shell DIR] [--check]
"""

import argparse
import json
import re
import sys
from pathlib import Path

API = 0
ID = re.compile(r"^subcult\.[a-z0-9-]+$")
HOST = re.compile(r"^[a-z0-9]([a-z0-9-]*[a-z0-9])?(\.[a-z0-9]([a-z0-9-]*[a-z0-9])?)+$")


def validate(m) -> list[str]:
    if not isinstance(m, dict):
        return ["manifest is not an object"]
    errors = []
    if m.get("api") != API:
        errors.append(f"api is {m.get('api')}, the shell speaks {API}")
    if m.get("kind") not in ("bar-widget", "service"):
        errors.append(f"kind must be bar-widget or service, not {m.get('kind')}")
    if not ID.match(str(m.get("id"))):
        errors.append(f"id {m.get('id')} must look like subcult.<name>")
    cost = m.get("cost") or {}
    for t in cost.get("timers") or []:
        ok = isinstance(t, dict) and isinstance(t.get("name"), str) and \
            all(isinstance(t.get(k), (int, float)) and t.get(k) > 0 for k in ("ac", "battery"))
        if not ok:
            errors.append(f"timer {t.get('name') if isinstance(t, dict) else t} needs a name and positive ac and battery seconds")
    for h in cost.get("network") or []:
        if not HOST.match(str(h)):
            errors.append(f"network host {h} is not a hostname")
    return errors


def build(shell: Path) -> tuple[dict, list[str]]:
    widgets, errors = {}, []
    for manifest_path in sorted((shell / "widgets").glob("*/manifest.json")):
        folder = manifest_path.parent.name
        try:
            m = json.loads(manifest_path.read_text())
        except json.JSONDecodeError as e:
            errors.append(f"{folder}: manifest is not JSON ({e})")
            continue
        errs = validate(m)
        if not (manifest_path.parent / "Widget.qml").exists():
            errs.append("no Widget.qml")
        if not errs and m["id"] in widgets:
            errs.append(f"id {m['id']} is also used by {widgets[m['id']]['dir']}")
        errors += [f"{folder}: {e}" for e in errs]
        if not errs:
            widgets[m["id"]] = {"dir": folder, "manifest": m}
    index = {"api": API, "widgets": dict(sorted(widgets.items()))}
    return index, errors


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--shell", type=Path, default=Path(__file__).resolve().parents[2] / "shell")
    ap.add_argument("--check", action="store_true", help="fail if index.json is missing or stale")
    args = ap.parse_args()

    index, errors = build(args.shell)
    for e in errors:
        print(f"gen-index: {e}", file=sys.stderr)
    if errors:
        return 1
    text = json.dumps(index, indent=2, sort_keys=False) + "\n"
    target = args.shell / "widgets" / "index.json"
    if args.check:
        if not target.exists() or target.read_text() != text:
            print(f"gen-index: {target} is stale; run tools/shell/gen-index.py", file=sys.stderr)
            return 1
        return 0
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text(text)
    return 0


if __name__ == "__main__":
    sys.exit(main())
