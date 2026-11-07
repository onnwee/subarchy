#!/usr/bin/env python3
"""Boot a Subarchy ISO in QEMU (UEFI, headless) and check it from the serial console.

Passes when the live system boots to a root shell, /etc/os-release says
Subarchy, and systemd reports a running (or only degraded) system.

Usage: tools/iso/boot-test.py path/to/subarchy.iso [--timeout 300] [--log FILE]
"""

from __future__ import annotations

import argparse
import re
import shutil
import subprocess
import sys
import tempfile
import time
from pathlib import Path

from vmlib import OVMF_CODE, OVMF_VARS, Serial, qemu_command


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("iso", type=Path)
    ap.add_argument("--timeout", type=float, default=300)
    ap.add_argument("--log", type=Path)
    args = ap.parse_args()

    for f in (args.iso, OVMF_CODE, OVMF_VARS):
        if not f.exists():
            print(f"boot-test: missing {f}", file=sys.stderr)
            return 2

    with tempfile.TemporaryDirectory() as tmp:
        vars_copy = Path(tmp) / "OVMF_VARS.fd"
        shutil.copy(OVMF_VARS, vars_copy)
        log_path = args.log or Path(tmp) / "serial.log"
        cmd = qemu_command(vars_copy, "-cdrom", str(args.iso), "-boot", "d")
        started = time.monotonic()
        with open(log_path, "wb") as log, subprocess.Popen(
            cmd, stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.STDOUT
        ) as proc:
            serial = Serial(proc, log)
            try:
                serial.expect(re.compile(rb"Welcome to .*Subarchy"), args.timeout)
                print(f"boot-test: systemd greeting seen after {time.monotonic() - started:.0f}s")
                serial.expect(re.compile(rb"automatic login"), args.timeout)
                serial.claim_prompt(60)
                print(f"boot-test: root shell after {time.monotonic() - started:.0f}s")
                osr = serial.run("cat /etc/os-release")
                state = serial.run("systemctl is-system-running --wait", timeout=120).strip().splitlines()[-1]
                kernel = serial.run("uname -r")
                failed = serial.run("systemctl --failed --no-legend --plain | awk '{print $1}'")
                installer = serial.run("subarchy-install --help | head -1")
                serial.send("poweroff\n")
            except TimeoutError as e:
                proc.kill()
                print(f"boot-test: FAIL, timed out {e}; serial log: {log_path}", file=sys.stderr)
                print(serial.tail(), file=sys.stderr)
                return 1
            try:
                proc.wait(timeout=60)
            except subprocess.TimeoutExpired:
                proc.kill()

    checks = {
        "os-release ID=subarchy": "ID=subarchy" in osr,
        "os-release NAME=Subarchy": 'NAME="Subarchy"' in osr,
        "kernel is linux-zen": "zen" in kernel,
        "system running or degraded": state in ("running", "degraded"),
        "installer on the image": "Subarchy installer" in installer,
    }
    for name, ok in checks.items():
        print(f"boot-test: {'ok  ' if ok else 'FAIL'} {name}")
    if failed.strip():
        print("boot-test: failed units: " + ", ".join(failed.split()))
    print(f"boot-test: kernel {kernel.strip()}, state {state}")
    return 0 if all(checks.values()) else 1


if __name__ == "__main__":
    sys.exit(main())
