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
import re
import shutil
import subprocess
import sys
import time
from pathlib import Path

from vmlib import ANSI, OVMF_CODE, OVMF_VARS, Serial, colours_in, distinct_colours, qemu_command, screendump

ROOT = Path(__file__).resolve().parents[2]
VM = ROOT / "build" / "vm"
CACHE = ROOT / "build" / "pkgcache"
IDLE_BUDGET = ROOT / "tools" / "iso" / "idle-budget.json"


def idle_ok(switches: int) -> bool:
    """The shell's idle wake-ups against tools/iso/idle-budget.json (ADR 0054).

    The first run records its measurement as the budget (null in the file);
    later runs fail above the larger of budget × 1.2 and budget + 3.
    """
    import json
    if switches < 0:
        return False
    data = json.loads(IDLE_BUDGET.read_text())
    budget = data.get("shell_voluntary_ctxt_switches_per_minute")
    if budget is None:
        print(f"install-test: no idle budget yet; measured {switches}, record it in {IDLE_BUDGET}")
        (VM / "idle.json").write_text(json.dumps({"shell_voluntary_ctxt_switches_per_minute": switches}) + "\n")
        return True
    return switches <= max(budget * 1.2, budget + 3)
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
        " --package-cache /run/pkgcache; echo EXIT=$?\n"
    )
    answers = [
        (rb"disk number: ", "1"),
        (rb"Computer name \[subarchy\]: ", "subarchy-vm"),
        (rb"Your user name: ", USER),
        (rb"Password for \w+: ", PASSWORD),
        (rb"Password for \w+ again: ", PASSWORD),
        (rb"Disk passphrase: ", PASSPHRASE),
        (rb"Disk passphrase again: ", PASSPHRASE),
        (rb"Time zone \[UTC\]: ", "America/Chicago"),
        (rb"Keyboard layout \[us\]: ", ""),
        (rb"Type vda to erase it", "vda"),
    ]
    for prompt, answer in answers:
        serial.expect(re.compile(prompt), 60)
        serial.send(answer + "\n")
    out = serial.expect(re.compile(rb"EXIT=\d+"), timeout)
    return ANSI.sub("", out.decode(errors="replace"))


def install(iso: Path, disk: Path, vars_file: Path, timeout: float, guided_setup: bool = False) -> bool:
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
        serial.run("systemctl is-system-running --wait >/dev/null; pacman-key --init >/dev/null 2>&1; true", timeout=180)
        if guided_setup:
            # The image's own subarchy-setup, installer and repository.
            out = guided(serial, timeout)
        else:
            out = serial.run(
                "/run/src/install/subarchy-install --config /run/src/build/vm/install.conf --yes; echo EXIT=$?",
                timeout=timeout,
            )
        ok = "subarchy-install: done" in out and "EXIT=0" in out
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


def wait_for(serial: Serial, command: str, seconds: int = 60) -> str:
    """Poll a shell condition in the guest for up to `seconds`."""
    return serial.run(
        f"for i in $(seq {seconds}); do {command} && break; sleep 1; done", timeout=seconds + 30
    )


