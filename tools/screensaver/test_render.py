#!/usr/bin/env python3
"""Conformance probe: encode, recolour, skip unchanged input and reject bad sizes."""
import gzip
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

from PIL import Image

ROOT = Path(__file__).resolve().parents[2]


class RenderTest(unittest.TestCase):
    def test_render_and_palette_change(self):
        with tempfile.TemporaryDirectory() as tmp:
            work = Path(tmp)
            data = b"\x1b[38;2;0;255;0mSUBCULT\x1b[0m"
            with gzip.open(work / "probe.log.gz", "wb") as f:
                f.write(b"Script started\n" + data)
            with gzip.open(work / "probe.tm.gz", "wb") as f:
                f.write(("0 %d\n0.5 0\n" % len(data)).encode())
            palette = work / "palette.json"
            palette.write_text(json.dumps({"colors": {"base": "#100b19", "lavender": "#a78bfa"}}))
            out = work / "out"
            command = [sys.executable, str(ROOT / "bin/subcult-screensaver-render"),
                       "--captures", tmp, "--out", str(out), "--palette", str(palette),
                       "--size", "192x54", "--fps", "2"]
            subprocess.run(command, check=True, capture_output=True)
            before = (out / "probe.png").read_bytes()
            stamp = (out / "index.json").stat().st_mtime_ns
            result = subprocess.run(command, check=True, capture_output=True, text=True)
            self.assertIn("up to date", result.stdout)
            self.assertEqual(stamp, (out / "index.json").stat().st_mtime_ns)
            probe = subprocess.run(["ffprobe", "-v", "error", "-show_entries", "stream=codec_name,width,height",
                                    "-of", "csv=p=0", str(out / "probe.webm")], check=True, capture_output=True, text=True)
            self.assertEqual(probe.stdout.strip(), "vp9,192,54")
            palette.write_text(json.dumps({"colors": {"base": "#223344", "lavender": "#ff0000"}}))
            subprocess.run(command, check=True, capture_output=True)
            self.assertNotEqual(before, (out / "probe.png").read_bytes())
            with Image.open(out / "probe.png") as image:
                self.assertEqual(image.getpixel((191, 53)), (34, 51, 68))
                self.assertTrue(any(image.getpixel((x, y))[0] > max(image.getpixel((x, y))[1:])
                                    for x in range(image.width) for y in range(image.height)))
            result = subprocess.run(command + ["--size", "193x54"], capture_output=True)
            self.assertEqual(result.returncode, 2)


if __name__ == "__main__":
    unittest.main()
