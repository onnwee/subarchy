#!/usr/bin/env python3
"""Install Subarchy into a QEMU disk from the live ISO, then boot it and check it.

1. Boots the ISO with an empty virtio disk, shares this checkout (read-only)
   and a persistent package cache over 9p, and runs install/subarchy-install
   from the checkout, so installer changes need no ISO rebuild.
2. Boots the disk alone, types the LUKS passphrase on the serial console,
   logs in as the new user and checks the result.

The disk, its OVMF variables and the test credentials stay in build/vm/.
They are throwaway test values for a VM, not secrets.

Usage: tools/iso/install-test.py ISO [--skip-install] [--timeout-install 2400]
"""

from __future__ import annotations

import argparse
import atexit
import json
import os
import re
import shlex
import shutil
import subprocess
import sys
import tempfile
import time
from pathlib import Path

from vmlib import ANSI, OVMF_CODE, OVMF_VARS, Serial, colours_in, distinct_colours, has_colour, qemu_command, screendump

ROOT = Path(__file__).resolve().parents[2]
VM = ROOT / "build" / "vm"
_SOCKETS: Path | None = None


def socket_path(name: str) -> Path:
    """A Unix socket path under the 108-byte limit: build/vm can sit too deep
    for one, so sockets go to a short runtime directory, removed at exit."""
    global _SOCKETS
    if _SOCKETS is None:
        _SOCKETS = Path(tempfile.mkdtemp(prefix="subarchy-vm-", dir=os.environ.get("XDG_RUNTIME_DIR")))
        atexit.register(shutil.rmtree, _SOCKETS, True)
    return _SOCKETS / name
CACHE = ROOT / "build" / "pkgcache"
IDLE_BUDGET = ROOT / "tools" / "iso" / "idle-budget.json"


def budget_ok(key: str, value: int, slack: int = 0) -> bool:
    """A measurement against its budget in tools/iso/idle-budget.json (ADR 0054).

    The first run records its measurement as the budget (null in the file),
    written to build/vm/budgets.json to copy over; later runs fail above the
    larger of budget × 1.2 and budget + slack.
    """
    import json
    if value < 0:
        return False
    data = json.loads(IDLE_BUDGET.read_text())
    budget = data.get(key)
    if budget is None:
        print(f"install-test: no budget for {key} yet; measured {value}, record it in {IDLE_BUDGET}")
        recorded = VM / "budgets.json"
        seen = json.loads(recorded.read_text()) if recorded.exists() else {}
        seen[key] = value
        recorded.write_text(json.dumps(seen) + "\n")
        return True
    return value <= max(budget * 1.2, budget + slack)


def idle_ok(switches: int) -> bool:
    """The shell's idle wake-ups per minute (ADR 0054), with three of slack.

    Counted on the shell's main thread, where its timers and event sources
    run. Every frame also wakes the render thread and, in a VM, llvmpipe's
    worker threads, so the total over all threads is reported but not
    budgeted (a probe on 2026-11-07 saw 10 main-thread wake-ups and 48-58
    in all for a quiet minute).
    """
    return budget_ok("shell_main_thread_wakeups_per_minute", switches, 3)


def thread_wakeups(before: str, after: str) -> int | None:
    """Wake-ups over all threads between two samples of `tid count` lines.

    Only threads in both samples count. A thread that exited in between took
    its count with it, and a plain difference of two sums came out as 60, 0
    and -10 for the same build; a thread that started in between has no
    earlier count. None when a sample has no usable line.
    """
    def read(text: str) -> dict[str, int]:
        rows = (line.split() for line in text.splitlines())
        return {r[0]: int(r[1]) for r in rows if len(r) == 2 and r[0].isdigit() and r[1].isdigit()}
    first, second = read(before), read(after)
    if not first or not second:
        return None
    return sum(second[tid] - count for tid, count in first.items() if tid in second)


def quietest_minute(sample, attempts: int = 3) -> tuple[int, int]:
    """The quietest of up to `attempts` idle minutes, as (main thread, all threads).

    `sample()` waits a minute and returns both counts, or None when they
    could not be read. Something else waking the shell (a D-Bus signal, a
    job still finishing after the tests before) only ever adds to a minute:
    runs of the same build read 11 to 16 against a limit of 15. A timer or
    a polling loop shows in every minute, so the quietest one is judged,
    and sampling stops at the first minute within budget.
    """
    best = (-1, -1)
    for _ in range(attempts):
        got = sample()
        if got is None:
            return (-1, -1)
        if best[0] < 0 or got[0] < best[0]:
            best = got
        if idle_ok(best[0]):
            break
    return best
USER = "tester"
PASSWORD = "subarchy-test"
PASSPHRASE = "subarchy-disk-test"


def write_config() -> None:
    VM.mkdir(parents=True, exist_ok=True)
    (VM / "user-password").write_text(PASSWORD + "\n")
    (VM / "luks-passphrase").write_text(PASSPHRASE + "\n")
    (VM / "install.conf").write_text(
        "# Written by tools/iso/install-test.py\n"
        "DISK=/dev/vda\n"
        "HOSTNAME=subarchy-vm\n"
        f"USERNAME={USER}\n"
        "USER_PASSWORD_FILE=/run/src/build/vm/user-password\n"
        "LUKS_PASSPHRASE_FILE=/run/src/build/vm/luks-passphrase\n"
        "TIMEZONE=America/Chicago\n"
        "SUBARCHY_REPO=file:///run/src/build/repo\n"
        "PACKAGE_CACHE=/run/pkgcache\n"
        "KERNEL_CMDLINE_EXTRA=console=tty0 console=ttyS0,115200\n"
    )


