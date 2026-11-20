#!/usr/bin/env python3
"""Publishing safety and retry behavior, without registry writes."""

import importlib.util
import http.client
import io
import os
from pathlib import Path
import tarfile
import tempfile
import unittest
from unittest.mock import patch, MagicMock
import urllib.error


spec = importlib.util.spec_from_file_location(
    "publish_packages", Path(__file__).parents[1] / "ci/publish-packages.py"
)
publisher = importlib.util.module_from_spec(spec)
spec.loader.exec_module(publisher)


# For tests of the upload itself: the registry does not serve the file.
not_served = patch.object(publisher, "served", new=lambda channel, package: False)


class PublishTests(unittest.TestCase):
    def test_pr_and_non_main_push_refuse_before_any_request(self):
        for event, ref in (("pull_request", "refs/heads/main"), ("push", "refs/heads/topic"),
                           ("push", "refs/tags/v0.0.0")):
            with self.subTest(event=event, ref=ref), patch.dict(
                os.environ,
                {"GITHUB_EVENT_NAME": event, "GITHUB_REF": ref, "SUBARCHY_PACKAGE_TOKEN": "unused"},
                clear=True,
            ), patch.object(publisher.urllib.request, "urlopen") as request:
                with self.assertRaisesRegex(SystemExit, "push to main"):
                    publisher.main()
                request.assert_not_called()

    def test_published_reads_the_channel_database(self):
        response = MagicMock()
        response.__enter__.return_value.read.return_value = database(
            "lib32-nvidia-580xx-utils-580.196.07-1", "yay-13.1.0-1")
        with patch.object(publisher.urllib.request, "urlopen", return_value=response) as request:
            listed = publisher.published("stable")
        self.assertEqual(listed, {"lib32-nvidia-580xx-utils-580.196.07-1", "yay-13.1.0-1"})
        lookup = request.call_args.args[0]
        self.assertEqual(lookup.method, "GET")
        self.assertIn("/stable/x86_64/subarchy.db?ci-check=", lookup.full_url)
        self.assertIsNone(lookup.get_header("Authorization"))

    def test_a_longer_name_does_not_stand_in_for_a_package(self):
        # The registry answers a file request for nvidia-580xx-utils-... with
        # lib32-nvidia-580xx-utils-...; only the database says what exists.
        listed = {"lib32-nvidia-580xx-utils-580.196.07-1"}
        self.assertIn(publisher.entry(Path("lib32-nvidia-580xx-utils-580.196.07-1-x86_64.pkg.tar.zst")), listed)
        self.assertNotIn(publisher.entry(Path("nvidia-580xx-utils-580.196.07-1-x86_64.pkg.tar.zst")), listed)
        self.assertEqual(publisher.entry(Path("linecast-2.12.0-1-any.pkg.tar.zst")), "linecast-2.12.0-1")

    def test_channel_without_a_database_lists_nothing(self):
        missing = urllib.error.HTTPError("https://example.test", 404, "missing", {}, None)
        with patch.object(publisher.urllib.request, "urlopen", side_effect=missing):
            self.assertEqual(publisher.published("edge"), set())

    def test_registry_failure_does_not_attempt_upload(self):
        error = urllib.error.HTTPError("https://example.test", 403, "forbidden", {}, None)
        with patch.dict(
            os.environ,
            {"GITHUB_EVENT_NAME": "push", "GITHUB_REF": "refs/heads/main", "SUBARCHY_PACKAGE_TOKEN": "unused"},
            clear=True,
        ), patch.object(publisher.urllib.request, "urlopen", side_effect=error) as request:
            with self.assertRaisesRegex(RuntimeError, "HTTP 403"):
                publisher.main()
            self.assertEqual(request.call_count, 1)

    def test_lookup_recovers_from_temporary_dns_failure(self):
        response = MagicMock()
        response.__enter__.return_value.read.return_value = database("new-1.0-1")
        with patch.object(publisher.urllib.request, "urlopen", side_effect=[
            urllib.error.URLError("temporary DNS failure"), response,
        ]) as request, patch.object(publisher.time, "sleep"):
            self.assertEqual(publisher.published("stable"), {"new-1.0-1"})
        self.assertEqual(request.call_count, 2)
        self.assertTrue(all(call.args[0].method == "GET" for call in request.call_args_list))

    def test_lookup_recovers_from_truncated_http_response(self):
        class Socket:
            def makefile(self, *args):
                return io.BytesIO(b"HTTP/1.1 200 OK\r\nContent-Length: 100\r\n\r\ntruncated")
        truncated = http.client.HTTPResponse(Socket())
        truncated.begin()
        response = MagicMock()
        response.__enter__.return_value.read.return_value = database("new-1.0-1")
        with patch.object(publisher.urllib.request, "urlopen", side_effect=[truncated, response]) as request, patch.object(
            publisher.time, "sleep",
        ):
            self.assertEqual(publisher.published("stable"), {"new-1.0-1"})
        self.assertEqual(request.call_count, 2)
        self.assertTrue(truncated.isclosed())

    def test_repeated_incomplete_reads_stop_without_echoing_body(self):
        with patch.object(publisher.urllib.request, "urlopen", side_effect=http.client.IncompleteRead(
            b"sensitive body marker", 100,
        )) as request, patch.object(publisher.time, "sleep"):
            with self.assertRaisesRegex(RuntimeError, "lookup.*3 attempts") as error:
                publisher.published("stable")
            self.assertEqual(request.call_count, 3)
            self.assertNotIn("sensitive body marker", str(error.exception))

    def test_lookup_stops_after_repeated_transient_failures(self):
        for error in (urllib.error.URLError("unavailable"),
                      urllib.error.HTTPError("https://example.test", 503, "unavailable", {}, None)):
            with self.subTest(error=type(error).__name__), patch.object(
                publisher.urllib.request, "urlopen", side_effect=error,
            ) as request, patch.object(publisher.time, "sleep"):
                with self.assertRaisesRegex(RuntimeError, "lookup.*3 attempts"):
                    publisher.published("stable")
                self.assertEqual(request.call_count, 3)

    @not_served
    def test_interrupted_upload_checks_whether_the_registry_committed_it(self):
        with tempfile.TemporaryDirectory() as temp:
            package = Path(temp) / "new-1.0-1-any.pkg.tar.zst"
            package.write_bytes(b"package bytes")
            with patch.object(publisher.urllib.request, "urlopen", side_effect=urllib.error.URLError(
                "temporary DNS failure",
            )) as request, patch.object(publisher, "published", return_value={"new-1.0-1"}) as lookup:
                publisher.publish(package, "stable", "test-token", set())
            lookup.assert_called_once_with("stable")
            self.assertEqual(request.call_count, 1, "a committed version must not be resent")

    @not_served
    def test_interrupted_http_status_line_checks_for_a_committed_upload(self):
        with tempfile.TemporaryDirectory() as temp:
            package = Path(temp) / "new-1.0-1-any.pkg.tar.zst"
            package.write_bytes(b"package bytes")
            with patch.object(publisher.urllib.request, "urlopen", side_effect=http.client.BadStatusLine(
                "truncated status marker",
            )) as request, patch.object(publisher, "published", return_value={"new-1.0-1"}) as lookup:
                publisher.publish(package, "stable", "test-token", set())
            lookup.assert_called_once_with("stable")
            self.assertEqual(request.call_count, 1)

    @not_served
    def test_upload_retry_opens_a_fresh_complete_stream(self):
        with tempfile.TemporaryDirectory() as temp:
            package = Path(temp) / "new-1.0-1-any.pkg.tar.zst"
            package.write_bytes(b"complete package")
            streams = []
            def upload(request, **kwargs):
                streams.append(request.data)
                self.assertEqual(request.data.read(), b"complete package")
                if len(streams) == 1:
                    raise urllib.error.URLError("connection interrupted")
                response = MagicMock()
                response.__enter__.return_value.status = 201
                return response
            with patch.object(publisher.urllib.request, "urlopen", side_effect=upload), patch.object(
                publisher, "published", return_value=set(),
            ), patch.object(publisher.time, "sleep"):
                publisher.publish(package, "edge", "test-token", set())
            self.assertEqual(len(streams), 2)
            self.assertIsNot(streams[0], streams[1])
            self.assertTrue(all(stream.closed for stream in streams))

    @not_served
    def test_upload_stops_after_repeated_network_failures(self):
        with tempfile.TemporaryDirectory() as temp:
            package = Path(temp) / "new-1.0-1-any.pkg.tar.zst"
            package.write_bytes(b"package bytes")
            with patch.object(publisher.urllib.request, "urlopen", side_effect=urllib.error.URLError(
                "do not echo request details or test-token",
            )) as request, patch.object(publisher, "published", return_value=set()), patch.object(
                publisher.time, "sleep",
            ):
                with self.assertRaisesRegex(RuntimeError, "upload.*3 attempts") as error:
                    publisher.publish(package, "stable", "test-token", set())
                self.assertEqual(request.call_count, 3)
                self.assertNotIn("test-token", str(error.exception))

    @not_served
    def test_upload_is_not_replayed_when_readback_fails(self):
        with tempfile.TemporaryDirectory() as temp:
            package = Path(temp) / "new-1.0-1-any.pkg.tar.zst"
            package.write_bytes(b"package bytes")
            with patch.object(publisher.urllib.request, "urlopen", side_effect=urllib.error.URLError(
                "connection interrupted",
            )) as request, patch.object(publisher, "published", side_effect=RuntimeError("lookup failed")):
                with self.assertRaisesRegex(RuntimeError, "lookup failed"):
                    publisher.publish(package, "stable", "test-token", set())
                self.assertEqual(request.call_count, 1)

    @not_served
    def test_upload_auth_failure_does_not_retry_or_read_back(self):
        with tempfile.TemporaryDirectory() as temp:
            package = Path(temp) / "new-1.0-1-any.pkg.tar.zst"
            package.write_bytes(b"package bytes")
            for code in (401, 403):
                error = urllib.error.HTTPError("https://example.test", code, "refused", {}, None)
                with self.subTest(code=code), patch.object(
                    publisher.urllib.request, "urlopen", side_effect=error,
                ) as request, patch.object(publisher, "published") as lookup:
                    with self.assertRaisesRegex(RuntimeError, f"HTTP {code}"):
                        publisher.publish(package, "stable", "test-token", set())
                    self.assertEqual(request.call_count, 1)
                    lookup.assert_not_called()

    def test_older_version_hidden_by_a_newer_one_is_not_uploaded(self):
        # 2026-11-16, job 44220: yay 13.1.0-3 was uploaded by hand before the
        # run for an older commit published 13.1.0-2. The databases list one
        # version per package, so they listed only -3; the registry still
        # held -2, the uploader sent it again and got HTTP 409.
        package = Path("yay-13.1.0-2-x86_64.pkg.tar.zst")
        requests = []
        def registry(request, **kwargs):
            requests.append(request)
            self.assertEqual(request.method, "HEAD")
            # The query keeps the CDN's cached 404 out of the answer.
            self.assertIn("/stable/x86_64/yay-13.1.0-2-x86_64.pkg.tar.zst?ci-check=", request.full_url)
            self.assertIsNone(request.get_header("Authorization"))
            return served_as(package.name)
        with patch.object(publisher.urllib.request, "urlopen", side_effect=registry):
            publisher.publish(package, "stable", "test-token", {"yay-13.1.0-3", "yay-debug-13.1.0-3"})
        self.assertEqual(len(requests), 1, "an existing version must not be uploaded")

    def test_only_the_channel_missing_the_version_gets_it(self):
        with tempfile.TemporaryDirectory() as temp:
            package = Path(temp) / "yay-13.1.0-2-x86_64.pkg.tar.zst"
            package.write_bytes(b"package bytes")
            uploads = []
            def registry(request, **kwargs):
                if request.method == "HEAD":
                    if "/stable/" in request.full_url:
                        return served_as(package.name)
                    raise urllib.error.HTTPError(request.full_url, 404, "missing", {}, None)
                uploads.append(request.full_url)
                return created()
            with patch.object(publisher.urllib.request, "urlopen", side_effect=registry):
                for channel in publisher.CHANNELS:
                    publisher.publish(package, channel, "test-token", {"yay-13.1.0-3"})
            self.assertEqual(uploads, [f"{publisher.REGISTRY}/edge"])

    def test_a_file_served_under_another_name_is_not_the_version(self):
        # The registry finds a file by substring, so the answer must name the
        # requested file before it counts.
        self.assertFalse(self.served_with("lib32-nvidia-580xx-utils-580.196.07-1-x86_64.pkg.tar.zst"))
        self.assertFalse(self.served_with(None))
        self.assertTrue(self.served_with("nvidia-580xx-utils-580.196.07-1-x86_64.pkg.tar.zst"))

    def served_with(self, filename):
        with patch.object(publisher.urllib.request, "urlopen", return_value=served_as(filename)):
            return publisher.served("stable", Path("nvidia-580xx-utils-580.196.07-1-x86_64.pkg.tar.zst"))

    def test_served_lookup_failure_is_not_read_as_absent(self):
        for error in (urllib.error.URLError("connection reset"),
                      urllib.error.HTTPError("https://example.test", 503, "unavailable", {}, None),
                      urllib.error.HTTPError("https://example.test", 403, "forbidden", {}, None)):
            with self.subTest(error=str(error)), patch.object(
                publisher.urllib.request, "urlopen", side_effect=error,
            ), patch.object(publisher.time, "sleep"):
                with self.assertRaises(RuntimeError):
                    publisher.served("stable", Path("yay-13.1.0-2-x86_64.pkg.tar.zst"))

    def test_conflict_for_a_version_the_registry_does_not_serve_still_fails(self):
        # Versions are immutable: if the registry refuses a file it does not
        # serve under that name, its bytes differ or its state is unknown.
        with tempfile.TemporaryDirectory() as temp:
            package = Path(temp) / "yay-13.1.0-2-x86_64.pkg.tar.zst"
            package.write_bytes(b"different bytes")
            def registry(request, **kwargs):
                if request.method == "HEAD":
                    raise urllib.error.HTTPError(request.full_url, 404, "missing", {}, None)
                raise urllib.error.HTTPError(request.full_url, 409, "exists", {}, None)
            with patch.object(publisher.urllib.request, "urlopen", side_effect=registry):
                with self.assertRaisesRegex(RuntimeError, "HTTP 409 for yay-13.1.0-2"):
                    publisher.publish(package, "stable", "test-token", {"yay-13.1.0-3"})

    def test_existing_version_is_never_uploaded(self):
        with patch.object(publisher.urllib.request, "urlopen") as request:
            publisher.publish(Path("already-there-1.0-1-any.pkg.tar.zst"), "stable", "unused", {"already-there-1.0-1"})
        request.assert_not_called()

    @not_served
    def test_missing_version_streams_upload_and_requires_created(self):
        for code in (201, 200, 409, 500):
            with self.subTest(code=code), tempfile.TemporaryDirectory() as temp:
                package = Path(temp) / "new-1.0-1-any.pkg.tar.zst"
                package.write_bytes(b"package bytes")
                response = MagicMock()
                response.__enter__.return_value.status = code
                with patch.object(publisher.urllib.request, "urlopen", return_value=response) as request:
                    if code == 201:
                        publisher.publish(package, "edge", "test-token", {"other-1.0-1"})
                    else:
                        with self.assertRaisesRegex(RuntimeError, f"HTTP {code}"):
                            publisher.publish(package, "edge", "test-token", {"other-1.0-1"})
                    self.assertEqual(request.call_count, 1)
                    upload = request.call_args.args[0]
                    self.assertEqual(upload.method, "PUT")
                    self.assertEqual(upload.get_header("Authorization"), "token test-token")
                    self.assertNotIn("test-token", upload.full_url)
                    self.assertEqual(upload.get_header("Content-length"), "13")

    def test_names_the_registry_cannot_tell_apart(self):
        # The registry finds a file by substring: with both of these present
        # it answers 404 for the shorter one (2026-11-09).
        short = "nvidia-580xx-utils-580.196.07-1-x86_64.pkg.tar.zst"
        long = "lib32-nvidia-580xx-utils-580.196.07-1-x86_64.pkg.tar.zst"
        self.assertEqual(publisher.collisions([long, "yay-13.1.0-1-x86_64.pkg.tar.zst", short]), [(short, long)])
        bumped = "nvidia-580xx-utils-580.196.07-2-x86_64.pkg.tar.zst"
        self.assertEqual(publisher.collisions([long, bumped, "yay-13.1.0-1-x86_64.pkg.tar.zst"]), [])

    @not_served
    def test_oversized_upload_says_what_to_do(self):
        with tempfile.TemporaryDirectory() as temp:
            package = Path(temp) / "big-1.0-1-x86_64.pkg.tar.zst"
            package.write_bytes(b"x")
            too_large = urllib.error.HTTPError("https://example.test", 413, "too large", {}, None)
            with patch.object(publisher.urllib.request, "urlopen", side_effect=too_large):
                with self.assertRaisesRegex(RuntimeError, "100 MB.*origin"):
                    publisher.publish(package, "stable", "test-token", set())


def served_as(filename):
    """A registry answer to a file request, naming the file it served."""
    response = MagicMock()
    response.__enter__.return_value.headers.get_filename.return_value = filename
    return response


def created():
    response = MagicMock()
    response.__enter__.return_value.status = 201
    return response


def database(*entries):
    """A pacman database as the registry serves it: one desc file per entry."""
    out = io.BytesIO()
    with tarfile.open(fileobj=out, mode="w:gz") as tar:
        for name in entries:
            info = tarfile.TarInfo(f"{name}/desc")
            info.size = 0
            tar.addfile(info, io.BytesIO())
    return out.getvalue()


if __name__ == "__main__":
    unittest.main()
