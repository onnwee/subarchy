#!/usr/bin/env python3
"""Tests for gen-index.py: the widget index and its manifest rules (ADR 0068)."""

import importlib.util
import json
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

GEN = Path(__file__).resolve().parent / "gen-index.py"


def write_widget(root: Path, folder: str, manifest: dict) -> None:
    d = root / "widgets" / folder
    d.mkdir(parents=True)
    (d / "manifest.json").write_text(json.dumps(manifest))
    (d / "Widget.qml").write_text("import QtQuick\nItem {}\n")


def run(root: Path, *extra: str) -> subprocess.CompletedProcess:
    return subprocess.run([sys.executable, str(GEN), "--shell", str(root), *extra],
                          capture_output=True, text=True)


GOOD = {"id": "subcult.clock", "name": "Clock", "version": "1.0.0", "api": 0, "kind": "bar-widget"}
WEATHER = {"id": "subcult.weather", "name": "Weather", "version": "1.0.0", "api": 0, "kind": "bar-widget",
           "cost": {"timers": [{"name": "current", "ac": 900, "battery": 1800}], "network": ["api.open-meteo.com"]}}


class GenIndexTest(unittest.TestCase):
    def test_good_tree(self):
        with tempfile.TemporaryDirectory() as t:
            root = Path(t)
            write_widget(root, "weather", WEATHER)
            write_widget(root, "clock", GOOD)
            r = run(root)
            self.assertEqual(r.returncode, 0, r.stderr)
            index = json.loads((root / "widgets" / "index.json").read_text())
            self.assertEqual(index["api"], 0)
            self.assertEqual(list(index["widgets"]), ["subcult.clock", "subcult.weather"])
            self.assertEqual(index["widgets"]["subcult.weather"]["dir"], "weather")
            self.assertEqual(index["widgets"]["subcult.weather"]["manifest"]["cost"]["timers"][0]["battery"], 1800)

    def test_bad_manifests_named(self):
        bad = {
            "api": dict(GOOD, id="subcult.a", api=1),
            "kind": dict(GOOD, id="subcult.b", kind="panel"),
            "id": dict(GOOD, id="omarchy.c"),
            "timer": dict(GOOD, id="subcult.d", cost={"timers": [{"name": "t", "ac": 60}]}),
            "host": dict(GOOD, id="subcult.e", cost={"network": ["http://x/"]}),
        }
        for folder, manifest in bad.items():
            with self.subTest(folder), tempfile.TemporaryDirectory() as t:
                root = Path(t)
                write_widget(root, "clock", GOOD)
                write_widget(root, folder, manifest)
                r = run(root)
                self.assertEqual(r.returncode, 1)
                self.assertIn(folder, r.stderr)
                self.assertFalse((root / "widgets" / "index.json").exists(), "no index written on error")

    def test_duplicate_id(self):
        with tempfile.TemporaryDirectory() as t:
            root = Path(t)
            write_widget(root, "clock", GOOD)
            write_widget(root, "clock2", GOOD)
            self.assertEqual(run(root).returncode, 1)

    def test_missing_widget_qml(self):
        with tempfile.TemporaryDirectory() as t:
            root = Path(t)
            write_widget(root, "clock", GOOD)
            (root / "widgets" / "clock" / "Widget.qml").unlink()
            self.assertEqual(run(root).returncode, 1)

    def test_bad_cost_is_an_error_not_a_crash(self):
        for folder, cost in {"str": "cheap", "timers": {"timers": {"t": 1}}, "net": {"network": "a.example"}}.items():
            with self.subTest(folder), tempfile.TemporaryDirectory() as t:
                root = Path(t)
                write_widget(root, folder, dict(GOOD, cost=cost))
                r = run(root)
                self.assertEqual(r.returncode, 1)
                self.assertIn(folder, r.stderr)
                self.assertNotIn("Traceback", r.stderr)

    @unittest.skipUnless(shutil.which("node"), "node runs the shell's ManifestModel.js")
    def test_same_verdict_as_the_shell(self):
        """gen-index.py and ManifestModel.js accept and refuse the same manifests."""
        timer = {"name": "t", "ac": 60, "battery": 120}
        cases = [GOOD, WEATHER, None, [], "x",
                 dict(GOOD, api=False), dict(GOOD, api="0"), dict(GOOD, api=0.0),
                 dict(GOOD, id=["subcult.clock"]), dict(GOOD, id="subcult.clock\n"), dict(GOOD, id=None),
                 dict(GOOD, cost=None), dict(GOOD, cost=0), dict(GOOD, cost="cheap"), dict(GOOD, cost=[]),
                 dict(GOOD, cost={"timers": None}), dict(GOOD, cost={"timers": {"t": timer}}),
                 dict(GOOD, cost={"timers": "t"}), dict(GOOD, cost={"timers": [timer]}),
                 dict(GOOD, cost={"timers": [dict(timer, ac="60")]}), dict(GOOD, cost={"timers": [dict(timer, ac=True)]}),
                 dict(GOOD, cost={"timers": [dict(timer, battery=0)]}), dict(GOOD, cost={"timers": [None]}),
                 dict(GOOD, cost={"network": ["api.open-meteo.com"]}), dict(GOOD, cost={"network": "api.open-meteo.com"}),
                 dict(GOOD, cost={"network": [["api.open-meteo.com"]]}), dict(GOOD, cost={"network": ["a.example\n"]})]
        js = (GEN.parents[2] / "shell" / "Commons" / "ManifestModel.js").read_text().replace(".pragma library", "")
        script = js + "\nconst cases = JSON.parse(require('fs').readFileSync(0, 'utf8'));\n" \
            "console.log(JSON.stringify(cases.map(m => validate(m, 0).length === 0)))\n"
        r = subprocess.run(["node", "-e", script], input=json.dumps(cases), capture_output=True, text=True)
        self.assertEqual(r.returncode, 0, r.stderr)
        shell_ok = json.loads(r.stdout)
        spec = importlib.util.spec_from_file_location("gen_index", GEN)
        gen = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(gen)
        for m, ok in zip(cases, shell_ok):
            with self.subTest(json.dumps(m)):
                self.assertEqual(gen.validate(m) == [], ok)
        self.assertEqual(shell_ok[:2], [True, True], "the good manifests pass")

    def test_check_mode(self):
        with tempfile.TemporaryDirectory() as t:
            root = Path(t)
            write_widget(root, "clock", GOOD)
            self.assertEqual(run(root, "--check").returncode, 1, "--check fails when the index is missing")
            self.assertEqual(run(root).returncode, 0)
            self.assertEqual(run(root, "--check").returncode, 0)
            write_widget(root, "weather", WEATHER)
            self.assertEqual(run(root, "--check").returncode, 1, "--check fails when the index is stale")


if __name__ == "__main__":
    unittest.main()
