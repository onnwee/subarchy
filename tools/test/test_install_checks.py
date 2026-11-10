#!/usr/bin/env python3
"""The install test's check functions that depend on the machine it runs on."""

import importlib.util
from pathlib import Path
import sys
import unittest

ISO = Path(__file__).parents[1] / "iso"
sys.path.insert(0, str(ISO))
spec = importlib.util.spec_from_file_location("install_test", ISO / "install-test.py")
install_test = importlib.util.module_from_spec(spec)
spec.loader.exec_module(install_test)

def probe(vendor: str, installed: list[str]) -> str:
    """What the guest prints: the installed hardware packages, then `subcult hw info`."""
    return ("".join(p + "\n" for p in installed)
            + f"CPU:       {vendor}\nVM:        QEMU\nHybrid:    false\nMatches:   \n")


class HardwarePackages(unittest.TestCase):
    def test_intel_guest_needs_intel_microcode_and_thermald(self):
        self.assertTrue(install_test.hw_ok(probe("GenuineIntel", ["intel-ucode", "thermald"])))
        self.assertFalse(install_test.hw_ok(probe("GenuineIntel", ["intel-ucode"])))
        self.assertFalse(install_test.hw_ok(probe("GenuineIntel", ["amd-ucode"])))

    def test_amd_guest_needs_amd_microcode_and_no_thermald(self):
        self.assertTrue(install_test.hw_ok(probe("AuthenticAMD", ["amd-ucode"])))
        self.assertFalse(install_test.hw_ok(probe("AuthenticAMD", ["intel-ucode", "thermald"])))
        self.assertFalse(install_test.hw_ok(probe("AuthenticAMD", ["amd-ucode", "thermald"])))

    def test_firmware_or_an_unknown_machine_fails(self):
        self.assertFalse(install_test.hw_ok(probe("AuthenticAMD", ["amd-ucode", "linux-firmware"])))
        self.assertFalse(install_test.hw_ok(probe("AuthenticAMD", ["amd-ucode"]).replace("QEMU", "none")))
        self.assertFalse(install_test.hw_ok(probe("CentaurHauls", [])))


if __name__ == "__main__":
    unittest.main()
