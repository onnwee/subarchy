#!/usr/bin/env python3
"""The install test's check functions that depend on the machine it runs on."""

import importlib.util
import os
from pathlib import Path
import re
import sys
import threading
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


class ThreadWakeups(unittest.TestCase):
    def test_threads_that_come_or_go_do_not_count(self):
        before = "100 50\n101 4000\n102 7\n"
        after = "100 60\n102 9\n103 300\n"  # 101 exited, 103 started
        self.assertEqual(install_test.thread_wakeups(before, after), 12)

    def test_an_unreadable_sample_is_no_answer(self):
        self.assertIsNone(install_test.thread_wakeups("", "100 60\n"))
        self.assertIsNone(install_test.thread_wakeups("100 50\n", "100 \n"))
        self.assertEqual(install_test.thread_wakeups("100 50\n101 \n", "100 51\n101 8\n"), 1)


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


class LoginShell:
    """A stand-in for QEMU with zsh on its serial console.

    Like the real one after a login, it loses the first `lose` bytes typed
    at it. A line that ends inside a quote continues on the next line, and
    Ctrl-C abandons it. A complete line that execs bash prints the prompt.
    """

    def __init__(self, lose: int):
        self.lose = lose
        read, self.out = os.pipe()
        self.stdout = os.fdopen(read, "rb", buffering=0)
        self.stdin = self
        self.line, self.quoted = "", False
        self.bash, self.cols = False, 80
        self.lock = threading.Lock()

    def poll(self):
        return None

    def flush(self):
        pass

    def write(self, data: bytes) -> None:
        with self.lock:
            for ch in data.decode():
                if self.lose:
                    self.lose -= 1
                elif ch == "\x03":
                    self.line, self.quoted = "", False
                elif ch == "\n" and not self.quoted:
                    if re.search(r"(^|; )stty cols 1000(;|$)", self.line):
                        self.cols = 1000
                    self.bash = self.bash or ("exec env" in self.line and "bash" in self.line)
                    if self.bash:
                        os.write(self.out, b"SUBARCHY-READY> ")
                    self.line = ""
                else:
                    self.quoted ^= ch == "'"
                    self.line += ch


class ClaimPrompt(unittest.TestCase):
    def claim(self, lose: int) -> LoginShell:
        shell = LoginShell(lose)
        self.addCleanup(shell.stdout.close)
        self.addCleanup(os.close, shell.out)
        install_test.Serial(shell, open(os.devnull, "wb")).claim_prompt(2, attempt=0.2)
        return shell

    def test_a_shell_that_takes_every_byte_gives_the_prompt(self):
        self.claim(0)

    def test_a_first_try_cut_inside_its_quotes_does_not_block_the_retries(self):
        # Seen on the Secure Boot stage, 2026-11-10: zsh got the command from
        # "ARCHY''-READY> ' bash" on, an odd number of quotes, and held every
        # retry as a continuation line until the stage timed out.
        self.claim(43)

    def test_a_first_try_that_lost_its_first_letter_still_widens_the_terminal(self):
        # Seen on the first boot, 2026-11-10: "tty cols 1000; exec ... bash"
        # reached zsh. bash started, the terminal stayed 80 columns wide, and
        # findmnt cut the mount options the checks read.
        self.assertEqual(self.claim(1).cols, 1000)


LOCKED = '{"locked":true,"secure":true,"prompt":false,"checking":false}'
HIDDEN = {"before": True, "locked": False, "killed": False, "replaced": False, "unlocked": True}


def crash(**changes) -> dict:
    """A passing lock-crash record, with some of its parts replaced."""
    return {"first": f"{LOCKED}\n1200\n", "second": f"{LOCKED}\n1311\n1\n", "end": "inactive\n", "shown": dict(HIDDEN)} | changes


