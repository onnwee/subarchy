#!/usr/bin/env python3
"""Exercise the hosted ISO's package resolver and download recovery without pacman, root or a VM."""

import os
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]


# Pacman diagnostics from ISO jobs 44206 and 44215 (2026-11-16), without
# the runner timestamps. No infrastructure cause is inferred from this reset.
RESET = """error: failed retrieving file 'nvidia-580xx-utils-580.196.07-4-x86_64.pkg.tar.zst' from git.subcult.tv : Recv failure: Connection reset by peer
warning: failed to retrieve some files
error: failed to commit transaction (download library error)
 nvidia-580xx-utils-580.196.07-4-x86_64 downloading...
Errors occurred, no packages were upgraded.
"""
FIXTURE = "pkgver = 580.196.07\npkgrel = 4\nepoch = 2\npkgname = utils\npkgname = opencl\n"


class PackagePins(unittest.TestCase):
    def resolve(self, srcinfo: str, failures=(), status=1):
        # Run the production selection/download block with command stand-ins.
        # The setup before it installs tools and keys; the code after it builds an ISO.
        script = (ROOT / "tools/ci/build-iso.sh").read_text()
        block = script.split("names=()\n", 1)[1].split('rm -f -- "$repo"/*.sig', 1)[0]
        # Exercise the actual generated config without writing to shared /tmp paths.
        config = script.split("# shellcheck disable=SC2016\n", 1)[1].split("names=()\n", 1)[0]
        config = config.replace('>/tmp/registry-pacman.conf', '>"$root/registry-pacman.conf"')
        with tempfile.TemporaryDirectory(prefix="iso pins ") as work:
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
            cache = root / "build/repo"
            cache.mkdir(parents=True)
            good = cache / "already-downloaded.pkg.tar.zst"
            good.write_bytes(b"previously downloaded package fixture")
            for i, diagnostic in enumerate([*failures, ""], 1):
                (root / f"diagnostic-{i}").write_text(diagnostic)
                (root / f"status-{i}").write_text(str(status if i <= len(failures) else 0))
            stubs = r'''set -euo pipefail
root=$1
repo="$root/build/repo"
registry=https://git.subcult.tv/api/packages/subculture-collective/arch/stable
runuser() { shift 3; "$@"; }
makepkg() { cat .SRCINFO; }
stub_calls=0
pacman() {
  stub_calls=$((stub_calls + 1))
  printf '%s\0' "$@" >"$root/pacman-args-$stub_calls"
  printf '%s\n' "${LC_ALL-}" >"$root/pacman-locale-$stub_calls"
  cat "$root/diagnostic-$stub_calls" >&2
  return "$(cat "$root/status-$stub_calls")"
}
sleep() { printf '%s\n' "$@" >>"$root/delays"; }
'''
            result = subprocess.run(["bash", "-c", stubs + config + "names=()\n" + block, "test", str(root)],
                                    env=os.environ, text=True, capture_output=True)
            self.calls = [p.read_text().rstrip("\0").split("\0")
                          for p in sorted(root.glob("pacman-args-*"))]
            self.delays = (root / "delays").read_text().splitlines() if (root / "delays").exists() else []
            for args in self.calls:
                self.assertEqual(args, self.calls[0], "every retry must use the identical exact targets and policy")
                self.assertEqual(args[:4], ["--config", "/tmp/registry-pacman.conf", "-Syddw", "--noconfirm"])
            self.locales = [p.read_text().strip() for p in sorted(root.glob("pacman-locale-*"))]
            self.assertEqual(good.read_bytes(), b"previously downloaded package fixture")
            self.assertEqual((root / "registry-pacman.conf").read_text(),
                             f"[options]\nArchitecture = auto\nDBPath = /tmp/registry-db\nCacheDir = {cache}\n\n"
                             "[subarchy]\nSigLevel = Required\n"
                             "Server = https://git.subcult.tv/api/packages/subculture-collective/arch/stable/$arch\n")
            return result, self.calls[-1][4:]

    def test_pult_cannot_fall_back_to_the_older_published_release(self):
        result, targets = self.resolve("pkgver = 0.4.1.r2.g7a703f1\npkgrel = 1\npkgname = pult\npkgname = pult-debug\n")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(targets, ["pult=0.4.1.r2.g7a703f1-1", "pult-debug=0.4.1.r2.g7a703f1-1"])
        self.assertEqual(len(self.calls), 1)
        self.assertEqual(self.delays, [])

    def test_split_packages_keep_the_epoch_and_revision(self):
        result, targets = self.resolve("pkgver = 580.196.07\npkgrel = 3\nepoch = 2\npkgname = utils\npkgname = opencl\n")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(targets, ["utils=2:580.196.07-3", "opencl=2:580.196.07-3"])

    def test_an_unpublished_version_stops_before_the_image_build(self):
        diagnostic = "error: target not found: fixture=1.2-4\n"
        result, _ = self.resolve("pkgver = 1.2\npkgrel = 4\npkgname = fixture\n", [diagnostic])
        self.assertNotEqual(result.returncode, 0)
        self.assertIn(diagnostic, result.stderr)
        self.assertEqual(len(self.calls), 1)
        self.assertEqual(self.delays, [])

    def test_observed_reset_recovers_with_the_same_pins_and_cache(self):
        result, targets = self.resolve(FIXTURE, [RESET])
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(targets, ["utils=2:580.196.07-4", "opencl=2:580.196.07-4"])
        self.assertEqual(len(self.calls), 2)
        self.assertEqual(self.delays, ["1"])
        self.assertEqual(self.locales, ["C", "C"])
        self.assertIn(RESET, result.stderr)

    def test_third_attempt_can_recover(self):
        result, _ = self.resolve(FIXTURE, [RESET, RESET])
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(len(self.calls), 3)
        self.assertEqual(self.delays, ["1", "2"])

    def test_reset_exhaustion_keeps_the_diagnostic_and_exit_status(self):
        result, _ = self.resolve(FIXTURE, [RESET] * 3, status=17)
        self.assertEqual(result.returncode, 17)
        self.assertEqual(len(self.calls), 3)
        self.assertEqual(self.delays, ["1", "2"])
        self.assertEqual(result.stderr.count(RESET), 3)
        self.assertIn("transport failed after 3 attempts", result.stderr)
        self.assertNotIn("not in the stable registry", result.stderr)

    def test_permanent_and_unknown_errors_are_not_retried_even_with_a_reset(self):
        diagnostics = [
            "error: target not found: utils=2:580.196.07-4",
            "error: failed retrieving file 'fixture' from registry : The requested URL returned error: 401",
            "error: failed retrieving file 'fixture' from registry : The requested URL returned error: 403",
            "error: failed retrieving file 'fixture' from registry : The requested URL returned error: 404",
            "error: failed retrieving file 'fixture' from registry : SSL certificate problem: certificate has expired",
            'error: utils: signature from "fixture signer" is unknown trust',
            "error: failed to commit transaction (invalid or corrupted package (PGP signature))",
            "error: failed retrieving file 'fixture' from registry : Failure writing output to destination",
            "error: could not open file: No space left on device",
            "error: invalid option '--bad-argument'",
            "error: failed to init transaction (unable to lock database)",
            "error: unrecognized failure",
        ]
        for diagnostic in diagnostics:
            for prefix in ["", RESET]:
                with self.subTest(diagnostic=diagnostic, mixed=bool(prefix)):
                    result, _ = self.resolve(FIXTURE, [prefix + diagnostic + "\n"], status=23)
                    self.assertEqual(result.returncode, 23)
                    self.assertEqual(len(self.calls), 1)
                    self.assertEqual(self.delays, [])
                    self.assertIn(diagnostic, result.stderr)

    def test_permanent_failure_after_a_reset_stops_the_recovery(self):
        diagnostic = "error: failed to commit transaction (invalid or corrupted package (PGP signature))\n"
        result, _ = self.resolve(FIXTURE, [RESET, diagnostic], status=23)
        self.assertEqual(result.returncode, 23)
        self.assertEqual(len(self.calls), 2)
        self.assertEqual(self.delays, ["1"])
        self.assertIn(RESET, result.stderr)
        self.assertIn(diagnostic, result.stderr)
        self.assertNotIn("transport failed after", result.stderr)

    def test_generic_download_library_error_alone_is_not_retried(self):
        for diagnostic in ["error: failed to commit transaction (download library error)\n", ""]:
            with self.subTest(diagnostic=diagnostic):
                result, _ = self.resolve(FIXTURE, [diagnostic], status=19)
                self.assertEqual(result.returncode, 19)
                self.assertEqual(len(self.calls), 1)
                self.assertEqual(self.delays, [])

    def test_signature_key_setup_is_unchanged(self):
        script = (ROOT / "tools/ci/build-iso.sh").read_text()
        self.assertIn('''install -Dm644 "$keyring/registry.key" /usr/share/pacman/keyrings/subarchy.gpg
install -Dm644 "$keyring/subarchy-trusted" /usr/share/pacman/keyrings/subarchy-trusted
install -Dm644 "$keyring/subarchy-revoked" /usr/share/pacman/keyrings/subarchy-revoked
pacman-key --init
pacman-key --populate archlinux subarchy
''', script)


if __name__ == "__main__":
    unittest.main()
