#!/usr/bin/env python3
"""Publishing safety and retry behavior, without registry writes."""

import importlib.util
import os
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch, MagicMock
import urllib.error


spec = importlib.util.spec_from_file_location(
    "publish_packages", Path(__file__).parents[1] / "ci/publish-packages.py"
)
publisher = importlib.util.module_from_spec(spec)
spec.loader.exec_module(publisher)


class PublishTests(unittest.TestCase):
    def test_pr_and_non_main_push_refuse_before_any_request(self):
        for event, ref in (("pull_request", "refs/heads/main"), ("push", "refs/heads/topic")):
            with self.subTest(event=event, ref=ref), patch.dict(
                os.environ,
                {"GITHUB_EVENT_NAME": event, "GITHUB_REF": ref, "SUBARCHY_PACKAGE_TOKEN": "unused"},
                clear=True,
            ), patch.object(publisher.urllib.request, "urlopen") as request:
                with self.assertRaisesRegex(SystemExit, "push to main"):
                    publisher.main()
                request.assert_not_called()

    def test_existing_version_is_never_uploaded(self):
        response = MagicMock()
        response.__enter__.return_value.status = 200
        with patch.object(publisher.urllib.request, "urlopen", return_value=response) as request:
            publisher.publish(Path("already-there.pkg.tar.zst"), "stable", "unused")
        self.assertEqual(request.call_count, 1)
        head = request.call_args.args[0]
        self.assertEqual(head.method, "HEAD")
        self.assertIn("?ci-check=", head.full_url)
        self.assertIsNone(head.get_header("Authorization"))

    def test_missing_version_streams_upload_and_requires_created(self):
        for code in (201, 200, 409, 500):
            with self.subTest(code=code), tempfile.TemporaryDirectory() as temp:
                package = Path(temp) / "new.pkg.tar.zst"
                package.write_bytes(b"package bytes")
                head = urllib.error.HTTPError("https://example.test", 404, "missing", {}, None)
                response = MagicMock()
                response.__enter__.return_value.status = code
                with patch.object(publisher.urllib.request, "urlopen", side_effect=[head, response]) as request:
                    if code == 201:
                        publisher.publish(package, "edge", "test-token")
                    else:
                        with self.assertRaisesRegex(RuntimeError, f"HTTP {code}"):
                            publisher.publish(package, "edge", "test-token")
                    upload = request.call_args.args[0]
                    self.assertEqual(upload.method, "PUT")
                    self.assertEqual(upload.get_header("Authorization"), "token test-token")
                    self.assertNotIn("test-token", upload.full_url)
                    self.assertEqual(upload.get_header("Content-length"), "13")

    def test_registry_failure_does_not_attempt_upload(self):
        error = urllib.error.HTTPError("https://example.test", 503, "unavailable", {}, None)
        with patch.object(publisher.urllib.request, "urlopen", side_effect=error) as request:
            with self.assertRaisesRegex(RuntimeError, "HTTP 503"):
                publisher.publish(Path("not-opened.pkg.tar.zst"), "stable", "unused")
            self.assertEqual(request.call_count, 1)


if __name__ == "__main__":
    unittest.main()
