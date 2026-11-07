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

from vmlib import OVMF_CODE, OVMF_VARS, Serial, qemu_command

ROOT = Path(__file__).resolve().parents[2]
VM = ROOT / "build" / "vm"
CACHE = ROOT / "build" / "pkgcache"
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


def install(iso: Path, disk: Path, vars_file: Path, timeout: float) -> bool:
    disk.unlink(missing_ok=True)
    subprocess.run(["qemu-img", "create", "-q", "-f", "qcow2", str(disk), "24G"], check=True)
    shutil.copy(OVMF_VARS, vars_file)
    CACHE.mkdir(parents=True, exist_ok=True)
    # pacman downloads as the guest's unprivileged alpm user; the 9p share
    # passes host modes through, so the cache must be writable to everyone.
    CACHE.chmod(0o777)
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


def boot(disk: Path, vars_file: Path) -> bool:
    cmd = qemu_command(vars_file, "-drive", f"file={disk},if=virtio,format=qcow2")
    started = time.monotonic()
    proc, serial, log = start(cmd, VM / "boot-serial.log")
    try:
        serial.expect(re.compile(rb"assphrase for"), 180)
        print(f"install-test: LUKS prompt after {time.monotonic() - started:.0f}s")
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
            # A snapshot must show up as a boot entry (limine-snapper-sync).
            "snapshot": serial.run(
                f"{sudo} snapper -c root create -d install-test >/dev/null && sleep 5"
                f" && {sudo} limine-snapper-sync >/dev/null 2>&1; {sudo} cat /boot/limine.conf",
                timeout=120,
            ),
            "state": serial.run("systemctl is-system-running --wait", timeout=120),
            "failed": serial.run("systemctl --failed --no-legend --plain | awk '{print $1}'"),
        }
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
        "@factory snapshot": any(line.endswith(" path @factory") for line in r["subvols"].splitlines()),
        "system running or degraded": state in ("running", "degraded"),
    }
    for name, ok in checks.items():
        print(f"install-test: {'ok  ' if ok else 'FAIL'} {name}")
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
    }
    for name, ok in checks.items():
        print(f"install-test: {'ok  ' if ok else 'FAIL'} {name}")
    return all(checks.values())


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("iso", type=Path)
    ap.add_argument("--skip-install", action="store_true", help="boot the existing build/vm disk only")
    ap.add_argument("--timeout-install", type=float, default=2400)
    args = ap.parse_args()
    for f in (args.iso, OVMF_CODE, OVMF_VARS, ROOT / "build" / "repo" / "subarchy.db"):
        if not f.exists():
            print(f"install-test: missing {f} (run make iso first)", file=sys.stderr)
            return 2
    disk, vars_file = VM / "disk.qcow2", VM / "OVMF_VARS.fd"
    write_config()
    if not args.skip_install and not install(args.iso, disk, vars_file, args.timeout_install):
        return 1
    if not boot(disk, vars_file):
        return 1
    return 0 if boot_snapshot(disk, vars_file) else 1


if __name__ == "__main__":
    sys.exit(main())
