#!/usr/bin/env python3
"""Check the default palette and the Hyprland theme colours (ADR 0037)."""

import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
ROLES = [
    "rosewater", "flamingo", "pink", "mauve", "red", "maroon", "peach", "yellow",
    "green", "teal", "sky", "sapphire", "blue", "lavender", "text", "subtext1",
    "subtext0", "overlay2", "overlay1", "overlay0", "surface2", "surface1",
    "surface0", "base", "mantle", "crust",
]
SPECIALS = ["background", "foreground", "cursor", "selection_bg", "selection_fg"]
PINNED = {
    "base": "#100B19", "mantle": "#0B0812", "crust": "#06040A", "surface0": "#1F1830",
    "text": "#F0ECE4", "subtext1": "#DDD6E8", "subtext0": "#9A92A8", "overlay0": "#5E5570",
    "green": "#00FF88", "mauve": "#8F4BC8", "lavender": "#A78BFA", "selection_bg": "#3B2470",
}


def main() -> int:
    errors = []
    palette = json.loads((ROOT / "default/theme/palette.json").read_text())
    if palette.get("schema") != 1:
        errors.append("schema is not 1")
    colors = palette.get("colors", {})
    expected = ROLES + [f"ansi{i}" for i in range(16)] + SPECIALS
    missing = [k for k in expected if k not in colors]
    extra = [k for k in colors if k not in expected]
    if missing:
        errors.append(f"missing roles: {missing}")
    if extra:
        errors.append(f"unknown roles: {extra}")
    for key, value in colors.items():
        if not re.fullmatch(r"#[0-9A-F]{6}", str(value)):
            errors.append(f"{key}: {value!r} is not #RRGGBB in upper case")
    for key, value in PINNED.items():
        if colors.get(key) != value:
            errors.append(f"{key} is {colors.get(key)!r}, spec says {value}")
    theme = (ROOT / "default/hypr/theme.lua").read_text()
    for needle in ("rgb(8F4BC8)", "rgb(1F1830)"):
        if needle not in theme:
            errors.append(f"default/hypr/theme.lua lacks {needle}")
    for e in errors:
        print(f"palette-test: {e}", file=sys.stderr)
    if not errors:
        print(f"palette-test: ok ({len(colors)} roles)")
    return 1 if errors else 0


if __name__ == "__main__":
    sys.exit(main())
