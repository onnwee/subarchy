"""Real Linux-PAM conversations against private, unprivileged test stacks."""

import json
import os
from pathlib import Path
import pwd
import subprocess
import sys
import tempfile
import time
import unittest


HELPER = Path(__file__).with_name("pam-helper.py")


class PamHelperTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.directory = Path(self.temp.name)

    def authenticate(self, stack, response=""):
        (self.directory / "test").write_text(stack)
        result = subprocess.run([sys.executable, str(HELPER), "test", str(self.directory)],
                                input=response, capture_output=True, text=True, timeout=5,
                                env=os.environ | {"USER": "subarchy-test-other-user"})
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stderr, "")
        frames = [json.loads(line) for line in result.stdout.splitlines()]
        self.assertEqual(frames[-1]["event"], "result")
        self.assertNotIn("dummy-password", result.stdout)
        return frames

    def test_permit_and_deny_are_distinct(self):
        for module, expected in (("permit", 0), ("deny", 1)):
            with self.subTest(module=module):
                frames = self.authenticate(f"auth required pam_{module}.so\n")
                self.assertEqual(frames, [{"event": "result", "result": expected}])

    def test_module_failure_is_not_authentication(self):
        self.assertEqual(self.authenticate("auth required missing_subarchy_test_module.so\n")[-1]["result"], 2)

    def test_conversation_transfers_utf8_and_uses_the_real_uid(self):
        # pam_exec receives the response on stdin and PAM's actual user in
        # PAM_USER. No password appears in argv or in a captured log.
        script = self.directory / "check.py"
        script.write_text("import os,sys\n"
                          "ok = sys.stdin.buffer.read().rstrip(b'\\0') == 'dummy-password-é'.encode()\n"
                          f"ok = ok and os.environ['PAM_USER'] == {pwd.getpwuid(os.getuid()).pw_name!r}\n"
                          "sys.exit(0 if ok else 1)\n")
        stack = f"auth required pam_exec.so expose_authtok {sys.executable} {script}\n"
        frames = self.authenticate(stack, json.dumps({"response": "dummy-password-é"}) + "\n")
        self.assertEqual(frames[0]["style"], 1)
        self.assertEqual(frames[-1]["result"], 0)
        self.assertEqual(len(frames), 2)

    def test_malformed_missing_and_oversized_responses_fail_closed(self):
        stack = "auth required pam_exec.so expose_authtok /usr/bin/true\n"
        for response in ("", "not json\n", "{}\n", '{"response":null}\n',
                         json.dumps({"response": "x\0y"}) + "\n",
                         json.dumps({"response": "x" * 513}) + "\n", "x" * 65537,
                         "[" * 1500 + "0" + "]" * 1500 + "\n"):
            with self.subTest(length=len(response)):
                self.assertNotEqual(self.authenticate(stack, response)[-1]["result"], 0)

    def test_informational_messages_are_framed(self):
        message = self.directory / "message"
        message.write_text('A "quoted" message — é\n')
        frames = self.authenticate(f"auth optional pam_echo.so file={message}\nauth required pam_deny.so\n")
        self.assertEqual(frames[0], {"event": "message", "style": 4, "text": 'A "quoted" message — é'})
        self.assertEqual(frames[-1]["result"], 1)

    def test_parent_exit_stops_a_waiting_helper(self):
        (self.directory / "test").write_text("auth required pam_exec.so expose_authtok /usr/bin/true\n")
        # The controller exits only after PAM is waiting for a response.
        # Losing the lock must not leave that authentication alive.
        controller = (
            "import os,subprocess,sys\n"
            f"p = subprocess.Popen({[sys.executable, str(HELPER), 'test', str(self.directory)]!r}, "
            "stdin=subprocess.PIPE, stdout=subprocess.PIPE)\n"
            "assert b'\"message\"' in p.stdout.readline()\n"
            "print(p.pid, flush=True)\n"
            "os._exit(0)\n"
        )
        result = subprocess.run([sys.executable, "-c", controller], capture_output=True,
                                text=True, check=True, timeout=5)
        pid = int(result.stdout.strip())
        for _ in range(100):
            try:
                state = Path(f"/proc/{pid}/stat").read_text().rsplit(")", 1)[1].split()[0]
            except (FileNotFoundError, ProcessLookupError):
                # The process may vanish before open (ENOENT) or between
                # opening the procfs node and reading it (ESRCH).
                return
            if state == "Z":
                return
            time.sleep(0.01)
        self.fail("PAM helper survived its parent")


if __name__ == "__main__":
    unittest.main()
