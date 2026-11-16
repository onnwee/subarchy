#!/usr/bin/env python3
"""Exercise the hosted ISO's package resolver without pacman, root or a VM."""

import os
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]


class PackagePins(unittest.TestCase):
    def resolve(self, srcinfo: str, fail: bool = False):
        # Run the production selection/download block with command stand-ins.
        # The setup before it installs tools and keys; the code after it builds an ISO.
        script = (ROOT / "tools/ci/build-iso.sh").read_text()
        block = script.split("names=()\n", 1)[1].split('rm -f -- "$repo"/*.sig', 1)[0]
        with tempfile.TemporaryDirectory() as work:
            root = Path(work)
            package = root / "packaging/aur/fixture"
            package.mkdir(parents=True)
            (package / "PKGBUILD").touch()
            (package / ".SRCINFO").write_text(srcinfo)
            # The ISO builds core from source, not from the registry.
            core = root / "packaging/subarchy"
            core.mkdir()
            (core / "PKGBUILD").touch()
            (core / ".SRCINFO").write_text("pkgname = subarchy\n")
            stubs = r'''set -euo pipefail
root=$1
runuser() { shift 3; "$@"; }
makepkg() { cat .SRCINFO; }
pacman() {
  printf '%s\n' "$@" >"$root/pacman-args"
  [[ $FAIL_DOWNLOAD == 0 ]]
}
names=()
'''
            result = subprocess.run(["bash", "-c", stubs + block, "test", str(root)],
                                    env=os.environ | {"FAIL_DOWNLOAD": str(int(fail))},
                                    text=True, capture_output=True)
            args = (root / "pacman-args").read_text().splitlines()
            self.assertEqual(args[:4], ["--config", "/tmp/registry-pacman.conf", "-Syddw", "--noconfirm"])
            return result, args[4:]

    def test_pult_cannot_fall_back_to_the_older_published_release(self):
        result, targets = self.resolve("pkgver = 0.4.1.r2.g7a703f1\npkgrel = 1\npkgname = pult\npkgname = pult-debug\n")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(targets, ["pult=0.4.1.r2.g7a703f1-1", "pult-debug=0.4.1.r2.g7a703f1-1"])

    def test_split_packages_keep_the_epoch_and_revision(self):
        result, targets = self.resolve("pkgver = 580.196.07\npkgrel = 3\nepoch = 2\npkgname = utils\npkgname = opencl\n")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(targets, ["utils=2:580.196.07-3", "opencl=2:580.196.07-3"])

    def test_an_unpublished_version_stops_before_the_image_build(self):
        result, _ = self.resolve("pkgver = 1.2\npkgrel = 4\npkgname = fixture\n", fail=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("pinned package version", result.stderr)
        self.assertIn("packages workflow", result.stderr)


if __name__ == "__main__":
    unittest.main()
