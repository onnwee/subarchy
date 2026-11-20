#!/usr/bin/env python3
"""The outdated-pin report, against fixture responses. No network."""

from datetime import datetime, timezone
import importlib.util
import io
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch
import urllib.error

spec = importlib.util.spec_from_file_location(
    "report_outdated_pins", Path(__file__).parents[1] / "ci/report-outdated-pins.py"
)
report = importlib.util.module_from_spec(spec)
spec.loader.exec_module(report)

NOW = datetime(2026, 11, 20, tzinfo=timezone.utc)


def make_tree(root):
    root = Path(root)
    files = {
        "packaging/aur/yay/PKGBUILD": "pkgname=yay\npkgver=13.1.0\npkgrel=3\n",
        "packaging/aur/cliamp/PKGBUILD": "pkgname=cliamp\npkgver=2.4.1\n",
        "packaging/aur/limine-mkinitcpio-hook/PKGBUILD":
            '_pkgver=1.40.0\n_extver=""\npkgver="${_pkgver}${_extver}"\n',
        "packaging/aur/odd/PKGBUILD": "pkgname=odd\nepoch=1\npkgver=2.0\n",
        "packaging/pult/PKGBUILD":
            "pkgver=0.4.1.r2.g7a703f1\n_commit=7a703f18d2a934d5c4821c24a723c0ad4863417d\n",
        "packaging/linecast/PKGBUILD": "pkgver=2.12.0\n",
        "packaging/subarchy-nvim/PKGBUILD": "_starter=803bc181d7c0d6d5eeba9274d9be49b287294d99\n",
        "packaging/subarchy-nvim/lazy-lock.json": json.dumps({
            "LazyVim": {"branch": "main", "commit": "a" * 40},
            "snacks.nvim": {"branch": "main", "commit": "b" * 40},
        }),
    }
    for name, text in files.items():
        path = root / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text)


def aur(**versions):
    return {"results": [{"Name": n, "Version": v} for n, v in versions.items()]}


def fixture_get(overrides=None, ahead=0):
    """A fake `get`: everything is current unless overridden."""
    table = {
        report.AUR_RPC: aur(**{"yay": "13.1.0-3", "cliamp": "2.4.1-1",
                               "limine-mkinitcpio-hook": "1.40.0-1", "odd": "1:2.0-1"}),
        "pult-release": {"tag_name": "v0.4.1"},
        "linecast-release": {"tag_name": "v2.12.0"},
    }
    table.update(overrides or {})

    def get(url):
        if url.startswith(report.AUR_RPC):
            return table[report.AUR_RPC]
        if url.endswith("/repos/subculture-collective/pult/releases/latest"):
            return table["pult-release"]
        if url.endswith("/repos/ashuttl/linecast/releases/latest"):
            return table["linecast-release"]
        if "/compare/" in url:
            repo = url.split("/repos/")[1].split("/compare/")[0]
            return {"ahead_by": table.get(("ahead", repo), ahead)}
        raise AssertionError(f"unexpected request {url}")

    return get


class VersionTests(unittest.TestCase):
    def test_vercmp(self):
        for a, b, want in (
            ("1.0", "1.0", 0), ("1.10", "1.9", 1), ("2.1.323", "2.1.330", -1),
            ("1.0", "1.0.1", -1), ("1.0rc1", "1.0", -1), ("251123", "260101", -1),
            ("580.196.07", "580.200.01", -1), ("1.0a", "1.0", -1),
        ):
            with self.subTest(a=a, b=b):
                self.assertEqual(report.vercmp(a, b), want)
                self.assertEqual(report.vercmp(b, a), -want)

    def test_epoch_beats_version(self):
        self.assertTrue(report.aur_newer(0, "9.9", "1:1.0-1"))
        self.assertFalse(report.aur_newer(1, "1.0", "9.9-1"))
        self.assertFalse(report.aur_newer(0, "13.1.0", "13.1.0-9"))


class PinReadingTests(unittest.TestCase):
    def test_pkgver_expands_helper_variables_and_epoch(self):
        with tempfile.TemporaryDirectory() as tmp:
            make_tree(tmp)
            pins = report.aur_pins(tmp)
        self.assertEqual(pins["limine-mkinitcpio-hook"], (0, "1.40.0"))
        self.assertEqual(pins["odd"], (1, "2.0"))
        self.assertEqual(pins["yay"], (0, "13.1.0"))

    def test_real_tree_has_every_pin_readable(self):
        root = Path(__file__).parents[2]
        pins = report.aur_pins(root)
        self.assertGreaterEqual(len(pins), 18)
        self.assertTrue(all(ver for _, ver in pins.values()), pins)
        lock = json.loads((root / "packaging/subarchy-nvim/lazy-lock.json").read_text())
        self.assertEqual(set(lock) - set(report.NVIM_REPOS), set())