class LockCrash(unittest.TestCase):
    def test_a_replacement_that_holds_the_lock_and_unlocks_passes(self):
        self.assertTrue(install_test.lock_crash_ok(crash()))

    def test_the_same_or_no_process_after_the_kill_fails(self):
        self.assertFalse(install_test.lock_crash_ok(crash(second=f"{LOCKED}\n1200\n1\n")))
        self.assertFalse(install_test.lock_crash_ok(crash(second=f"{LOCKED}\n0\n1\n")))
        self.assertFalse(install_test.lock_crash_ok(crash(second=f"{LOCKED}\n1311\n0\n")))
        self.assertFalse(install_test.lock_crash_ok(crash(second="No running instances\n0\n5\n")))

    def test_a_replacement_the_compositor_did_not_accept_fails(self):
        refused = LOCKED.replace('"secure":true', '"secure":false')
        self.assertFalse(install_test.lock_crash_ok(crash(second=f"{refused}\n1311\n1\n")))

    def test_the_desktop_showing_while_locked_fails(self):
        for moment in ("locked", "killed", "replaced"):
            with self.subTest(moment=moment):
                self.assertFalse(install_test.lock_crash_ok(crash(shown=HIDDEN | {moment: True})))

    def test_no_marker_before_the_lock_or_after_the_unlock_fails(self):
        self.assertFalse(install_test.lock_crash_ok(crash(shown=HIDDEN | {"before": False})))
        self.assertFalse(install_test.lock_crash_ok(crash(shown=HIDDEN | {"unlocked": False})))
        self.assertFalse(install_test.lock_crash_ok(crash(end="active\n")))


class QuietestMinute(unittest.TestCase):
    """The idle sample: other programs waking the shell only add to a minute."""

    def samples(self, *minutes):
        left = list(minutes)
        self.taken = 0

        def sample():
            self.taken += 1
            return left.pop(0)
        return sample

    def test_a_quiet_first_minute_is_the_only_one_taken(self):
        self.assertEqual(install_test.quietest_minute(self.samples((1, 40), (0, 0))), (1, 40))
        self.assertEqual(self.taken, 1)

    def test_a_noisy_minute_is_sampled_again_and_the_quietest_judged(self):
        self.assertEqual(install_test.quietest_minute(self.samples((900, 950), (2, 30))), (2, 30))
        self.assertEqual(self.taken, 2)

    def test_a_shell_that_wakes_every_minute_is_still_reported_over_budget(self):
        main, total = install_test.quietest_minute(self.samples((900, 950), (800, 990), (850, 900)))
        self.assertEqual((main, total), (800, 990))
        self.assertEqual(self.taken, 3)
        self.assertFalse(install_test.idle_ok(main))

    def test_a_failed_reading_is_a_failure(self):
        self.assertEqual(install_test.quietest_minute(self.samples(None)), (-1, -1))
        self.assertFalse(install_test.idle_ok(-1))


class GreeterSession(unittest.TestCase):
    def test_nothing_of_the_desktop_for_sddm_passes(self):
        ok = "PROCS=0\nUPDATE=0\nMANAGER=active\nTARGET=inactive inactive \n"
        self.assertTrue(install_test.greeter_session_ok(ok))
        self.assertTrue(install_test.greeter_session_ok("PROCS=0\nUPDATE=0\nMANAGER=inactive\nTARGET=\n"))

    def test_a_bar_a_target_or_an_update_window_fails(self):
        self.assertFalse(install_test.greeter_session_ok("PROCS=2\nUPDATE=0\nMANAGER=active\nTARGET=inactive inactive\n"))
        self.assertFalse(install_test.greeter_session_ok("PROCS=0\nUPDATE=1\nMANAGER=active\nTARGET=inactive inactive\n"))
        self.assertFalse(install_test.greeter_session_ok("PROCS=0\nUPDATE=0\nMANAGER=active\nTARGET=activating active\n"))
        self.assertFalse(install_test.greeter_session_ok("PROCS=0\nUPDATE=0\nMANAGER=active\nTARGET=\n"))
        self.assertFalse(install_test.greeter_session_ok(""))

    def test_screensaver_unit(self):
        self.assertTrue(install_test.screensaver_ok("exec\n1\n"))
        self.assertFalse(install_test.screensaver_ok("oneshot\n1\n"))
        self.assertFalse(install_test.screensaver_ok("exec\n0\n"))
        self.assertFalse(install_test.screensaver_ok("exec\n"))


if __name__ == "__main__":
    unittest.main()
