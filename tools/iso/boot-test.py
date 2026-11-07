#!/usr/bin/env python3
"""Boot a Subarchy ISO in QEMU (UEFI, headless) and check it from the serial console.

Passes when the live system boots to a root shell, /etc/os-release says
Subarchy, and systemd reports a running (or only degraded) system.

Usage: tools/iso/boot-test.py path/to/subarchy.iso [--timeout 300] [--log FILE]
"""

from __future__ import annotations

import argparse
import os
import re
import selectors
import shutil
import subprocess
import sys
import tempfile
import time
from pathlib import Path

OVMF_CODE = Path("/usr/share/edk2/x64/OVMF_CODE.4m.fd")
OVMF_VARS = Path("/usr/share/edk2/x64/OVMF_VARS.4m.fd")
PROMPT = re.compile(rb"SUBARCHY-READY> ")
ANSI = re.compile(r"\x1b\[[0-9;?]*[ -/]*[@-~]|\x1b[()][0-9A-B]|\r")


class Serial:
    """Reads QEMU's serial console from its stdout and writes to its stdin."""

    def __init__(self, proc: subprocess.Popen, log):
        self.proc = proc
        self.log = log
        self.buf = b""
        self.sel = selectors.DefaultSelector()
        self.sel.register(proc.stdout, selectors.EVENT_READ)
        os.set_blocking(proc.stdout.fileno(), False)

    def expect(self, pattern: re.Pattern, timeout: float) -> bytes:
        deadline = time.monotonic() + timeout
        while True:
            m = pattern.search(self.buf)
            if m:
                out, self.buf = self.buf[: m.end()], self.buf[m.end():]
                return out
            left = deadline - time.monotonic()
            if left <= 0 or self.proc.poll() is not None:
                raise TimeoutError(f"waiting for {pattern.pattern!r}")
            for _ in self.sel.select(min(left, 1.0)):
                chunk = self.proc.stdout.read(65536) or b""
                self.buf += chunk
                self.log.write(chunk)
                self.log.flush()

    def run(self, command: str, timeout: float = 30) -> str:
        self.buf = b""
        self.proc.stdin.write(command.encode() + b"\n")
        self.proc.stdin.flush()
        out = ANSI.sub("", self.expect(PROMPT, timeout).decode(errors="replace"))
        lines = out.splitlines()
        return "\n".join(lines[1:-1])  # drop the echoed command and the prompt

    def claim_prompt(self, timeout: float) -> None:
        """Replace the autologin shell with a plain bash, retrying until its prompt shows.

        The live image's zsh (grml) redraws its own prompt, so the test runs
        bash instead. The quoted halves keep the echoed command from matching
        PROMPT.
        """
        deadline = time.monotonic() + timeout
        while time.monotonic() < deadline:
            self.proc.stdin.write(
                b"exec env TERM=dumb PS1='SUBARCHY''-READY> ' bash --norc --noprofile -i\n"
            )
            self.proc.stdin.flush()
            try:
                self.expect(PROMPT, 5)
                self.buf = b""
                return
            except TimeoutError:
                continue
        raise TimeoutError("shell prompt")


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
        cmd = [
            "qemu-system-x86_64", "-machine", "q35", "-m", "4096", "-smp", "4",
            "-drive", f"if=pflash,format=raw,readonly=on,file={OVMF_CODE}",
            "-drive", f"if=pflash,format=raw,file={vars_copy}",
            "-cdrom", str(args.iso), "-boot", "d",
            "-display", "none", "-serial", "stdio", "-monitor", "none",
            "-nic", "user,model=virtio-net-pci",
        ]
        if os.access("/dev/kvm", os.R_OK | os.W_OK):
            cmd[1:1] = ["-enable-kvm", "-cpu", "host"]
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
                serial.proc.stdin.write(b"poweroff\n")
                serial.proc.stdin.flush()
            except TimeoutError as e:
                proc.kill()
                print(f"boot-test: FAIL, timed out {e}; serial log: {log_path}", file=sys.stderr)
                tail = log_path.read_bytes()[-2000:].decode(errors="replace")
                print(tail, file=sys.stderr)
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
    }
    for name, ok in checks.items():
        print(f"boot-test: {'ok  ' if ok else 'FAIL'} {name}")
    if failed.strip():
        print("boot-test: failed units: " + ", ".join(failed.split()))
    print(f"boot-test: kernel {kernel.strip()}, state {state}")
    return 0 if all(checks.values()) else 1


if __name__ == "__main__":
    sys.exit(main())
