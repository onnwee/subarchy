#!/usr/bin/env python3
"""Tests for gen-index.py: the widget index and its manifest rules (ADR 0068)."""

import json
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
