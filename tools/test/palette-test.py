#!/usr/bin/env python3
"""Check the default palette, the Theme Tender theme it is generated from,
and the Hyprland theme colours (ADR 0037)."""

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


# The packaged KDE colour scheme stands in for Pult's until `pult apply`
# writes the user's copy; its main colours must be the default theme's.
KDE_ROLES = {
    ("Colors:Window", "BackgroundNormal"): "base",
    ("Colors:Window", "ForegroundNormal"): "text",
    ("Colors:View", "BackgroundNormal"): "mantle",
    ("Colors:Button", "BackgroundNormal"): "surface0",
    ("Colors:Selection", "BackgroundNormal"): "mauve",
}


def kde_errors(roles: dict) -> list:
    errors = []
    kdeglobals = (ROOT / "default/kde/kdeglobals").read_text()
    if not re.search(r"^\[UiSettings\]\nColorScheme=Pult$", kdeglobals, re.M):
        errors.append("default/kde/kdeglobals does not select the Pult colour scheme")
    groups, group = {}, None
    for line in (ROOT / "default/kde/Pult.colors").read_text().splitlines():
        if line.startswith("["):
            group = line.strip("[]")
        elif "=" in line and group:
            key, value = line.split("=", 1)
            groups[(group, key)] = value
    for where, role in KDE_ROLES.items():
        want = roles.get(role, "#000000")
        rgb = ",".join(str(int(want[i:i + 2], 16)) for i in (1, 3, 5))
        if groups.get(where) != rgb:
            errors.append(f"default/kde/Pult.colors [{where[0]}] {where[1]} is {groups.get(where)!r}, want {role} {rgb}")
    if groups.get(("General", "Name")) != "Pult":
        errors.append("default/kde/Pult.colors is not named Pult")
    return errors


def kitty_errors(roles: dict) -> list:
    # kitty's packaged colours stand in for Pult's until `pult apply`; the
    # cursor must not change colour when Pult takes over.
    conf = (ROOT / "default/kitty/subcult-ink.conf").read_text()
    m = re.search(r"^cursor (#[0-9A-F]{6})$", conf, re.M)
    have = m.group(1) if m else None
    if have != roles.get("cursor"):
        return [f"default/kitty/subcult-ink.conf cursor is {have!r}, the theme's is {roles.get('cursor')!r}"]
    return []


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
    # The Theme Tender theme (default/theme/subcult-minimal.json) is the
    # source; the shell's palette.json is generated from it and must agree.
    tt = json.loads((ROOT / "default/theme/subcult-minimal.json").read_text())
    meta = tt.get("theme") or {}
    if tt.get("schema") != 1 or meta.get("id") != "subcult-minimal" or meta.get("appearance") != "dark" or not meta.get("name"):
        errors.append("subcult-minimal.json lacks Theme Tender's schema 1 theme envelope (id, name, appearance)")
    if tt.get("colors") != colors:
        errors.append("subcult-minimal.json and palette.json colours differ; run tools/theme/gen-palette.py")
    if palette.get("name") != "subcult-minimal" or palette.get("appearance") != "dark":
        errors.append("palette.json name or appearance differ from the theme")
    theme = (ROOT / "default/hypr/theme.lua").read_text()
    for needle in ("rgb(8F4BC8)", "rgb(1F1830)"):
        if needle not in theme:
            errors.append(f"default/hypr/theme.lua lacks {needle}")
    errors += kde_errors(tt.get("colors", {}))
    errors += kitty_errors(tt.get("colors", {}))
    for e in errors:
        print(f"palette-test: {e}", file=sys.stderr)
    if not errors:
        print(f"palette-test: ok ({len(colors)} roles)")
    return 1 if errors else 0


if __name__ == "__main__":
    sys.exit(main())
