#!/usr/bin/env python3
"""Conformance probe: encode, recolour, skip unchanged input, clear stopped renders and reject bad sizes."""
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
            # Brackets in the path: the cleanup must not read it as a pattern.
            out = work / "out[1]"
            command = [sys.executable, str(ROOT / "bin/subcult-screensaver-render"),
                       "--captures", tmp, "--out", str(out), "--palette", str(palette),
                       "--size", "192x54", "--fps", "2"]
            # A render stopped by SIGTERM leaves its work directory behind.
            stale = out / ".render-stale"
            stale.mkdir(parents=True)
            (stale / "probe.webm").write_bytes(b"partial")
            elsewhere = work / "out1" / ".render-other"
            elsewhere.mkdir(parents=True)
            subprocess.run(command, check=True, capture_output=True)
            self.assertFalse(stale.exists(), "the next render removes a stopped render's work directory")
            self.assertTrue(elsewhere.exists(), "the cleanup stays inside the output directory")
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

    @staticmethod
    def probe(directory):
        """A capture that draws SUBCULT at the terminal's top left, as ttfx does."""
        data = b"SUBCULT\r\n//"
        with gzip.open(directory / "probe.log.gz", "wb") as f:
            f.write(b"Script started\n" + data)
        with gzip.open(directory / "probe.tm.gz", "wb") as f:
            f.write(("0 %d\n0.2 0\n" % len(data)).encode())

    def test_art_is_centred(self):
        with tempfile.TemporaryDirectory() as tmp:
            work = Path(tmp)
            self.probe(work)
            palette = work / "palette.json"
            palette.write_text(json.dumps({"colors": {"base": "#000000", "text": "#ffffff"}}))
            out = work / "out"
            subprocess.run([sys.executable, str(ROOT / "bin/subcult-screensaver-render"), "--captures", tmp,
                            "--out", str(out), "--palette", str(palette), "--size", "960x540", "--fps", "2"],
                           check=True, capture_output=True)
            with Image.open(out / "probe.png") as image:
                left, top, right, bottom = image.convert("L").point(lambda v: 255 if v > 64 else 0).getbbox()
                # Within a cell (10x20 px) of the middle each way.
                self.assertLess(abs((left + right) / 2 - 480), 10, (left, right))
                self.assertLess(abs((top + bottom) / 2 - 270), 20, (top, bottom))

    def test_user_render_skips_the_shipped_colours(self):
        with tempfile.TemporaryDirectory() as tmp:
            work = Path(tmp)
            system, home = work / "system", work / "home"
            (system / "screensaver/captures").mkdir(parents=True)
            (system / "default/theme").mkdir(parents=True)
            self.probe(system / "screensaver/captures")
            (system / "screensaver/index.json").write_text('{"schema": 1, "loops": ["probe"]}')
            colours = {"colors": {"base": "#100B19", "lavender": "#A78BFA"}}
            (system / "default/theme/palette.json").write_text(json.dumps(colours))
            mine = home / ".config/subcult/theme/palette.json"
            mine.parent.mkdir(parents=True)
            mine.write_text(json.dumps(dict(colours, name="subcult-minimal")))
            cache = home / ".cache/subcult/screensaver"
            cache.mkdir(parents=True)
            (cache / "index.json").write_text('{"schema": 1, "loops": ["probe"]}')
            env = {"PATH": "/usr/bin:/bin", "HOME": str(home), "SUBCULT_PATH": str(system)}
            command = [sys.executable, str(ROOT / "bin/subcult-screensaver-render"), "--user"]
            result = subprocess.run(command, env=env, check=True, capture_output=True, text=True)
            self.assertIn("shipped art", result.stdout)
            self.assertFalse((cache / "index.json").exists(), "the lock falls back to the shipped art")
            mine.write_text(json.dumps({"colors": {"base": "#223344"}}))
            subprocess.run(command, env=env, check=True, capture_output=True)
            self.assertTrue((cache / "index.json").exists(), "another palette is rendered")


if __name__ == "__main__":
    unittest.main()