def boot(disk: Path, vars_file: Path) -> bool:
    qmp = VM / "qmp.sock"
    qmp.unlink(missing_ok=True)
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
            "cmdline": serial.run("cat /proc/cmdline"),
            # GPU modes (ADR 0006): a VM has no hybrid graphics, so the uwsm
            # hook must stay silent and the session start in its default.
            "gpu": serial.run("test -r /usr/share/uwsm/env-hyprland.d/50-subarchy-gpu && echo HOOK;"
                              " subcult-gpu-env | wc -l; subcult gpu mode"),
            # Hardware detection (ADR 0005): an Intel host CPU, emulated devices.
            "hw": serial.run("pacman -Qq | grep -E '^(linux-firmware.*|intel-ucode|amd-ucode|thermald)$'; subcult hw info"),
            "update_timer": serial.run(
                "systemctl --user list-timers --all --no-legend | grep -c subcult-update-check;"
                " systemctl --user start subcult-update-check.service; cat ~/.local/state/subcult/update-count",
                timeout=120,
            ),
            "power_auto": serial.run("systemctl show -p Result --value subcult-power-auto; journalctl -b -u subcult-power-auto -o cat"),
            "plymouth": serial.run(f"{sudo} journalctl -b -o cat | grep -c 'Show Plymouth Boot Screen'"),
            # subcult update: snapshot, pacman -Syu, migrations, report.
            "update": serial.run(
                # sudo -k and no stdin: the update must not need a password (ADR 0062).
                "sudo -k; subcult update --yes </dev/null; echo UPDATE_EXIT=$?"
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
        # Desktop (ADR 0029-0032): the SDDM greeter, then a test-only
        # autologin into the uwsm/Hyprland session.
        results["greeter"] = wait_for(serial, "pgrep -a sddm-greeter", 60)
        time.sleep(3)
        screendump(qmp, VM / "greeter.png")
        results["greeter_colours"] = distinct_colours(VM / "greeter.png")
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
        results["fonts"] = serial.run(
            "for r in monospace sans-serif serif; do fc-match -f '%{family[0]}\\n' $r; done")
        results["gtk"] = serial.run(
            "gsettings get org.gnome.desktop.interface icon-theme; gsettings get org.gnome.desktop.interface cursor-theme")
        results["discord"] = serial.run(
            "test -f /usr/share/applications/discord.desktop"
            " && test -f /usr/share/chromium/extensions/cbghhgpcnddeihccjmnadmkaejncjndb.json && echo WEBAPP_OK")
        results["cursor"] = serial.run("ls /usr/share/icons/subcult-cursor/cursors/left_ptr /usr/share/icons/subcult-cursor/hyprcursors/default.hlc")
        # The bar and the idle sample come first, before any window is open.
        screendump(qmp, VM / "bar.png")
        results["bar_colours"] = colours_in(VM / "bar.png", 26)
        # Idle cost: voluntary context switches of all the shell's threads over
        # a quiet minute.
        pid = serial.run("pgrep -u $(id -u) -f 'quickshell -n -p /usr/share/subcult/shell' | head -1").strip()
        ctxt = ("cat /proc/%s/task/*/status 2>/dev/null"
                " | awk '/^voluntary_ctxt_switches/ {s += $2} END {print s + 0}'" % pid)
        before = serial.run(ctxt).strip() if pid.isdigit() else ""
        time.sleep(60)
        after = serial.run(ctxt).strip() if pid.isdigit() else ""
        results["idle"] = int(after) - int(before) if before.isdigit() and after.isdigit() else -1
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
        results["ac_again"] = serial.run(
            f"{sudo} pkill -f '[d]busmock --system --template upower'; {sudo} systemctl start upower.service"
            f" && sleep 2 && systemctl --user restart subcult-shell.service && sleep 8 && {shell_ipc}")
        time.sleep(3)
        screendump(qmp, VM / "session.png")
        results["session_colours"] = distinct_colours(VM / "session.png")
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
        "subcult update ran without a password": "UPDATE_EXIT=0" in r["update"] and "eboot needed" in r["update"],
        "daily update check timer and count": r["update_timer"].splitlines()[0:1] == ["1"]
        and r["update_timer"].strip().splitlines()[-1].isdigit(),
        "power profile service (no battery: unchanged)": r["power_auto"].splitlines()[0:1] == ["success"]
        and "no system battery" in r["power_auto"],
        "update took a snapshot": "subcult update" in r["update"].split("UPDATE_EXIT")[-1],
        "marker created after the snapshots": "MARKED" in r["marker"],
        "@factory snapshot": any(line.endswith(" path @factory") for line in r["subvols"].splitlines()),
        "system running or degraded": state in ("running", "degraded"),
        "hardware packages: microcode, no firmware in a VM": "intel-ucode" in r["hw"].split()
        and "thermald" in r["hw"].split() and "linux-firmware" not in r["hw"] and "VM:        QEMU" in r["hw"],
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
        "Discord web app and Vencord Web installed": "WEBAPP_OK" in r["discord"],
        "shell sees battery power": '"onBattery":true' in r["battery"],
        "shell back on AC with the real UPower": '"onBattery":false' in r["ac_again"],
        "workspace dispatch (Lua expression)": '"id": 3' in r["dispatch"],
        "Alt-Tab switches to the previous window (global shortcuts)": "SWITCHED_GLOBAL" in r["altswitch"].splitlines(),
        "Alt-Tab switches back (IPC)": "SWITCHED_IPC" in r["altswitch"].splitlines(),
        "shell idle within budget": idle_ok(r["idle"]),
    }
    for name, ok in checks.items():
        print(f"install-test: {'ok  ' if ok else 'FAIL'} {name}")
    if not {"SWITCHED_GLOBAL", "SWITCHED_IPC"} <= set(r["altswitch"].splitlines()):
        print("install-test: Alt-Tab:\n" + r["altswitch"].strip())
    if r["shell_errors"].strip():
        print("install-test: shell errors:\n" + r["shell_errors"].strip())
    print(f"install-test: shell idle: {r['idle']} voluntary context switches in 60 s (budget file {IDLE_BUDGET})")
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
    tpm_sock = tpm_dir / "swtpm.sock"
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
        "TPM unlock enabled": "TPM_EXIT=0" in tpm and "TPM unlock: on" in tpm,
        "boots without the passphrase (TPM)": b"assphrase for" not in tpm_boot
        and tpm_state.strip().splitlines()[-1:] in (["running"], ["degraded"]),
    }
    for name, ok in checks.items():
        print(f"install-test: {'ok  ' if ok else 'FAIL'} {name}")
    return all(checks.values())


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("iso", type=Path)
    ap.add_argument("--skip-install", action="store_true", help="boot the existing build/vm disk only")
    ap.add_argument("--guided", action="store_true", help="install by answering subarchy-setup from the image")
    ap.add_argument("--timeout-install", type=float, default=2400)
    args = ap.parse_args()
    for f in (args.iso, OVMF_CODE, OVMF_VARS, ROOT / "build" / "repo" / "subarchy.db"):
        if not f.exists():
            print(f"install-test: missing {f} (run make iso first)", file=sys.stderr)
            return 2
    disk, vars_file = VM / "disk.qcow2", VM / "OVMF_VARS.fd"
    write_config()
    if not args.skip_install and not install(args.iso, disk, vars_file, args.timeout_install, args.guided):
        return 1
    # A failed check in one stage does not skip the others.
    ok = boot(disk, vars_file)
    ok = boot_snapshot(disk, vars_file) and ok
    ok = boot_secureboot(disk, vars_file) and ok
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
