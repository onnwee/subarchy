"""QEMU helpers shared by the ISO boot test and the install test.

Runs a UEFI (OVMF) q35 guest headless with its serial console on stdio and
drives that console with expect-style reads.
"""

from __future__ import annotations

import os
import re
import selectors
import subprocess
import time
from pathlib import Path

# Secure Boot capable firmware; with the stock VARS template it starts in
# setup mode (no keys), so unsigned media boot until keys are enrolled.
OVMF_CODE = Path("/usr/share/edk2/x64/OVMF_CODE.secboot.4m.fd")
OVMF_VARS = Path("/usr/share/edk2/x64/OVMF_VARS.4m.fd")
PROMPT = re.compile(rb"SUBARCHY-READY> ")
ANSI = re.compile(r"\x1b\[[0-9;?]*[ -/]*[@-~]|\x1b\][^\x07\x1b]*(\x07|\x1b\\)|\x1b[()][0-9A-B]|\r")


def screendump(qmp_socket: Path, out: Path, timeout: float = 10) -> None:
    """Save the guest display as a PNG through QEMU's QMP socket."""
    import json
    import socket

    with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as s:
        s.settimeout(timeout)
        s.connect(str(qmp_socket))
        f = s.makefile("rw")
        f.readline()  # greeting
        for cmd in (
            {"execute": "qmp_capabilities"},
            {"execute": "screendump", "arguments": {"filename": str(out), "format": "png"}},
        ):
            f.write(json.dumps(cmd) + "\n")
            f.flush()
            while True:
                reply = json.loads(f.readline())
                if "return" in reply:
                    break
                if "error" in reply:
                    raise RuntimeError(f"QMP {cmd['execute']}: {reply['error']}")


_QCODES = {"-": "minus", "/": "slash", " ": "spc", ".": "dot", ",": "comma", "=": "equal", "\n": "ret"}


def send_keys(qmp_socket: Path, *keys: str, timeout: float = 10) -> None:
    """Press keys on the guest's keyboard through QMP. A key is a QEMU key
    name ("ret", "esc", "down") or a combination joined by "+"."""
    import json
    import socket

    with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as s:
        s.settimeout(timeout)
        s.connect(str(qmp_socket))
        f = s.makefile("rw")
        f.readline()  # greeting
        cmds = [{"execute": "qmp_capabilities"}]
        for key in keys:
            codes = [{"type": "qcode", "data": k} for k in key.split("+")]
            cmds.append({"execute": "send-key", "arguments": {"keys": codes, "hold-time": 40}})
        for cmd in cmds:
            f.write(json.dumps(cmd) + "\n")
            f.flush()
            while True:
                reply = json.loads(f.readline())
                if "return" in reply:
                    break
                if "error" in reply:
                    raise RuntimeError(f"QMP {cmd['execute']}: {reply['error']}")
            time.sleep(0.08)  # one key at a time: QEMU drops keys sent while one is held


def type_text(qmp_socket: Path, text: str) -> None:
    """Type text on the guest's keyboard (US layout)."""
    keys = []
    for ch in text:
        if ch in _QCODES:
            keys.append(_QCODES[ch])
        elif ch == "_":
            keys.append("shift+minus")
        elif ch.isupper():
            keys.append("shift+" + ch.lower())
        elif ch.isalnum():
            keys.append(ch)
        else:
            raise ValueError(f"no key for {ch!r}")
    send_keys(qmp_socket, *keys)


def distinct_colours(png: Path) -> int:
    """Number of distinct colours in an image (ImageMagick); 1 means blank."""
    out = subprocess.run(["magick", "identify", "-format", "%k", str(png)], capture_output=True, text=True, check=True)
    return int(out.stdout.strip())


def colours_in(png: Path, rows: int) -> set[str]:
    """Colours present in the top `rows` rows of an image, as RRGGBB."""
    out = subprocess.run(
        ["magick", str(png), "-crop", f"x{rows}+0+0", "+repage", "-format", "%c", "histogram:info:-"],
        capture_output=True, text=True, check=True)
    return {m.upper() for m in re.findall(r"#([0-9A-Fa-f]{6})", out.stdout)}