class CollectTests(unittest.TestCase):
    def collect(self, get):
        with tempfile.TemporaryDirectory() as tmp:
            make_tree(tmp)
            return report.collect(tmp, get)

    def test_nothing_behind(self):
        sections, problems = self.collect(fixture_get())
        self.assertEqual(sum(len(r) for r in sections.values()), 0)
        self.assertEqual(problems, [])

    def test_each_kind_of_pin_is_reported(self):
        get = fixture_get({
            report.AUR_RPC: aur(**{"yay": "13.2.0-1", "cliamp": "2.4.1-1",
                                   "limine-mkinitcpio-hook": "1.40.0-1", "odd": "1:2.0-1"}),
            "pult-release": {"tag_name": "v0.5.0"},
            "linecast-release": {"tag_name": "v2.13.0"},
            ("ahead", "folke/snacks.nvim"): 12,
        })
        sections, problems = self.collect(get)
        self.assertEqual(problems, [])
        self.assertEqual(sections["Vendored AUR packages (packaging/aur)"], [("`yay`", "13.1.0", "13.2.0")])
        self.assertEqual(sections["Pult (packaging/pult)"][0][2], "0.5.0")
        self.assertEqual(sections["linecast (packaging/linecast)"][0][2], "2.13.0")
        nvim = sections["Neovim starter and plugin lock (packaging/subarchy-nvim)"]
        self.assertEqual([r[0] for r in nvim], ["`snacks.nvim`"])
        self.assertIn("12 commit", nvim[0][2])

    def test_pult_pinned_past_its_release_is_not_behind(self):
        sections, _ = self.collect(fixture_get({"pult-release": {"tag_name": "v0.4.1"}}))
        self.assertNotIn("Pult (packaging/pult)", sections)

    def test_missing_aur_package_and_unknown_plugin_are_reported_not_skipped(self):
        get = fixture_get({report.AUR_RPC: aur(**{"yay": "13.1.0-3"})})
        sections, problems = self.collect(get)
        self.assertTrue(any("`cliamp`" in p and "not found" in p for p in problems))

        with tempfile.TemporaryDirectory() as tmp:
            make_tree(tmp)
            lock = Path(tmp, "packaging/subarchy-nvim/lazy-lock.json")
            lock.write_text(json.dumps({"new.nvim": {"branch": "main", "commit": "c" * 40}}))
            _, problems = report.collect(tmp, fixture_get())
        self.assertTrue(any("new.nvim" in p for p in problems))

    def test_upstream_failure_is_a_problem_not_a_crash(self):
        base = fixture_get()

        def get(url):
            if "linecast" in url:
                raise urllib.error.URLError("offline")
            return base(url)

        sections, problems = self.collect(get)
        self.assertTrue(any(p.startswith("linecast") for p in problems))
        self.assertNotIn("linecast (packaging/linecast)", sections)

    def test_release_lookup_falls_back_to_tags_on_404(self):
        def get(url):
            if url.endswith("/releases/latest"):
                raise urllib.error.HTTPError(url, 404, "nf", {}, io.BytesIO())
            return [{"name": "v1.9"}, {"name": "v1.10"}, {"name": "nightly"}]

        self.assertEqual(report.latest_release("x/y", get), "1.10")


class IssueTests(unittest.TestCase):
    def run_sync(self, open_issues, behind, complete=True):
        calls = []

        def call(method, path, token, body=None):
            calls.append((method, path, body))
            if method == "GET":
                return open_issues
            return {"number": 77}

        return report.sync_issue("o/r", "t", "BODY", behind, complete, call), calls

    def test_opens_when_behind_and_none_exists(self):
        summary, calls = self.run_sync([], 3)
        self.assertEqual(summary, "opened #77")
        self.assertEqual(calls[1][0:2], ("POST", "/repos/o/r/issues"))
        self.assertEqual(calls[1][2]["title"], report.TITLE)

    def test_updates_changed_body_and_leaves_current_one(self):
        existing = {"number": 5, "title": report.TITLE, "body": "old"}
        summary, calls = self.run_sync([existing], 3)
        self.assertEqual(summary, "updated #5")
        self.assertEqual(calls[1][0], "PATCH")
        summary, calls = self.run_sync([dict(existing, body="BODY")], 3)
        self.assertIn("already current", summary)
        self.assertEqual(len(calls), 1)

    def test_other_issues_and_pull_requests_are_ignored(self):
        others = [{"number": 1, "title": "Outdated pins!", "body": ""},
                  {"number": 2, "title": report.TITLE, "body": "", "pull_request": {}}]
        summary, _ = self.run_sync(others, 1)
        self.assertEqual(summary, "opened #77")

    def test_closes_when_nothing_behind(self):
        existing = {"number": 5, "title": report.TITLE, "body": "old"}
        summary, calls = self.run_sync([existing], 0)
        self.assertEqual(summary, "closed #5")
        self.assertEqual(calls[-1][2], {"state": "closed"})

    def test_nothing_behind_and_no_issue_writes_nothing(self):
        summary, calls = self.run_sync([], 0)
        self.assertEqual(len(calls), 1)
        self.assertIn("no open issue", summary)

    def test_incomplete_run_never_closes_the_issue(self):
        existing = {"number": 5, "title": report.TITLE, "body": "old"}
        summary, calls = self.run_sync([existing], 0, complete=False)
        self.assertIn("left open", summary)
        self.assertEqual(len(calls), 1)


class MainTests(unittest.TestCase):
    def test_dry_run_prints_report_and_makes_no_issue_call(self):
        with tempfile.TemporaryDirectory() as tmp:
            make_tree(tmp)
            get = fixture_get({"linecast-release": {"tag_name": "v2.13.0"}})

            def forbidden(*args, **kwargs):
                raise AssertionError("dry run called the issue API")

            out = io.StringIO()
            with patch("sys.stdout", out), patch.dict("os.environ", {}, clear=True):
                code = report.main(["--dry-run", "--root", tmp], get=get, call=forbidden, now=NOW)
        self.assertEqual(code, 0)
        self.assertIn("| `linecast` | 2.12.0 | 2.13.0 |", out.getvalue())
        self.assertIn("as of 2026-11-20", out.getvalue())
        self.assertIn("dry run", out.getvalue())

    def test_live_run_without_token_refuses(self):
        with tempfile.TemporaryDirectory() as tmp:
            make_tree(tmp)
            with patch("sys.stdout", io.StringIO()), patch("sys.stderr", io.StringIO()), \
                    patch.dict("os.environ", {}, clear=True):
                code = report.main(["--root", tmp], get=fixture_get(), now=NOW)
        self.assertEqual(code, 2)


if __name__ == "__main__":
    unittest.main()
