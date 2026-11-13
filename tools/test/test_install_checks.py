#!/usr/bin/env python3
"""The install test's check functions that depend on the machine it runs on."""

import contextlib
import importlib.util
import io
import json
import os
from pathlib import Path
import re
import shutil
import sys
import tempfile
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


def lock_run(**prompt) -> str:
    """What the lock check prints: locked, after the shell died, the prompt, the units."""
    base = {"locked": True, "secure": True, "prompt": False, "playing": 1, "screensaver": True,
            "fingerprint": "off", "fingerprintChecking": False}
    shown = base | {"prompt": True, "playing": 0, "screensaver": False} | prompt
    return f"{json.dumps(base)}\n---\n{json.dumps(base)}\n---\n{json.dumps(shown)}\n---\ninactive\nactive\n"


class Lock(unittest.TestCase):
    def test_a_lock_without_a_fingerprint_check_passes(self):
        self.assertTrue(install_test.lock_ok(lock_run()))

    def test_a_fingerprint_check_without_a_reader_fails(self):
        self.assertFalse(install_test.lock_ok(lock_run(fingerprint="ready", fingerprintChecking=True)))
        self.assertFalse(install_test.lock_ok(lock_run(fingerprintChecking=True)))
        self.assertFalse(install_test.lock_ok(lock_run(fingerprint=None)), "a lock that does not report it")


APP_STATE = "DOLPHIN=0\nAPPLY=0\nGTK=1\nADW=1\nKDE_ENTRY=1\n'adw-gtk3-dark'\nDRACULA=0\nKDE=1\nRESTORE=0\n"
# Pult 0.3.0 has no kde entry: no Dracula round, Dolphin on the packaged scheme.
APP_STATE_NO_KDE = "DOLPHIN=0\nAPPLY=0\nGTK=1\nADW=1\nKDE_ENTRY=0\n'adw-gtk3-dark'\n"
APP_WINDOWS = {"dolphin": "\tclass: org.kde.dolphin\n\tfullscreen: 2\n", "gtk": "\tclass: python3\n\tfullscreen: 2\n"}


def apps(**changes) -> dict:
    """A passing app-colours record, with some of its parts replaced."""
    return {"state": APP_STATE, "windows": dict(APP_WINDOWS), "themed": {"dolphin": True, "gtk": True}} | changes


class AppColours(unittest.TestCase):
    def test_both_apps_full_screen_in_the_palette_pass(self):
        self.assertTrue(install_test.app_colours_ok(apps()))

    def test_a_pult_without_the_kde_entry_passes_on_the_packaged_scheme(self):
        self.assertTrue(install_test.app_colours_ok(apps(state=APP_STATE_NO_KDE)))

    def test_an_app_in_its_own_colours_fails(self):
        self.assertFalse(install_test.app_colours_ok(apps(themed={"dolphin": False, "gtk": True})))
        self.assertFalse(install_test.app_colours_ok(apps(themed={"dolphin": True, "gtk": False})))

    def test_a_missing_target_or_the_old_gtk_theme_fails(self):
        for old, new in (("\nKDE=1", "\nKDE=0"), ("GTK=1", "GTK="), ("APPLY=0", "APPLY=1"), ("ADW=1", "ADW="),
                         ("DRACULA=0", "DRACULA=1"), ("RESTORE=0", "RESTORE=1"), ("'adw-gtk3-dark'", "'Adwaita-dark'")):
            with self.subTest(old=old):
                self.assertFalse(install_test.app_colours_ok(apps(state=APP_STATE.replace(old, new))))

    def test_no_word_on_the_kde_entry_fails(self):
        self.assertFalse(install_test.app_colours_ok(apps(state=APP_STATE_NO_KDE.replace("KDE_ENTRY=0\n", ""))))

    def test_a_window_that_never_showed_stayed_tiled_or_was_maximized_fails(self):
        self.assertFalse(install_test.app_colours_ok(apps(windows=APP_WINDOWS | {"dolphin": ""})))
        self.assertFalse(install_test.app_colours_ok(apps(windows={"dolphin": APP_WINDOWS["dolphin"]})))
        for mode in ("0", "1"):
            with self.subTest(mode=mode):
                windows = APP_WINDOWS | {"gtk": f"\tclass: python3\n\tfullscreen: {mode}\n"}
                self.assertFalse(install_test.app_colours_ok(apps(windows=windows)))


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



