#!/usr/bin/env python3
"""Exercise the packaged Pult's embedded app integrations in a temporary home.

Usage: python3 tools/test/pult-app-targets-test.py /path/to/pult
App binaries are detection fixtures, not native rendering checks. No host
config, app process or network is used. The package's check() runs this.
"""

import json
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile
import tomllib
import unittest

ROOT = Path(__file__).resolve().parents[2]
PULT = Path(sys.argv.pop(1)).resolve() if len(sys.argv) > 1 else None
APPS = ["swayimg", "vscode", "obsidian", "bat", "delta", "eza", "fzf", "subarchy-shell"]


class AppTargets(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="subarchy-pult-")
        self.addCleanup(self.temp.cleanup)
        self.home = Path(self.temp.name)
        self.config = self.home / ".config"
        self.bin = self.home / "bin"
        self.bin.mkdir()
        # A fresh environment prevents inherited config overrides, framework
        # detection and connections to the owner's running desktop apps.
        self.env = {
            "HOME": str(self.home), "PATH": f"{self.bin}:{os.defpath}",
            "XDG_CONFIG_HOME": str(self.config),
            "XDG_DATA_HOME": str(self.home / ".local/share"),
            "XDG_STATE_HOME": str(self.home / ".local/state"),
            "XDG_CACHE_HOME": str(self.home / ".cache"),
            "FZF_DEFAULT_OPTS_FILE": str(self.config / "fzf/fzfrc"),
            "GOMAXPROCS": "2",
        }
        for binary, version in {
            "swayimg": "swayimg version 5.7", "code": "1.105.0",
            "obsidian": "1.15.0", "bat": "bat 0.26.1", "delta": "delta 0.20.1",
            "eza": "v0.23.5", "fzf": "0.74.5", "subcult": "0.0.0",
        }.items():
            stub = self.bin / binary
            stub.write_text(f"#!/bin/sh\nprintf '%s\\n' '{version}'\n")
            stub.chmod(0o755)
        # Use Subarchy's default theme but limit the app set: the default
        # profile's all-installed policy must never reload a host app here.
        profile = tomllib.loads((ROOT / "default/theme/subarchy.toml").read_text())
        self.theme = ROOT / "default/theme" / profile["theme"]
        self.write("profile.toml", f'schema = 1\ntheme = {json.dumps(str(self.theme))}\n'
                   + "apps = " + json.dumps(APPS) + "\n")
        self.vaults = [self.home / "Vaults/First notes", self.home / "Vaults/Closed"]
        for vault in self.vaults:
            (vault / ".obsidian").mkdir(parents=True)
            (vault / "note.md").write_text("# Keep this note\n")
            (vault / ".obsidian/workspace.json").write_text('{"active":"keep"}\n')
            (vault / ".obsidian/appearance.json").write_text(
                '{"cssTheme":"Previous theme","baseFontSize":19}\n')
        self.write(".config/obsidian/obsidian.json", json.dumps({"vaults": {
            "first": {"path": str(self.vaults[0]), "open": True},
            "closed": {"path": str(self.vaults[1]), "open": False},
            "duplicate": {"path": str(self.vaults[0]) + "/."},
            "missing": {"path": str(self.home / "missing")},
        }}))
        self.write(".config/Code/User/settings.json", '\ufeff{\r\n'
                   '  // Keep my editor settings\r\n  "editor.fontSize": 19,\r\n'
                   '  "workbench.colorCustomizations": {"extension.custom": "#123456",},\r\n}\r\n')
        self.write(".config/swayimg/init.lua", "-- My keys stay here\nswayimg.viewer.default_scale = 'fit'\n")
        self.write(".config/bat/config", "--paging=never\n")
        self.write(".gitconfig", "[user]\n\tname = Fixture\n")
        self.write(".config/eza/theme.yml", "# My listing style\ncolourful: false\n")
        self.write(".config/fzf/fzfrc", "--height=40%\n")

    def write(self, path, text):
        path = self.home / path
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(text.encode())

    def read(self, path):
        return (self.home / path).read_text(encoding="utf-8-sig")

    def run_pult(self, *args, success=True):
        result = subprocess.run([str(PULT), *args], env=self.env, cwd=self.home,
                                capture_output=True, text=True, timeout=120)
        if success:
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        else:
            self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
        return result.stdout + result.stderr

    def snapshot(self):
        # State/cache hold Pult's transaction history, not app configuration.
        return {str(p.relative_to(self.home)): p.read_bytes()
                for base in (self.config, self.home / "Vaults") for p in base.rglob("*") if p.is_file()
                } | {".gitconfig": (self.home / ".gitconfig").read_bytes()}

    def apply(self, theme=None, dry=False):
        args = ["apply", "-yes", "-profile", str(self.home / "profile.toml")]
        if theme:
            # Change only the theme; keep the safe, limited app set.
            self.write("profile.toml", 'schema = 1\ntheme = ' + json.dumps(theme)
                       + "\napps = " + json.dumps(APPS) + "\n")
        if dry:
            args.append("-dry-run")
        return self.run_pult(*args)

    def assert_colours(self, theme, settings_theme):
        colors = {k: v.lower() for k, v in theme["colors"].items()}
        settings = self.read(".config/Code/User/settings.json")
        for text in ('// Keep my editor settings', '"editor.fontSize": 19',
                     '"extension.custom": "#123456"', settings_theme,
                     '"editor.background": "' + colors["base"] + '"',
                     '"terminal.ansiBlue": "' + colors["ansi4"] + '"'):
            self.assertIn(text, settings)
        for vault in self.vaults:
            cfg = vault / ".obsidian"
            appearance = json.loads((cfg / "appearance.json").read_text())
            self.assertEqual(appearance, {"cssTheme": "Pult", "baseFontSize": 19})
            self.assertEqual(json.loads((cfg / "themes/Pult/manifest.json").read_text())["name"], "Pult")
            self.assertIn("--background-primary: " + colors["base"] + ";",
                          (cfg / "themes/Pult/theme.css").read_text())
        lua = self.read(".config/swayimg/pult.lua")
        for text in ("swayimg.viewer.set_window_background(0xff" + colors["base"][1:] + ")",
                     "swayimg.gallery.window_color = 0xff" + colors["base"][1:],
                     "swayimg.text.color = 0xff" + colors["text"][1:]):
            self.assertIn(text, lua)
        init = self.read(".config/swayimg/init.lua")
        self.assertTrue(init.startswith("-- My keys stay here\nswayimg.viewer.default_scale = 'fit'\n"))
        self.assertEqual(init.count('dofile("' + str(self.config / "swayimg/pult.lua") + '")'), 1)
        palette = json.loads(self.read(".config/subcult/theme/palette.json"))
        self.assertEqual(palette["colors"]["base"].lower(), colors["base"])
        self.assertRegex(self.read(".config/eza/theme.yml").lower(),
                         r'normal:\s+foreground: "' + re.escape(colors["text"]) + '"')

    def test_default_dark_light_idempotence_and_exact_undo(self):
        before = self.snapshot()
        listed = self.run_pult("list")
        for app in APPS:
            self.assertRegex(listed, rf"(?m)^{app}\s")
        self.apply(dry=True)
        self.assertEqual(before, self.snapshot(), "dry-run wrote app files")
        self.apply()
        self.assert_colours(json.loads(self.theme.read_text()), "Default Dark Modern")
        for theme, base in (("dracula", "Default Dark Modern"),
                            ("catppuccin-latte", "Default Light Modern")):
            self.apply(theme)
            self.assert_colours(json.loads(self.run_pult("palette", theme)), base)
        after = self.snapshot()
        self.apply()
        self.assertEqual(after, self.snapshot(), "same palette rewrote app files")
        self.apply(str(self.theme))
        self.assert_colours(json.loads(self.theme.read_text()), "Default Dark Modern")
        self.assertIn("--paging=never", self.read(".config/bat/config"))
        self.assertIn('--theme="ansi"', self.read(".config/bat/config"))
        delta_theme = subprocess.check_output(
            ["git", "config", "--file", str(self.home / ".gitconfig"), "delta.syntax-theme"],
            env=self.env, text=True)
        self.assertEqual(delta_theme.strip(), "ansi")
        self.assertIn("name = Fixture", self.read(".gitconfig"))
        self.assertIn('--color="16"', self.read(".config/fzf/fzfrc"))
        self.assertIn("--height=40%", self.read(".config/fzf/fzfrc"))
        self.assertIn("# My listing style", self.read(".config/eza/theme.yml"))
        # Discovery metadata, notes and workspace state are read-only.
        for path, content in before.items():
            if path.endswith(("note.md", "workspace.json", "obsidian/obsidian.json")):
                self.assertEqual((self.home / path).read_bytes(), content)
        self.run_pult("uninstall", "-yes")
        self.assertEqual(before, self.snapshot(), "uninstall did not restore original app bytes")
        self.assertFalse((self.home / "missing").exists())

    def test_invalid_editor_settings_stop_before_any_app_write(self):
        self.write(".config/Code/User/settings.json", '{"editor.fontSize":14,"editor.fontSize":16}')
        before = self.snapshot()
        output = self.run_pult("apply", "-yes", "-profile", str(self.home / "profile.toml"), success=False)
        self.assertIn("duplicate JSON key", output)
        self.assertEqual(before, self.snapshot())


if __name__ == "__main__":
    if PULT is None or not PULT.is_file():
        raise SystemExit("usage: pult-app-targets-test.py /path/to/pult (required; no skip)")
    unittest.main()
