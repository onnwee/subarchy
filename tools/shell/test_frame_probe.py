#!/usr/bin/env python3
"""Safety checks for the diagnostic copy used in the #98 frame probe."""

import importlib.util
import tempfile
import unittest
from pathlib import Path

spec = importlib.util.spec_from_file_location("frame_probe", Path(__file__).with_name("frame-probe.py"))
probe = importlib.util.module_from_spec(spec)
spec.loader.exec_module(probe)


class FrameProbeTest(unittest.TestCase):
    def test_copy_preserves_sources_and_runtime_settings(self):
        source = probe.SOURCE
        before = {p.relative_to(source): p.read_bytes() for p in source.rglob("*") if p.is_file()}
        with tempfile.TemporaryDirectory() as work:
            destination = Path(work) / "shell"
            probe.prepare(source, destination)
            self.assertEqual(before, {p.relative_to(source): p.read_bytes() for p in source.rglob("*") if p.is_file()})
            for name, data in before.items():
                if name != Path("Bar.qml"):
                    self.assertEqual((destination / name).read_bytes(), data, str(name))
            self.assertIn("bar.contentItem.Window.window", (destination / "Bar.qml").read_text())
            self.assertIn("onFrameSwapped", (destination / "FrameProbe.qml").read_text())

    def test_existing_destination_is_not_overwritten(self):
        with tempfile.TemporaryDirectory() as work:
            destination = Path(work)
            sentinel = destination / "Bar.qml"
            sentinel.write_text("other work")
            with self.assertRaises(FileExistsError):
                probe.prepare(probe.SOURCE, destination)
            self.assertEqual(sentinel.read_text(), "other work")

    def test_source_and_descendants_are_rejected(self):
        for destination in [probe.SOURCE, probe.SOURCE / "probe"]:
            with self.subTest(destination=destination), self.assertRaises(ValueError):
                probe.prepare(probe.SOURCE, destination)


if __name__ == "__main__":
    unittest.main()