def theme_probe(ukis: str, exit_code: int = 0) -> str:
    """The theme_system output: the privileged run, apply-system again, the UKI ages, the files."""
    return ("wrote /usr/share/sddm/themes/subarchy/theme.conf\nwrote /etc/chromium/policies/managed/color.json\n"
            f"the splash changed; rebuilding the initramfs (limine-mkinitcpio)\nSYSTEM_APPLY_EXIT={exit_code}\n---\n"
            "palette: x\nunchanged /boot/limine.conf\nthe splash is unchanged; no initramfs rebuild\n---\n"
            f"{ukis}\n---\n1\n1\nsubarchy-user\n1\n")


class ThemeSystem(unittest.TestCase):
    def test_every_uki_rebuilt_passes(self):
        self.assertTrue(install_test.theme_system_ok(theme_probe("2\n0")))

    def test_a_uki_left_over_or_none_rebuilt_fails(self):
        self.assertFalse(install_test.theme_system_ok(theme_probe("1\n1")))
        self.assertFalse(install_test.theme_system_ok(theme_probe("0\n2")))
        self.assertFalse(install_test.theme_system_ok(theme_probe("")))

    def test_a_failed_privileged_run_fails(self):
        self.assertFalse(install_test.theme_system_ok(theme_probe("2\n0", exit_code=1)))


class DockerTui(unittest.TestCase):
    # pkaction --verbose, as checked with polkit 126 (2026-11-13), then the
    # root side and the desktop entry.
    PKACTION = (" implicit active: auth_admin_keep\n"
                " annotation: org.freedesktop.policykit.exec.path -> /usr/lib/subcult/lazydocker-root\n")

    def test_the_action_root_side_and_entry_pass(self):
        self.assertTrue(install_test.docker_tui_ok(self.PKACTION + "ROOT_SIDE\n1\n"))

    def test_a_missing_part_fails(self):
        self.assertFalse(install_test.docker_tui_ok("ROOT_SIDE\n1\n"))
        self.assertFalse(install_test.docker_tui_ok(self.PKACTION + "1\n"))
        self.assertFalse(install_test.docker_tui_ok(self.PKACTION.replace("_keep", "") + "ROOT_SIDE\n1\n"))
        self.assertFalse(install_test.docker_tui_ok(self.PKACTION + "ROOT_SIDE\n0\n"))


class TailscaleHelper(unittest.TestCase):
    # No operator in `tailscale debug prefs`, `tailscale down` refused to the
    # user, pkaction --verbose (polkit 126 format), the helper, the receiver
    # (wanted by tailscaled, enabled, running).
    PKACTION = (" implicit any: auth_admin\n implicit inactive: auth_admin\n implicit active: yes\n"
                " annotation: org.freedesktop.policykit.exec.path -> /usr/lib/subcult/tailscale-helper\n")

    def out(self, operators="0", user="USER_DENIED", pkaction=PKACTION, tail="HELPER\nWANTED\nenabled\nactive\n"):
        return f"{operators}\n{user}\n{pkaction}{tail}"

    def test_no_operator_helper_and_receiver_pass(self):
        self.assertTrue(install_test.tailscale_helper_ok(self.out()))

    def test_an_operator_or_a_user_in_control_fails(self):
        self.assertFalse(install_test.tailscale_helper_ok(self.out(operators="1")))
        self.assertFalse(install_test.tailscale_helper_ok(self.out(user="USER_CONTROLS")))

    def test_a_password_free_action_outside_the_session_or_another_program_fails(self):
        self.assertFalse(install_test.tailscale_helper_ok(self.out(pkaction=self.PKACTION.replace("any: auth_admin", "any: yes"))))
        self.assertFalse(install_test.tailscale_helper_ok(self.out(pkaction=self.PKACTION.replace("active: yes", "active: auth_admin"))))
        self.assertFalse(install_test.tailscale_helper_ok(self.out(pkaction=self.PKACTION.replace("tailscale-helper", "x"))))

    def test_a_missing_helper_or_receiver_fails(self):
        self.assertFalse(install_test.tailscale_helper_ok(self.out(tail="WANTED\nenabled\nactive\n")))
        self.assertFalse(install_test.tailscale_helper_ok(self.out(tail="HELPER\nenabled\nactive\n")))
        self.assertFalse(install_test.tailscale_helper_ok(self.out(tail="HELPER\nWANTED\ndisabled\ninactive\n")))
        self.assertFalse(install_test.tailscale_helper_ok(self.out(tail="HELPER\nWANTED\nenabled\nfailed\n")))


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


