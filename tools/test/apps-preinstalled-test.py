#!/usr/bin/env python3
"""Every app the catalogue marks `preinstalled = true` (default/apps.toml,
ADR 0044) must be installed by a new system: each of its packages is named
in an install list (install/packages/*.txt), which the installer and the ISO
build read. AUR apps not yet rebuilt in Subarchy's repository are listed in
PENDING; the check fails when that list is out of date in either direction,
so it cannot grow unnoticed."""

import sys
import tomllib
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]

# AUR packages still to vendor under packaging/aur and add to an install list.
PENDING = {
    "zen-browser-bin",
    "t3code-nightly-bin",
    "visual-studio-code-bin",
    "pipewire-control-center",
    "disktree-bin",
    "tuxguitar",
    "claude-code",
}


def install_lists():
    names = set()
    for path in sorted((ROOT / "install/packages").glob("*.txt")):
        for line in path.read_text().splitlines():
            name = line.split("#", 1)[0].strip()
            if name:
                names.add(name)
    return names


def main():
    catalogue = tomllib.loads((ROOT / "default/apps.toml").read_text())
    installed = install_lists()
    errors = []
    wanted = set()
    for app in catalogue["app"]:
        if not app.get("preinstalled"):
            continue
        for pkg in app.get("packages", []):
            wanted.add(pkg)
            if pkg not in installed and pkg not in PENDING:
                errors.append(f"{app['id']}: {pkg} is marked preinstalled but no install list names it")
    for pkg in sorted(PENDING & installed):
        errors.append(f"{pkg} is in an install list now; take it out of PENDING")
    for pkg in sorted(PENDING - wanted):
        errors.append(f"{pkg} is in PENDING but no preinstalled app needs it")
    for e in errors:
        print(f"apps-preinstalled-test: {e}", file=sys.stderr)
    if errors:
        return 1
    print(f"apps-preinstalled-test: ok ({len(wanted) - len(PENDING)} packages installed, {len(PENDING)} pending)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