def start(cmd: list[str], log_path: Path):
    log = open(log_path, "wb")
    proc = subprocess.Popen(cmd, stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    return proc, Serial(proc, log), log


def stop(proc: subprocess.Popen, log) -> None:
    try:
        proc.wait(timeout=90)
    except subprocess.TimeoutExpired:
        proc.kill()
        proc.wait()
    log.close()


def guided(serial: Serial, timeout: float) -> str:
    """Answer subarchy-setup's questions on the serial console."""
    serial.buf = b""
    serial.send(
        "subarchy-setup --cmdline-extra 'console=tty0 console=ttyS0,115200'"
        " --package-cache /run/pkgcache --batch; echo EXIT=$?\n"
    )
    answers = [
        (rb"Keyboard layout \[us\]: ", ""),
        (rb"disk number: ", "1"),
        (rb"Computer name \[subarchy\]: ", "subarchy-vm"),
        (rb"Your user name: ", USER),
        (rb"Password for \w+: ", PASSWORD),
        (rb"Password for \w+ again: ", PASSWORD),
        (rb"disk passphrase too\? \(Y/n\): ", "n"),
        (rb"Disk passphrase: ", PASSPHRASE),
        (rb"Disk passphrase again: ", PASSPHRASE),
        (rb"Time zone \[UTC\]: ", "America/Chicago"),
        (rb"Erase /dev/vda and install\? \(y/N\): ", "y"),
    ]
    for prompt, answer in answers:
        serial.expect(re.compile(prompt), 60)
        serial.send(answer + "\n")
    out = serial.expect(re.compile(rb"EXIT=\d+"), timeout)
    return ANSI.sub("", out.decode(errors="replace"))


def install(iso: Path, disk: Path, vars_file: Path, timeout: float, guided_setup: bool = False, offline: bool = False) -> bool:
    disk.unlink(missing_ok=True)
    subprocess.run(["qemu-img", "create", "-q", "-f", "qcow2", str(disk), "24G"], check=True)
    shutil.copy(OVMF_VARS, vars_file)
    CACHE.mkdir(parents=True, exist_ok=True)
    # pacman downloads as the guest's unprivileged alpm user; the 9p share
    # passes host modes through, so the cache must be writable to everyone.
    CACHE.chmod(0o777)
    # Local packages are rebuilt without a version bump; a cached copy with
    # the same name would fail pacman's checksum check.
    for pkg in (ROOT / "build" / "repo").glob("*.pkg.tar.zst"):
        (CACHE / pkg.name).unlink(missing_ok=True)
    cmd = qemu_command(
        vars_file,
        "-cdrom", str(iso), "-boot", "d",
        "-drive", f"file={disk},if=virtio,format=qcow2,discard=unmap",
        "-virtfs", f"local,path={ROOT},mount_tag=src,security_model=none,readonly=on",
        "-virtfs", f"local,path={CACHE},mount_tag=pkgcache,security_model=none",
        network=not offline,
    )
    started = time.monotonic()
    proc, serial, log = start(cmd, VM / "install-serial.log")
    try:
        serial.expect(re.compile(rb"automatic login"), 300)
        serial.claim_prompt(60)
        print(f"install-test: live shell after {time.monotonic() - started:.0f}s")
        opts = "trans=virtio,version=9p2000.L,msize=262144"
        serial.run(
            f"mkdir -p /run/src /run/pkgcache && mount -t 9p -o {opts},ro src /run/src"
            f" && mount -t 9p -o {opts} pkgcache /run/pkgcache && echo MOUNTED"
        )
        # Bounded: with no network device the live medium's startup never
        # settles (its network-online units wait their full timeouts), and
        # the installer does not need it to.
        serial.run("timeout 90 systemctl is-system-running --wait >/dev/null; pacman-key --init >/dev/null 2>&1; true", timeout=180)
        if guided_setup:
            # The image's own subarchy-setup, installer and repository.
            out = guided(serial, timeout)
        else:
            out = serial.run(
                "/run/src/install/subarchy-install --config /run/src/build/vm/install.conf --yes; echo EXIT=$?",
                timeout=timeout,
            )
        ok = "subarchy-install: done" in out and "EXIT=0" in out
        if guided_setup:
            ok = ok and "Installed Subarchy in " in out
        if offline:
            # With no network the installer must say so and still finish from
            # the image's repository (ADR 0049).
            offline_ok = "no mirror reachable" in out
            print(f"install-test: {'ok  ' if offline_ok else 'FAIL'} installer ran from the image's repository with no network")
            ok = ok and offline_ok
        print(f"install-test: installer {'finished' if ok else 'FAILED'} after {time.monotonic() - started:.0f}s")
        if not ok:
            print("\n".join(out.splitlines()[-40:]), file=sys.stderr)
        serial.send("poweroff\n")
        return ok
    except TimeoutError as e:
        proc.kill()
        print(f"install-test: FAIL during install, timed out {e}", file=sys.stderr)
        print(serial.tail(), file=sys.stderr)
        return False
    finally:
        stop(proc, log)


MARKER = "FF00FF"


def lock_crash(serial: Serial, qmp: Path, lock_status: str) -> dict:
    """Kill the lock program while locked and record what the session shows.

    `shown` maps each capture to whether the marker terminal is visible:
    before the lock (it must be), while locked, right after the kill, once
    the replacement runs, and after the unlock (visible again).
    """
    unit = "subcult-lock.service"
    main_pid = f"systemctl --user show -p MainPID --value {unit}"
    shown: dict[str, bool] = {}

    def capture(name: str) -> None:
        png = VM / f"lock-{name}.png"
        screendump(qmp, png)
        shown[name] = has_colour(png, MARKER)

    serial.run(
        f"hyprctl -i 0 dispatch 'hl.dsp.exec_cmd(\"kitty -o background=#{MARKER} -o background_opacity=1\")' >/dev/null;"
        " for i in $(seq 20); do [ $(hyprctl -i 0 clients | grep -c '^Window ') -ge 1 ] && break; sleep 1; done; sleep 2",
        timeout=60)
    capture("before")
    first = serial.run(f"systemctl --user start {unit}; sleep 4; {lock_status}; {main_pid}", timeout=60)
    capture("locked")
    serial.run(f"systemctl --user kill --signal=SIGKILL {unit}")
    capture("killed")
    second = serial.run(
        f"for i in $(seq 20); do p=$({main_pid}); [ \"$p\" != 0 ] && {lock_status} >/dev/null 2>&1 && break; sleep 1; done;"
        f" sleep 3; {lock_status}; {main_pid}; systemctl --user show -p NRestarts --value {unit}", timeout=90)
    capture("replaced")
    end = serial.run(
        f"W=$(ls /run/user/$(id -u) | grep -m1 '^wayland-[0-9]'); WAYLAND_DISPLAY=$W wtype -s 200 -k Return; sleep 2;"
        f" WAYLAND_DISPLAY=$W wtype -s 200 '{PASSWORD}' -k Return; sleep 5; systemctl --user is-active {unit}", timeout=60)
    capture("unlocked")
    serial.run("hyprctl -i 0 dispatch 'hl.dsp.window.close()' >/dev/null; sleep 1")
    return {"first": first, "second": second, "end": end, "shown": shown}


def lock_crash_ok(result: dict) -> bool:
    """A different process holds a secure lock after the kill, the desktop
    showed only before the lock and after the unlock, and the unit ended."""
    try:
        first_status, first_pid = result["first"].strip().splitlines()[-2:]
        second_status, second_pid, restarts = result["second"].strip().splitlines()[-3:]
        first, second = json.loads(first_status), json.loads(second_status)
        restarted = int(restarts) >= 1
    except ValueError:
        return False
    return (
        first.get("locked") is True and first.get("secure") is True
        and second.get("locked") is True and second.get("secure") is True
        and first_pid.isdigit() and second_pid.isdigit() and second_pid not in ("0", first_pid)
        and restarted
        and result["shown"] == {"before": True, "locked": False, "killed": False, "replaced": False, "unlocked": True}
        and result["end"].strip().splitlines()[-1:] == ["inactive"]
    )


def wait_for(serial: Serial, command: str, seconds: int = 60) -> str:
    """Poll a shell condition in the guest for up to `seconds`."""
    return serial.run(
        f"for i in $(seq {seconds}); do {command} && break; sleep 1; done", timeout=seconds + 30
    )


def boot(disk: Path, vars_file: Path) -> bool:
    qmp = socket_path("qmp.sock")
    cmd = qemu_command(
        vars_file, "-drive", f"file={disk},if=virtio,format=qcow2",
        "-qmp", f"unix:{qmp},server=on,wait=off",
    )
    started = time.monotonic()
    proc, serial, log = start(cmd, VM / "boot-serial.log")
    try:
        serial.expect(re.compile(rb"assphrase for"), 180)
        print(f"install-test: LUKS prompt after {time.monotonic() - started:.0f}s")
        time.sleep(2)
        screendump(qmp, VM / "luks.png")  # Plymouth draws the prompt (ADR 0013)
        serial.send(PASSPHRASE + "\n")
        serial.expect(re.compile(rb"login: "), 180)
        print(f"install-test: login prompt after {time.monotonic() - started:.0f}s")
        serial.send(USER + "\n")
        serial.expect(re.compile(rb"Password: "), 30)
        serial.send(PASSWORD + "\n")
        serial.claim_prompt(60)
        sudo = f"echo {PASSWORD} | sudo -S -p ''"
        results = {
            "osr": serial.run("cat /etc/os-release"),
            "kernel": serial.run("uname -r"),
            "root": serial.run("findmnt -no FSTYPE,OPTIONS /"),
            "crypt": serial.run("lsblk -lno TYPE,NAME"),
            "mounts": serial.run("findmnt -lno TARGET,OPTIONS -t btrfs"),
            "zram": serial.run("swapon --show=NAME --noheadings"),
            "snapper": serial.run(f"{sudo} snapper -c root list-configs"),
            "nm": serial.run("systemctl is-enabled NetworkManager"),
            "shell": serial.run("getent passwd " + USER),
            "uki": serial.run(f"{sudo} ls /boot/EFI/Linux"),
            "subvols": serial.run(f"{sudo} btrfs subvolume list /"),
            # System services and hardening (ADR 0013, 0018-0021, 0063).
            "ufw": serial.run(f"{sudo} ufw status verbose"),
            "lsm": serial.run("cat /sys/kernel/security/lsm; echo; cat /sys/module/apparmor/parameters/enabled"),
            "sysctl": serial.run("sysctl -n kernel.kptr_restrict kernel.dmesg_restrict net.ipv4.tcp_syncookies"),
            "dns": serial.run("resolvectl status | grep -i -m1 dnsovertls; resolvectl query archlinux.org", timeout=60),
            "services": serial.run("systemctl is-active avahi-daemon power-profiles-daemon; systemctl is-enabled bluetooth"),
            # Exercise the CLI even without a battery: the auto-profile
            # service otherwise exits before importing its Python bindings.
            "power_cli": serial.run("powerprofilesctl --help >/dev/null; echo POWER_CLI_EXIT=$?"),
            "cmdline": serial.run("cat /proc/cmdline"),
            # GPU modes (ADR 0006): a VM has no hybrid graphics, so the uwsm
            # hook must stay silent and the session start in its default.
            "gpu": serial.run("test -r /usr/share/uwsm/env-hyprland.d/50-subarchy-gpu && echo HOOK;"
                              " subcult-gpu-env | wc -l; subcult gpu mode"),
            # Hardware detection (ADR 0005): the host's CPU, emulated devices.
            "hw": serial.run("pacman -Qq | grep -E '^(linux-firmware.*|intel-ucode|amd-ucode|thermald)$'; subcult hw info"),
            "update_timer": serial.run(
                "systemctl --user list-timers --all --no-legend | grep -c subcult-update-check;"
                " systemctl --user start subcult-update-check.service; cat ~/.local/state/subcult/update-count",
                timeout=120,
            ),
            "power_auto": serial.run("systemctl show -p Result --value subcult-power-auto; journalctl -b -u subcult-power-auto -o cat"),
            "plymouth": serial.run(f"{sudo} journalctl -b -o cat | grep -c 'Show Plymouth Boot Screen'"),
            # The splash theme (ADR 0013): selected, and its files installed.
            "plymouth_theme": serial.run("plymouth-set-default-theme; ls /usr/share/plymouth/themes/subarchy | sort | tr '\\n' ' '; echo"),
            # Channels (ADR 0026): a new install is on stable; edge includes
            # Arch's mirrorlist; back to stable warns about newer packages.
            "channel": serial.run(
                "subcult channel; echo ---; sudo subcult channel set edge; subcult channel; echo ---;"
                " grep -c 'Include = /etc/pacman.d/mirrorlist' /etc/pacman.d/subcult-mirrorlist; echo ---;"
                " sudo subcult channel set stable; echo ---; grep -c archive.archlinux.org /etc/pacman.d/subcult-mirrorlist;"
                " grep -c subcult-mirrorlist /etc/pacman.conf",
                timeout=60,
            ),
            # The repository key is trusted (ADR 0025, subarchy-keyring).
            "keyring": serial.run(f"{sudo} pacman-key --list-keys CCE8B0F3BCDD601D909773E4466AA6E8241453D2 2>&1 | grep -c 'Arch Registry'"),
            # Hardware fixes (ADR 0050): the VM gets the ones every x86 machine
            # gets; their files are in place; the regulatory domain follows the zone.
            "fixes": serial.run("subcult hw fixes; echo ---; cat /etc/modprobe.d/hid_apple.conf; echo ---; grep '^WIRELESS_REGDOM=' /etc/conf.d/wireless-regdom"),
            # The system screens take the user's palette (ADR 0037): SDDM's
            # theme.conf, Limine's colours, a recoloured splash (one initramfs
            # rebuild), Chromium skipped since it is not installed; again: nothing.
            "theme_system": serial.run(
                "mkdir -p ~/.config/subcult/theme && printf '%s' '{\"schema\": 1, \"appearance\": \"dark\", \"colors\": {\"base\": \"#1a1b26\", \"text\": \"#c0caf5\", \"mauve\": \"#bb9af7\", \"surface0\": \"#24283b\"}}' > ~/.config/subcult/theme/palette.json;"
                f" subcult theme apply-system --elevate sudo; {sudo} cp /boot/limine.conf /tmp/limine-after-theme.conf; echo ---;"
                f" subcult theme apply-system --elevate sudo; {sudo} diff -u /tmp/limine-after-theme.conf /boot/limine.conf; echo ---;"
                f" grep -c '^base=#1a1b26' /usr/share/sddm/themes/subarchy/theme.conf; {sudo} grep -c '^interface_branding_colour: bb9af7' /boot/limine.conf;"
                " plymouth-set-default-theme; grep -c 'SetBackgroundTopColor(0.102, 0.106, 0.149)' /usr/share/plymouth/themes/subarchy-user/subarchy-user.script",
                timeout=600,
            ),
            # subcult update: snapshot, pacman -Syu, migrations, report.
            "update": serial.run(
                # Authenticate with this disposable VM's password, then share
                # its sudo timestamp. Never use this password on a real host.
                "sudo -k; sudo -n /usr/bin/subcult-update privileged services >/dev/null 2>&1; echo UNAUTH_STEP_EXIT=$?;"
                " setsid --wait subcult update --yes </dev/null; echo UNAUTH_UPDATE_EXIT=$?;"
                f" {sudo} true && subcult update --yes </dev/null; echo UPDATE_EXIT=$?"
                f" && {sudo} snapper -c root list --columns description",
                timeout=900,
            ),
            # A snapshot must show up as a boot entry (limine-snapper-sync).
            "snapshot": serial.run(
                f"{sudo} rm -f /etc/subarchy-after-snapshot && {sudo} snapper -c root create -d install-test >/dev/null && sleep 5"
                f" && {sudo} limine-snapper-sync >/dev/null 2>&1; {sudo} cat /boot/limine.conf",
                timeout=120,
            ),
            # Marker made after every snapshot: a restore must remove it.
            "marker": serial.run(f"{sudo} touch /etc/subarchy-after-snapshot && echo MARKED"),
            "state": serial.run("systemctl is-system-running --wait", timeout=120),
            "failed": serial.run("systemctl --failed --no-legend --plain | awk '{print $1}'"),
        }
        # The theme probe deliberately writes a different palette. Reset it
        # before the greeter and bar checks assert the shipped colours.
        results["theme_reset"] = serial.run(
            "cp /usr/share/subcult/default/theme/palette.json ~/.config/subcult/theme/palette.json"
            " && subcult theme apply-system --elevate sudo && echo THEME_RESET", timeout=600)
        # Desktop (ADR 0029-0032): the SDDM greeter, then a test-only
        # autologin into the uwsm/Hyprland session.
        results["greeter"] = wait_for(serial, "pgrep -a sddm-greeter", 60)
        time.sleep(3)
        screendump(qmp, VM / "greeter.png")
        results["greeter_colours"] = distinct_colours(VM / "greeter.png")
        results["greeter_palette"] = colours_in(VM / "greeter.png", 800)
        results["sddm_log"] = serial.run("journalctl -b -o cat | grep -i 'qml' | grep -ci 'error\\|is not a type\\|cannot assign\\|Could not load' ; true")
        serial.run(
            f"echo {PASSWORD} | sudo -S -p '' -v && sudo mkdir -p /etc/sddm.conf.d"
            f" && printf '[Autologin]\\nUser={USER}\\nSession=subarchy.desktop\\n'"
            f" | sudo tee /etc/sddm.conf.d/zz-install-test.conf >/dev/null && sudo systemctl restart sddm"
        )
        results["hyprland"] = wait_for(serial, f"pgrep -u {USER} -x Hyprland", 90)
        results["hypr_opts"] = wait_for(
            serial,
            "hyprctl -i 0 getoption general:gaps_out 2>/dev/null | grep -q gap "
            "&& hyprctl -i 0 getoption general:gaps_out && hyprctl -i 0 binds | grep 'description: Terminal'",
            60,
        )
        results["uwsm"] = serial.run("systemctl --user list-units --plain --no-legend 'wayland-wm@*'")
        # The desktop shell (shell and look design, Task 16).
        results["shell_active"] = wait_for(
            serial, "systemctl --user is-active subcult-shell.service | grep -qx active && echo ACTIVE", 90)
        time.sleep(8)
        # The serial login has no WAYLAND_DISPLAY; the shell runs on the session's.
        shell_ipc = "quickshell ipc --any-display -p /usr/share/subcult/shell call subcult.shell status"
        results["shell_status"] = serial.run(shell_ipc)
        results["shell_errors"] = serial.run(
            "journalctl --user -b -u subcult-shell.service --no-pager"
            " | grep -vE 'Failed to (connect|create) pipewire context|MESA|ZINK'"
            " | grep -E 'ERROR|TypeError|ReferenceError|is not a type|Cannot assign' | head -5")
        results["layers"] = serial.run("hyprctl -i 0 layers | grep -c 'namespace: subcult-bar'")
        # Exercise the generated commands twice from each state. Merely
        # accepting dispatch is insufficient: an unknown Lua field toggles.
        dpms_probe = r"""
import json, os, pathlib, shlex, subprocess, time
config = pathlib.Path('/run/user', str(os.getuid()), 'subcult/hypridle.conf').read_text()
assert 'inhibit_sleep = 3' in config, config
commands = dict(line.strip().split(' = ', 1) for line in config.splitlines()
                if ' = ' in line and 'dpms(' in line)
on = shlex.split(commands['after_sleep_cmd'])
off = shlex.split(commands['on-timeout'])
for command in (on, off):
    command[1:1] = ['-i', '0']
try:
    for expected, command in ((True, on), (False, off), (True, on)):
        for _ in range(2):
            subprocess.run(command, check=True, capture_output=True)
            time.sleep(0.3)
            monitors = json.loads(subprocess.check_output(['hyprctl', '-i', '0', '-j', 'monitors']))
            assert monitors and all(m['dpmsStatus'] == expected for m in monitors), monitors
    print('DPMS_IDEMPOTENT')
finally:
    subprocess.run(on, check=True, capture_output=True)
"""
        results["idle_service"] = serial.run(
            "systemctl --user is-active subcult-idle.service; grep -c 'timeout = 420' /run/user/$(id -u)/subcult/hypridle.conf; "
            + "python3 -c " + shlex.quote(dpms_probe), timeout=60)
        # The lock (ADR 0036): its own unit locks the session; the shell dying
        # leaves it locked; the password typed into it unlocks and the
        # program exits; the shell comes back on its own.
        lock_status = "quickshell ipc --any-display -p /usr/share/subcult/lock call subcult.lock status"
        results["lock"] = serial.run(
            f"systemctl --user start subcult-lock.service; sleep 4; {lock_status}; echo ---;"
            f" systemctl --user kill --signal=SIGKILL subcult-shell.service; sleep 4; {lock_status}; echo ---;"
            f" W=$(ls /run/user/$(id -u) | grep -m1 '^wayland-[0-9]'); WAYLAND_DISPLAY=$W wtype -s 200 -k Return; sleep 2; {lock_status}; echo ---;"
            f" WAYLAND_DISPLAY=$W wtype -s 200 '{PASSWORD}' -k Return; sleep 5;"
            " systemctl --user is-active subcult-lock.service; systemctl --user is-active subcult-shell.service",
            timeout=120)
        results["fonts"] = serial.run(
            "for r in monospace sans-serif serif; do fc-match -f '%{family[0]}\\n' $r; done")
        results["gtk"] = serial.run(
            "gsettings get org.gnome.desktop.interface icon-theme; gsettings get org.gnome.desktop.interface cursor-theme")
        results["discord"] = serial.run(
            "test -f /usr/share/applications/discord.desktop"
            " && test -f /usr/share/chromium/extensions/cbghhgpcnddeihccjmnadmkaejncjndb.json && echo WEBAPP_OK")

        # Pult applied the default theme for the new user (ADR 0037).
        results["pult"] = serial.run("pult doctor 2>&1; echo PULT_RC=$?", timeout=60)
        # Its Subarchy targets (issue #76): the shell and lock palette and the
        # Hyprland colour file are Pult's own files from the install on.
        results["pult_targets"] = serial.run(
            "pult list | grep -c '^subarchy-.*owned'; head -1 ~/.config/subcult/theme/hyprland.lua")

        # Neovim's first launch needs no network (ADR 0045): run it in a
        # network namespace as the user, with the config from /etc/skel.
        results["nvim"] = serial.run(
            f"{sudo} unshare -n runuser -u $(id -un) -- nvim --headless '+lua print(require(\"lazy\").stats().count)'"
            " '+lua print(\"SCHEME=\" .. tostring(vim.g.colors_name) .. \" LAYER=\" .. tostring(vim.g.subarchy_layer))' +qa 2>&1; echo NVIM_RC=$?", timeout=120)
        results["cursor"] = serial.run("ls /usr/share/icons/subcult-cursor/cursors/left_ptr /usr/share/icons/subcult-cursor/hyprcursors/default.hlc")
        # The bar and the idle sample come first, before any window is open.
        screendump(qmp, VM / "bar.png")
        results["bar_colours"] = colours_in(VM / "bar.png", 26)
        # Idle cost over a quiet minute: voluntary context switches of the
        # shell's main thread (budgeted) and of all its threads (reported).
        pid = serial.run("pgrep -u $(id -u) -f 'quickshell -n -p /usr/share/subcult/shell' | head -1").strip()
        main = "awk '/^voluntary_ctxt_switches/ {print $2}' /proc/%s/status" % pid
        threads = ("for t in /proc/%s/task/*; do echo \"${t##*/}"
                   " $(awk '/^voluntary_ctxt_switches/ {print $2}' $t/status 2>/dev/null)\"; done" % pid)

        def idle_minute():
            if not pid.isdigit():
                return None
            before, before_all = serial.run(main).strip(), serial.run(threads)
            time.sleep(60)
            after, after_all = serial.run(main).strip(), serial.run(threads)
            total = thread_wakeups(before_all, after_all)
            if not (before.isdigit() and after.isdigit()) or total is None:
                return None
            return int(after) - int(before), total
        results["idle"], results["idle_all"] = quietest_minute(idle_minute)
        # Idle resident memory of the whole session (every process of the
        # user: compositor, shell, portals, agents) in KiB, taken after the
        # quiet minute, and the installed package count (ADR 0054 budgets).
        mem = serial.run("ps -u $(id -u) -o rss= | awk '{s += $1} END {print s + 0}'").strip()
        results["mem"] = int(mem) if mem.isdigit() else -1
        pkgs = serial.run("pacman -Qq | wc -l").strip()
        results["packages"] = int(pkgs) if pkgs.isdigit() else -1
        # A catalog theme recolours the bar through Pult alone (issue #76);
        # the default profile then puts Subarchy's own colours back.
        results["pult_theme"] = serial.run("pult apply -yes dracula >/dev/null 2>&1; echo PULT_APPLY=$?", timeout=120)
        time.sleep(3)
        screendump(qmp, VM / "bar-dracula.png")
        results["dracula_colours"] = colours_in(VM / "bar-dracula.png", 26)
        results["pult_restore"] = serial.run(
            "pult apply -yes -profile /usr/share/subcult/default/theme/subarchy.toml >/dev/null 2>&1; echo PULT_RESTORE=$?;"
            " grep -ci '\"base\": \"#100b19\"' ~/.config/subcult/theme/palette.json", timeout=120)
        # The shell's Hyprland dispatches on a Lua config: the workspace click
        # expression (as shell/Commons/HyprDispatch.js writes it).
        results["dispatch"] = serial.run(
            "hyprctl -i 0 dispatch 'hl.dsp.focus({ workspace = \"3\" })' >/dev/null; sleep 1;"
            " hyprctl -i 0 activeworkspace -j | grep -o '\"id\": [0-9]*' | head -1;"
            " hyprctl -i 0 dispatch 'hl.dsp.focus({ workspace = \"1\" })' >/dev/null; sleep 1")
        # Alt-Tab between two terminals. First through the global shortcuts
        # real keys take, next then commit at once as a quick tap sends them:
        # from the second (focused) terminal it must land on exactly the first
        # (the session may hold other windows) and leave no switcher open.
        # Then over IPC, back from the first to the second. Both are closed
        # afterwards.
        glob = "hyprctl -i 0 dispatch 'hl.dsp.global(\"subcult:altswitch-%s\")' >/dev/null"
        alt = "quickshell ipc --any-display -p /usr/share/subcult/shell call subcult.altswitch"
        active = "hyprctl -i 0 activewindow | head -1"
        results["altswitch"] = serial.run(
            "hyprctl -i 0 dispatch 'hl.dsp.exec_cmd(\"kitty\")' >/dev/null;"
            " for i in $(seq 20); do [ $(hyprctl -i 0 clients | grep -c '^Window ') -ge 1 ] && break; sleep 1; done;"
            f" sleep 1; w1=$({active});"
            " hyprctl -i 0 dispatch 'hl.dsp.exec_cmd(\"kitty\")' >/dev/null;"
            " for i in $(seq 20); do [ $(hyprctl -i 0 clients | grep -c '^Window ') -ge 2 ] && break; sleep 1; done;"
            f" sleep 1; w2=$({active}); n=$(hyprctl -i 0 clients | grep -c '^Window ');"
            f" {glob % 'next'}; {glob % 'commit'}; sleep 1; g=$({active});"
            " o=$(hyprctl -i 0 layers | grep -c 'namespace: subcult-altswitch');"
            f" {alt} next; sleep 0.5; {alt} commit; sleep 1; v=$({active});"
            " echo \"N=$n\"; echo \"W1=$w1\"; echo \"W2=$w2\"; echo \"G=$g\"; echo \"O=$o\"; echo \"V=$v\";"
            " if [ \"$n\" -ge 2 ] && [ -n \"$w1\" ] && [ \"$w1\" != \"$w2\" ]; then"
            "   [ \"$g\" = \"$w1\" ] && [ \"$o\" = 0 ] && echo SWITCHED_GLOBAL;"
            "   [ \"$v\" = \"$w2\" ] && echo SWITCHED_IPC;"
            " fi;"
            " for i in 1 2; do hyprctl -i 0 dispatch 'hl.dsp.window.close()' >/dev/null; sleep 1; done", timeout=180)
        # On battery: UPower replaced by python-dbusmock's template with
        # OnBattery set, then the shell restarted (it reads UPower at start;
        # a live hand-over between UPower owners is not tested). Then the real
        # UPower again: the restarted shell must be back on AC.
        results["battery"] = serial.run(
            f"{sudo} pacman -S --noconfirm --needed python-dbusmock >/dev/null 2>&1"
            f" && {sudo} systemctl stop upower.service"
            f" && ({sudo} python3 -m dbusmock --system --template upower -p '{{\"OnBattery\": true}}'"
            " >/tmp/upower-mock.log 2>&1 &) && sleep 3"
            " && busctl get-property org.freedesktop.UPower /org/freedesktop/UPower org.freedesktop.UPower OnBattery"
            " && systemctl --user restart subcult-shell.service && sleep 8"
            f" && {shell_ipc}", timeout=300)
        # A battery lock must use still art even when motion is forced on.
        results["lock_battery"] = serial.run(
            "mkdir -p ~/.config/subcult; echo '{\"mode\":\"on\"}' >~/.config/subcult/motion.json;"
            f" systemctl --user start subcult-lock.service; sleep 4; {lock_status};"
            f" W=$(ls /run/user/$(id -u) | grep -m1 '^wayland-[0-9]'); WAYLAND_DISPLAY=$W wtype -s 200 '{PASSWORD}' -k Return; sleep 3;"
            " echo '{\"mode\":\"auto\"}' >~/.config/subcult/motion.json", timeout=60)
        # Keep-awake: a logind idle inhibitor that a shell restart keeps.
        shell_call = "quickshell ipc --any-display -p /usr/share/subcult/shell call subcult.shell"
        inhibited = "systemd-inhibit --list --no-legend 2>/dev/null | grep -c SUBCULT"
        results["keep_awake"] = serial.run(
            f"{shell_call} keepAwake true; sleep 1; {inhibited};"
            f" systemctl --user restart subcult-shell.service; sleep 8; {inhibited};"
            f" {shell_call} keepAwake false; sleep 1; {inhibited}", timeout=120)
        results["ac_again"] = serial.run(
            f"{sudo} pkill -f '[d]busmock --system --template upower'; {sudo} systemctl start upower.service"
            f" && sleep 2 && systemctl --user restart subcult-shell.service && sleep 8 && {shell_ipc}")
        time.sleep(3)
        screendump(qmp, VM / "session.png")
        results["session_colours"] = distinct_colours(VM / "session.png")
        # The lock program dying (ADR 0070), apart from the shell dying
        # earlier: the unit starts a replacement, which takes over the lock
        # the compositor kept, and the password still unlocks. A terminal in
        # a colour nothing else draws stands for the desktop: it must not
        # show in any capture between the lock and the unlock. Last, because
        # a refused replacement leaves the session locked for good.
        results["lock_crash"] = lock_crash(serial, qmp, lock_status)
        serial.run(f"{sudo} rm -f /etc/sddm.conf.d/zz-install-test.conf")
        serial.send(f"{sudo} poweroff\n")
    except TimeoutError as e:
        proc.kill()
        print(f"install-test: FAIL during boot, timed out {e}", file=sys.stderr)
        print(serial.tail(), file=sys.stderr)
        return False
    finally:
        stop(proc, log)

    r = results
    state = r["state"].strip().splitlines()[-1] if r["state"].strip() else ""
    checks = {
        "os-release ID=subarchy": "ID=subarchy" in r["osr"],
        "kernel is linux-zen": "zen" in r["kernel"],
        "root is btrfs subvolume @": r["root"].startswith("btrfs") and "subvol=/@" in r["root"],
        "root is on LUKS (crypt)": any(line.startswith("crypt") for line in r["crypt"].splitlines()),
        "@home, @log, @pkg mounted": all(f"subvol=/{sv}" in r["mounts"] for sv in ("@home", "@log", "@pkg")),
        "zstd compression": "compress=zstd:3" in r["mounts"],
        "zram swap": "zram" in r["zram"],
        "snapper root config": "root" in r["snapper"],
        "NetworkManager enabled": r["nm"].strip().endswith("enabled"),
        "login shell is zsh": r["shell"].strip().endswith("/usr/bin/zsh"),
        "both UKIs present": "subarchy_linux-zen.efi" in r["uki"] and "subarchy_linux-lts.efi" in r["uki"],
        "snapshot boot entry": "rootflags=subvol=/@/.snapshots/" in r["snapshot"],
        "no self-referencing EFI entry": "/EFI/BOOT/BOOTX64.EFI" not in r["snapshot"],
        "subcult update authenticates before privileged work": "UNAUTH_STEP_EXIT=1" in r["update"]
        and "UNAUTH_UPDATE_EXIT=1" in r["update"],
        "subcult update reuses authorized sudo": "\nUPDATE_EXIT=0" in r["update"] and "eboot needed" in r["update"],
        "hardware fixes applied (hid_apple fnmode, regulatory domain US)": "hid-apple-fkeys" in r["fixes"]
        and "options hid_apple fnmode=2" in r["fixes"] and 'WIRELESS_REGDOM="US"' in r["fixes"],
        "new install on the stable channel, switches to edge and back": channel_ok(r["channel"]),
        "repository key trusted (subarchy-keyring)": r["keyring"].strip().splitlines()[-1:] == ["1"],
        "daily update check timer and count": r["update_timer"].splitlines()[0:1] == ["1"]
        and r["update_timer"].strip().splitlines()[-1].isdigit(),
        "power profile service (no battery: unchanged)": r["power_auto"].splitlines()[0:1] == ["success"]
        and "no system battery" in r["power_auto"],
        "powerprofilesctl Python bindings available without a battery": "POWER_CLI_EXIT=0" in r["power_cli"],
        "update took a snapshot": "subcult update" in r["update"].split("UPDATE_EXIT")[-1],
        "marker created after the snapshots": "MARKED" in r["marker"],
        "@factory snapshot": any(line.endswith(" path @factory") for line in r["subvols"].splitlines()),
        "system running or degraded": state in ("running", "degraded"),
        "hardware packages: microcode for the guest's CPU, no firmware in a VM": hw_ok(r["hw"]),
        "GPU hook installed, silent without hybrid graphics": r["gpu"].split()[:2] == ["HOOK", "0"]
        and "chosen:  intel" in r["gpu"],
        "ufw active, incoming denied": "Status: active" in r["ufw"] and "deny (incoming)" in r["ufw"],
        "AppArmor enabled": "apparmor" in r["lsm"] and r["lsm"].strip().endswith("Y"),
        "sysctl hardening": r["sysctl"].split() == ["2", "1", "1"],
        "DNS over TLS resolves": "+DNSOverTLS" in r["dns"] and "archlinux.org:" in r["dns"],
        "avahi, power-profiles, bluetooth": r["services"].split() == ["active", "active", "enabled"],
        # Graphical splash is not checked: with console=ttyS0 (needed to
        # drive the test) Plymouth falls back to its text mode.
        "Plymouth runs and takes the LUKS prompt": "splash" in r["cmdline"]
        and r["plymouth"].strip().isdigit() and int(r["plymouth"].strip()) > 0,
        "SDDM greeter running": "sddm-greeter" in r["greeter"],
        "greeter drew something": r["greeter_colours"] > 1,
        "greeter shows the theme (ink background, no QML errors)": "100B19" in r["greeter_palette"]
        and r["sddm_log"].strip().splitlines()[-1:] == ["0"],
        "default palette restored after the system-theme probe": "THEME_RESET" in r["theme_reset"],
        "theme apply-system recolours SDDM, Limine and the splash, rebuilding the initramfs once": theme_system_ok(r["theme_system"]),
        "Plymouth theme selected with its images": "subarchy" in r["plymouth_theme"].split()
        and all(f in r["plymouth_theme"] for f in ("logo.png", "subarchy.script", "entry.png", "progress-bar.png")),
        "idle service runs generated config and DPMS on/off are idempotent":
            r["idle_service"].strip().splitlines()[0:2] == ["active", "1"] and "DPMS_IDEMPOTENT" in r["idle_service"],
        "lock locks, survives the shell dying, unlocks with the password": lock_ok(r["lock"]),
        "lock comes back after its process is killed, keeps the desktop hidden, then unlocks": lock_crash_ok(r["lock_crash"]),
        "Hyprland session started": r["hyprland"].strip() != "",
        "session runs under uwsm": "wayland-wm@" in r["uwsm"],
        "Subarchy Hyprland defaults loaded (flat look)": "gap data: 0 0 0 0" in r["hypr_opts"]
        and "description: Terminal" in r["hypr_opts"],
        "session drew something": r["session_colours"] > 1,
        "shell service active": "ACTIVE" in r["shell_active"],
        "shell log has no QML errors": r["shell_errors"].strip() == "",
        "one bar layer per monitor": r["layers"].strip() == "1",
        "full bar with widgets": '"subcult.clock"' in r["shell_status"] and '"subcult.menu"' in r["shell_status"],
        "bar colours (base, line, text)": {"100B19", "1F1830", "F0ECE4"} <= r["bar_colours"],
        "font roles": r["fonts"].split("\n")[:3] == ["JetBrainsMono Nerd Font", "JetBrainsMono Nerd Font Propo", "Libertinus Mono"],
        "GTK icons and cursor": "'Papirus-Dark'" in r["gtk"] and "'subcult-cursor'" in r["gtk"],
        "cursor theme installed": "No such file" not in r["cursor"] and "left_ptr" in r["cursor"],
        "Neovim starts offline with its plugins": "NVIM_RC=0" in r["nvim"] and "Failed" not in r["nvim"],
        "Neovim has the Subarchy layer and the subcult scheme": "LAYER=subarchy-nvim" in r["nvim"] and "SCHEME=subcult" in r["nvim"],
        "Discord web app and Vencord Web installed": "WEBAPP_OK" in r["discord"],

        "pult doctor passes with subcult-minimal applied": "PULT_RC=0" in r["pult"] and "subcult-minimal" in r["pult"],
        "pult owns the shell palette and the Hyprland colours": r["pult_targets"].split()[:1] == ["2"] and "Generated by Pult" in r["pult_targets"],
        "a catalog theme recolours the bar through pult, and the profile restores it": "PULT_APPLY=0" in r["pult_theme"]
            and "282A36" in r["dracula_colours"] and r["pult_restore"].split() == ["PULT_RESTORE=0", "1"],
        "lock uses still art on battery even with motion on": '\"playing\":0' in r["lock_battery"] and '\"motion\":false' in r["lock_battery"] and '\"screensaver\":true' in r["lock_battery"],
        "shell sees battery power": '"onBattery":true' in r["battery"],
        "shell back on AC with the real UPower": '"onBattery":false' in r["ac_again"],
        "keep-awake inhibits idle, survives a shell restart, releases": r["keep_awake"].split() == ["1", "1", "0"],
        "workspace dispatch (Lua expression)": '"id": 3' in r["dispatch"],
        "Alt-Tab switches to the previous window (global shortcuts)": "SWITCHED_GLOBAL" in r["altswitch"].splitlines(),
        "Alt-Tab switches back (IPC)": "SWITCHED_IPC" in r["altswitch"].splitlines(),
        "shell idle within budget": idle_ok(r["idle"]),
        "session idle memory within budget": budget_ok("session_rss_kb", r["mem"], 20480),
        "package count within budget": budget_ok("packages", r["packages"], 5),
    }
    for name, ok in checks.items():
        print(f"install-test: {'ok  ' if ok else 'FAIL'} {name}")
    if not {"SWITCHED_GLOBAL", "SWITCHED_IPC"} <= set(r["altswitch"].splitlines()):
        print("install-test: Alt-Tab:\n" + r["altswitch"].strip())
    if r["shell_errors"].strip():
        print("install-test: shell errors:\n" + r["shell_errors"].strip())
    print(f"install-test: shell idle: {r['idle']} main-thread wake-ups in the quietest 60 s sampled, {r['idle_all']} over all threads (budget file {IDLE_BUDGET})")
    print(f"install-test: session idle memory: {r['mem']} KiB resident; packages installed: {r['packages']}")
    print(f"install-test: screenshots {VM / 'greeter.png'}, {VM / 'session.png'}, {VM / 'bar.png'}"
          f" ({r['greeter_colours']} and {r['session_colours']} colours)")
    if r["failed"].strip():
        print("install-test: failed units: " + ", ".join(r["failed"].split()))
    print(f"install-test: kernel {r['kernel'].strip()}, state {state}")
    return all(checks.values())


DOWN, ENTER = "\x1b[B", "\r"


def boot_snapshot(disk: Path, vars_file: Path) -> bool:
    """Boot the newest snapshot's linux-zen entry from the Limine menu.

    Menu with the Subarchy directory open: 1 Subarchy, 2 linux-zen (default),
    3 linux-lts, 4 Snapshots (closed). The keys open Snapshots, then the
    first snapshot, and boot its first kernel.
    """
    cmd = qemu_command(vars_file, "-drive", f"file={disk},if=virtio,format=qcow2")
    proc, serial, log = start(cmd, VM / "snapshot-serial.log")
    try:
        serial.expect(re.compile(rb"starting Boot.*Limine"), 60)
        time.sleep(1.5)  # let Limine draw its menu
        for key in (DOWN, DOWN, ENTER, DOWN, ENTER, DOWN, ENTER):
            serial.send(key)
            time.sleep(0.3)
        serial.expect(re.compile(rb"assphrase for"), 180)
        serial.send(PASSPHRASE + "\n")
        serial.expect(re.compile(rb"login: "), 180)
        serial.send(USER + "\n")
        serial.expect(re.compile(rb"Password: "), 30)
        serial.send(PASSWORD + "\n")
        serial.claim_prompt(60)
        cmdline = serial.run("cat /proc/cmdline")
        root = serial.run("findmnt -no FSTYPE /")
        state = serial.run("systemctl is-system-running --wait", timeout=120).strip()
        # Restore the booted snapshot over @, then boot the default entry
        # (ADR 0011): the marker made after the snapshot must be gone.
        # The tool reads each answer with a fresh buffered reader, so the
        # answers (restore, default backup description) arrive one at a
        # time. It ends with "Reboot now? [Y/n]", and the closed input
        # takes the default: the VM reboots into the default entry.
        serial.buf = b""
        serial.send(
            f"echo {PASSWORD} | sudo -S -p '' -v && (echo r; sleep 5; echo; sleep 5)"
            " | sudo limine-snapper-sync --restore\n"
        )
        restore = ANSI.sub("", serial.expect(re.compile(rb"Restore complete"), 600).decode(errors="replace"))
        serial.expect(re.compile(rb"assphrase for"), 240)
        serial.send(PASSPHRASE + "\n")
        serial.expect(re.compile(rb"login: "), 180)
        serial.send(USER + "\n")
        serial.expect(re.compile(rb"Password: "), 30)
        serial.send(PASSWORD + "\n")
        serial.claim_prompt(60)
        restored = serial.run(
            "test -e /etc/subarchy-after-snapshot && echo MARKER_PRESENT || echo MARKER_GONE;"
            " findmnt -no OPTIONS / | tr , '\\n' | grep subvol=; systemctl is-system-running --wait",
            timeout=120,
        )
        serial.send(f"echo {PASSWORD} | sudo -S -p '' poweroff\n")
    except TimeoutError as e:
        proc.kill()
        print(f"install-test: FAIL booting the snapshot, timed out {e}", file=sys.stderr)
        print(serial.tail(), file=sys.stderr)
        return False
    finally:
        stop(proc, log)
    state = state.splitlines()[-1] if state else ""
    checks = {
        "snapshot booted": "subvol=/@/.snapshots/" in cmdline,
        "snapshot root is a writable overlay": root.strip() == "overlay",
        "snapshot system running or degraded": state in ("running", "degraded"),
        "restore from the snapshot succeeded": "Success: mv" in restore and "Restore complete" in restore,
        "after restore: change since snapshot gone": "MARKER_GONE" in restored,
        "after restore: boots @ and runs": "subvol=/@\n" in restored + "\n"
        and restored.strip().splitlines()[-1] in ("running", "degraded"),
    }
    for name, ok in checks.items():
        print(f"install-test: {'ok  ' if ok else 'FAIL'} {name}")
    return all(checks.values())


SB_VAR = "/sys/firmware/efi/efivars/SecureBoot-8be4df61-93ca-11d2-aa0d-00e098032b8c"


def unlock_and_login(serial: Serial) -> None:
    serial.expect(re.compile(rb"assphrase for"), 240)
    serial.send(PASSPHRASE + "\n")
    serial.expect(re.compile(rb"login: "), 180)
    serial.send(USER + "\n")
    serial.expect(re.compile(rb"Password: "), 30)
    serial.send(PASSWORD + "\n")
    serial.claim_prompt(60)


def boot_secureboot(disk: Path, vars_file: Path) -> bool:
    """Enroll keys with `subcult secureboot setup`, then boot with Secure
    Boot enforced, take a snapshot (rewrites limine.conf, so the enrolled
    config hash must follow) and boot once more (ADR 0012)."""
    # A software TPM for this phase (ADR 0010 TPM unlock); fresh each run.
    tpm_dir = VM / "tpm"
    shutil.rmtree(tpm_dir, ignore_errors=True)
    tpm_dir.mkdir(parents=True)
    tpm_sock = socket_path("swtpm.sock")
    swtpm = subprocess.Popen(
        ["swtpm", "socket", "--tpm2", "--tpmstate", f"dir={tpm_dir}", "--ctrl", f"type=unixio,path={tpm_sock}"],
        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
    )
    for _ in range(50):
        if tpm_sock.exists():
            break
        time.sleep(0.1)
    cmd = qemu_command(
        vars_file, "-drive", f"file={disk},if=virtio,format=qcow2",
        "-chardev", f"socket,id=chrtpm,path={tpm_sock}", "-tpmdev", "emulator,id=tpm0,chardev=chrtpm",
        "-device", "tpm-tis,tpmdev=tpm0",
    )
    proc, serial, log = start(cmd, VM / "secureboot-serial.log")
    sb_state = f"od -An -t u1 -j4 -N1 {SB_VAR}"
    tpm_boot = b""
    try:
        unlock_and_login(serial)
        before = serial.run(sb_state)
        setup = serial.run(f"echo {PASSWORD} | sudo -S -p '' -v && sudo subcult secureboot setup; echo SETUP_EXIT=$?", timeout=600)
        serial.send("sudo reboot\n")
        unlock_and_login(serial)
        after = serial.run(f"{sb_state}; systemctl is-system-running --wait", timeout=120)
        serial.run(
            f"echo {PASSWORD} | sudo -S -p '' -v && sudo snapper -c root create -d secureboot-test"
            " && sleep 5 && sudo limine-snapper-sync >/dev/null 2>&1; echo SNAP_DONE",
            timeout=180,
        )
        serial.send("sudo reboot\n")
        unlock_and_login(serial)
        again = serial.run(f"{sb_state}; systemctl is-system-running --wait", timeout=120)
        # A theme change rewrites the colour lines of limine.conf. With the
        # config's hash enrolled in the boot loader, the hash must follow,
        # or the next boot stops at Limine. Only the accent changes here,
        # so the splash and the initramfs stay as they are.
        themed = serial.run(
            "mkdir -p ~/.config/subcult/theme && printf '%s' '{\"schema\": 1, \"appearance\": \"dark\", \"colors\":"
            " {\"base\": \"#100B19\", \"text\": \"#F0ECE4\", \"mauve\": \"#33aa77\"}}' > ~/.config/subcult/theme/palette.json;"
            f" echo {PASSWORD} | sudo -S -p '' -v && subcult theme apply-system --elevate sudo; echo THEME_EXIT=$?",
            timeout=600,
        )
        serial.send("sudo reboot\n")
        unlock_and_login(serial)
        themed_boot = serial.run(f"{sb_state}; systemctl is-system-running --wait", timeout=120)
        # TPM unlock (ADR 0010): bind the disk to PCR 7, then boot without
        # typing the passphrase.
        tpm = serial.run(
            f"echo {PASSWORD} | sudo -S -p '' -v && sudo env PASSWORD={PASSPHRASE} subcult disk tpm enable;"
            " echo TPM_EXIT=$?; subcult disk tpm status 2>&1 || sudo subcult disk tpm status",
            timeout=300,
        )
        serial.send("sudo reboot\n")
        tpm_boot = serial.expect(re.compile(rb"assphrase for|login: "), 240)
        if b"login: " in tpm_boot:
            serial.send(USER + "\n")
            serial.expect(re.compile(rb"Password: "), 30)
            serial.send(PASSWORD + "\n")
            serial.claim_prompt(60)
            tpm_state = serial.run("systemctl is-system-running --wait", timeout=120)
            serial.send(f"echo {PASSWORD} | sudo -S -p '' poweroff\n")
        else:
            tpm_state = ""
            proc.kill()
    except TimeoutError as e:
        proc.kill()
        print(f"install-test: FAIL in the Secure Boot phase, timed out {e}", file=sys.stderr)
        print(serial.tail(), file=sys.stderr)
        return False
    finally:
        stop(proc, log)
        swtpm.terminate()
        swtpm.wait(timeout=10)
    checks = {
        "Secure Boot off before setup": before.split()[:1] == ["0"],
        "subcult secureboot setup succeeded": "SETUP_EXIT=0" in setup,
        "boots with Secure Boot on": after.split()[:1] == ["1"] and after.split()[-1] in ("running", "degraded"),
        "still boots after limine.conf changed": again.split()[:1] == ["1"] and again.split()[-1] in ("running", "degraded"),
        "still boots after the theme recoloured the boot menu": "THEME_EXIT=0" in themed and "wrote /boot/limine.conf" in themed
        and themed_boot.split()[:1] == ["1"] and themed_boot.split()[-1] in ("running", "degraded"),
        "TPM unlock enabled": "TPM_EXIT=0" in tpm and "TPM unlock: on" in tpm,
        "boots without the passphrase (TPM)": b"assphrase for" not in tpm_boot
        and tpm_state.strip().splitlines()[-1:] in (["running"], ["degraded"]),
    }
    for name, ok in checks.items():
        print(f"install-test: {'ok  ' if ok else 'FAIL'} {name}")
    return all(checks.values())


def lock_ok(out: str) -> bool:
    """Playback, shell-crash survival, prompt without playback, then unlock."""
    parts = [p.strip() for p in out.split("---")]
    if len(parts) < 4:
        return False
    try:
        first = json.loads(parts[0].splitlines()[-1])
        second = json.loads(parts[1].splitlines()[-1])
        prompt = json.loads(parts[2].splitlines()[-1])
    except (ValueError, IndexError):
        return False
    tail = parts[3].splitlines()
    return (first.get("locked") is True and first.get("playing", 0) > 0
            and first.get("screensaver") is True and second.get("locked") is True
            and prompt.get("locked") is True and prompt.get("prompt") is True
            and prompt.get("playing") == 0 and tail[-2:] == ["inactive", "active"])


def hw_ok(out: str) -> bool:
    """The installed hardware packages, then `subcult hw info`.

    With KVM the guest has the host's CPU, so the microcode follows the
    machine the test runs on: Intel also gets thermald (ADR 0021), AMD does
    not. A VM has no radios or audio DSP, so no firmware package.
    """
    vendor = re.search(r"(?m)^CPU:\s+(\S+)", out)
    wanted = {"GenuineIntel": {"intel-ucode", "thermald"}, "AuthenticAMD": {"amd-ucode"}}.get(vendor.group(1) if vendor else "")
    installed = {w for w in out.split() if w in ("intel-ucode", "amd-ucode", "thermald")}
    return wanted is not None and installed == wanted and "linux-firmware" not in out and "VM:        QEMU" in out


def theme_system_ok(out: str) -> bool:
    """Two apply-system runs (the first rebuilds the initramfs, the second changes nothing), then the files."""
    parts = [p.strip() for p in re.split(r"(?m)^---$", out)]
    if len(parts) != 3:
        return False
    first, second, files = parts
    return (
        "rebuilding the initramfs" in first and "wrote /usr/share/sddm/themes/subarchy/theme.conf" in first
        and "skipped: Chromium" in first
        and "no initramfs rebuild" in second and "wrote" not in second
        and files.splitlines()[-4:-1] == ["1", "1", "subarchy-user"] and files.splitlines()[-1] == "1"
    )


def channel_ok(out: str) -> bool:
    """`subcult channel` output: stable first, edge with Arch's mirrorlist, back with the warning."""
    parts = [p.strip() for p in out.split("---")]
    if len(parts) < 5:
        return False
    first, edge, include, back, stable = parts[0], parts[1], parts[2], parts[3], parts[4]
    return (
        first.startswith("stable (snapshot ")
        and edge.splitlines()[-1].startswith("edge")
        and include.splitlines()[-1] == "1"
        and "newer than the snapshot" in back
        and stable.splitlines()[0] == "1" and stable.splitlines()[-1] == "2"
    )


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("iso", type=Path)
    ap.add_argument("--skip-install", action="store_true", help="boot the existing build/vm disk only")
    ap.add_argument("--guided", action="store_true", help="install by answering subarchy-setup from the image")
    ap.add_argument("--timeout-install", type=float, default=2400)
    ap.add_argument("--offline", action="store_true", help="install with the guest's network off (needs --guided)")
    args = ap.parse_args()
    if args.offline and not args.guided:
        ap.error("--offline needs --guided: the image's own setup and repository")
    for f in (args.iso, OVMF_CODE, OVMF_VARS, ROOT / "build" / "repo" / "subarchy.db"):
        if not f.exists():
            print(f"install-test: missing {f} (run make iso first)", file=sys.stderr)
            return 2
    disk, vars_file = VM / "disk.qcow2", VM / "OVMF_VARS.fd"
    write_config()
    if not args.skip_install and not install(args.iso, disk, vars_file, args.timeout_install, args.guided, args.offline):
        return 1
    # A failed check in one stage does not skip the others.
    ok = boot(disk, vars_file)
    ok = boot_snapshot(disk, vars_file) and ok
    ok = boot_secureboot(disk, vars_file) and ok
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
