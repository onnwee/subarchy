#!/usr/bin/env python3
"""The file chooser's pure parts; the portal itself needs a desktop session."""

import importlib.util
from pathlib import Path
import unittest

spec = importlib.util.spec_from_file_location("file_chooser", Path(__file__).with_name("file-chooser.py"))
chooser = importlib.util.module_from_spec(spec)
spec.loader.exec_module(chooser)


class RequestPath(unittest.TestCase):
    def test_from_the_unique_name(self):
        self.assertEqual(chooser.request_path(":1.42", "subcult7"),
                         "/org/freedesktop/portal/desktop/request/1_42/subcult7")


class LocalPaths(unittest.TestCase):
    def test_file_uris_become_paths(self):
        try:
            import gi  # noqa: F401
        except ImportError:
            self.skipTest("python-gobject is not installed")
        self.assertEqual(chooser.local_paths(["file:///home/a/My%20notes.pdf", "https://example.com/x", "file:///tmp/b"]),
                         ["/home/a/My notes.pdf", "/tmp/b"])


if __name__ == "__main__":
    unittest.main()