class WidgetHidden(unittest.TestCase):
    def test_loaded_but_not_shown(self):
        status = '{"loaded": {"Virtual-1": ["subcult.menu", "subcult.ht3"]}, "shown": {"Virtual-1": ["subcult.menu"]}}'
        self.assertTrue(install_test.widget_hidden("noise\n" + status + "\n", "subcult.ht3"))

    def test_shown_missing_or_unreadable_fails(self):
        shown = '{"loaded": {"Virtual-1": ["subcult.ht3"]}, "shown": {"Virtual-1": ["subcult.ht3"]}}'
        self.assertFalse(install_test.widget_hidden(shown, "subcult.ht3"))
        self.assertFalse(install_test.widget_hidden('{"loaded": {"Virtual-1": []}, "shown": {}}', "subcult.ht3"))
        self.assertFalse(install_test.widget_hidden("", "subcult.ht3"))
        self.assertFalse(install_test.widget_hidden("not json", "subcult.ht3"))
        self.assertFalse(install_test.widget_hidden('{"loaded": []}', "subcult.ht3"))


class FullBar(unittest.TestCase):
    layout = install_test.ROOT / "default" / "shell" / "bar.json"

    def full(self) -> list[str]:
        sections = json.loads(self.layout.read_text())["layout"]
        return sections["left"] + sections["center"] + sections["right"]

    def status(self, **loaded) -> str:
        return "noise\n" + json.dumps({"loaded": loaded})

    def test_every_default_widget_on_one_bar(self):
        self.assertTrue(install_test.full_bar_ok(self.status(**{"Virtual-1": self.full()})))
        # A machine layer may add widgets; a second output may be minimal.
        extra = self.full() + ["subcult.power-profile"]
        self.assertTrue(install_test.full_bar_ok(self.status(**{"Virtual-1": extra, "Virtual-2": ["subcult.workspaces"]})))

    def test_a_missing_widget_or_unreadable_status_fails(self):
        self.assertFalse(install_test.full_bar_ok(self.status(**{"Virtual-1": self.full()[1:]})))
        self.assertFalse(install_test.full_bar_ok(self.status(**{"Virtual-1": ["subcult.menu", "subcult.clock"]})))
        self.assertFalse(install_test.full_bar_ok(self.status()))
        self.assertFalse(install_test.full_bar_ok(""))
        self.assertFalse(install_test.full_bar_ok("not json"))


class BarLayers(unittest.TestCase):
    def test_one_layer_per_monitor(self):
        self.assertTrue(install_test.bar_layers_ok("1\n1\n"))
        self.assertTrue(install_test.bar_layers_ok("2\n2"))

    def test_mismatch_none_or_unreadable_fails(self):
        self.assertFalse(install_test.bar_layers_ok("1\n2\n"))
        self.assertFalse(install_test.bar_layers_ok("0\n0\n"))
        self.assertFalse(install_test.bar_layers_ok("1\n"))
        self.assertFalse(install_test.bar_layers_ok("x\n1\n"))


class WorkspaceDispatch(unittest.TestCase):
    def test_built_from_the_shell_module(self):
        self.assertEqual(install_test.workspace_dispatch(3), 'hl.dsp.focus({ workspace = "3" })')


class Budgets(unittest.TestCase):
    def setUp(self):
        self.dir = Path(tempfile.mkdtemp())
        self.addCleanup(shutil.rmtree, self.dir)
        self.vm, self.budget = install_test.VM, install_test.IDLE_BUDGET
        install_test.VM, install_test.IDLE_BUDGET = self.dir, self.dir / "idle-budget.json"
        self.addCleanup(setattr, install_test, "VM", self.vm)
        self.addCleanup(setattr, install_test, "IDLE_BUDGET", self.budget)
        install_test.IDLE_BUDGET.write_text('{"packages": 100, "session_rss_kb": null}\n')

    def test_over_budget_fails_and_an_unbudgeted_key_passes(self):
        self.assertTrue(install_test.budget_ok("packages", 120, 5))
        self.assertFalse(install_test.budget_ok("packages", 121, 5))
        self.assertTrue(install_test.budget_ok("packages", 108, 8))
        with contextlib.redirect_stdout(io.StringIO()):
            self.assertTrue(install_test.budget_ok("session_rss_kb", 4000))
        self.assertFalse(install_test.budget_ok("packages", -1))

    def test_every_measurement_is_recorded_budgeted_or_not(self):
        (self.dir / "budgets.json").write_text('{"stale": 1}\n')
        install_test.record_budgets({"packages": 121, "session_rss_kb": 4000, "shell_main_thread_wakeups_per_minute": -1})
        self.assertEqual(json.loads((self.dir / "budgets.json").read_text()), {"packages": 121, "session_rss_kb": 4000})


if __name__ == "__main__":
    unittest.main()