def has_colour(png: Path, colour: str) -> bool:
    """Whether any pixel of an image has this RRGGBB colour."""
    out = subprocess.run(["magick", str(png), "-format", "%c", "histogram:info:-"],
                         capture_output=True, text=True, check=True)
    return colour.upper() in {m.upper() for m in re.findall(r"#([0-9A-Fa-f]{6})", out.stdout)}


def qemu_command(vars_file: Path, *extra: str, memory: str = "4096", network: bool = True) -> list[str]:
    """Base QEMU command line: q35, OVMF, serial on stdio, user networking (or none)."""
    cmd = [
        "qemu-system-x86_64", "-machine", "q35,smm=on", "-m", memory, "-smp", "4",
        "-global", "driver=cfi.pflash01,property=secure,value=on",
        "-drive", f"if=pflash,format=raw,readonly=on,file={OVMF_CODE}",
        "-drive", f"if=pflash,format=raw,file={vars_file}",
        "-display", "none", "-serial", "stdio", "-monitor", "none",
        "-nic", "user,model=virtio-net-pci" if network else "none",
        *extra,
    ]
    if os.access("/dev/kvm", os.R_OK | os.W_OK):
        cmd[1:1] = ["-enable-kvm", "-cpu", "host"]
    return cmd


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

    def send(self, text: str) -> None:
        self.proc.stdin.write(text.encode())
        self.proc.stdin.flush()

    def run(self, command: str, timeout: float = 30) -> str:
        """Run a command at the claimed prompt and return its output.

        Each command ends with a numbered marker, so a stray prompt left
        over from an earlier retry cannot shift output to the next command.
        The quoted halves keep the echoed command from matching the marker.
        """
        self.seq = getattr(self, "seq", 0) + 1
        end = f"__END_{self.seq}__"
        self.buf = b""
        self.send(f"{command}; printf '%s\\n' '__E''ND_{self.seq}__'\n")
        out = ANSI.sub("", self.expect(re.compile(end.encode()), timeout).decode(errors="replace"))
        lines = out.splitlines()
        # The tty can echo the command twice (type-ahead, then at the prompt);
        # output starts after the last echo.
        echoes = [i for i, line in enumerate(lines) if f"'__E''ND_{self.seq}__'" in line]
        start = echoes[-1] + 1 if echoes else 0
        return "\n".join(lines[start:-1])

    def settle(self, quiet: float, timeout: float) -> None:
        """Read until the guest has printed nothing for `quiet` seconds."""
        deadline = time.monotonic() + timeout
        while time.monotonic() < deadline and self.sel.select(quiet):
            chunk = self.proc.stdout.read(65536) or b""
            self.buf += chunk
            self.log.write(chunk)
            self.log.flush()

    def claim_prompt(self, timeout: float, attempt: float = 5) -> None:
        """Replace the login shell with a plain bash, retrying until its prompt shows.

        zsh prompts (grml on the ISO) redraw themselves, so the tests run
        bash. The quoted halves keep the echoed command from matching PROMPT.
        """
        deadline = time.monotonic() + timeout
        # A shell that is still starting loses what is typed at it, so wait
        # for the login's output to stop first.
        self.settle(min(1.0, attempt), min(15.0, timeout))
        first = True
        while time.monotonic() < deadline:
            # The front of the line can still be lost. What is left may end
            # inside a quote, and zsh then holds every later line as its
            # continuation; Ctrl-C abandons that. Not on the first try,
            # where it could still reach the login prompt.
            if not first:
                self.send("\x03")
            first = False
            self.send("exec env TERM=dumb PS1='SUBARCHY''-READY> ' bash --norc --noprofile -i\n")
            try:
                self.expect(PROMPT, attempt)
                # A serial console is 80 columns; tools like findmnt truncate
                # to fit. Set at the claimed prompt, where nothing is lost.
                self.buf = b""
                self.send("stty cols 1000\n")
                self.expect(PROMPT, attempt)
                self.buf = b""
                return
            except TimeoutError:
                continue
        raise TimeoutError("shell prompt")

    def tail(self, n: int = 2000) -> str:
        return ANSI.sub("", self.buf[-n:].decode(errors="replace"))
