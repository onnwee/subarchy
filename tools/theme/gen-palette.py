#!/usr/bin/env python3
"""Write the shell's palette (default/theme/palette.json) from the Theme
Tender theme (default/theme/subcult-minimal.json), or check that the two
agree (ADR 0037). The theme file is the source: Theme Tender's palette-file
format, with the `theme` envelope. The shell's file keeps the envelope it
reads (name, appearance, colors) and the same colours."""
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
THEME = ROOT / "default/theme/subcult-minimal.json"
PALETTE = ROOT / "default/theme/palette.json"


def render(theme: dict) -> str:
    meta = theme.get("theme") or {}
    out = {
        "schema": theme["schema"],
        "name": meta.get("id", "subcult-minimal"),
        "appearance": meta.get("appearance", "dark"),
        "colors": theme["colors"],
    }
    return json.dumps(out, indent=2) + "\n"


def main(argv: list[str]) -> int:
    theme = json.loads(THEME.read_text())
    want = render(theme)
    if "--check" in argv:
        have = PALETTE.read_text() if PALETTE.exists() else ""
        if have != want:
            print(f"gen-palette: {PALETTE.relative_to(ROOT)} is stale; run tools/theme/gen-palette.py", file=sys.stderr)
            return 1
        print("gen-palette: palette.json matches subcult-minimal.json")
        return 0
    PALETTE.write_text(want)
    print(f"gen-palette: wrote {PALETTE.relative_to(ROOT)}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
