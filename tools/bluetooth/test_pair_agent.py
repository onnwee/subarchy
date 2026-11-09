"""Real Gio/Agent1 IPC against a private fake BlueZ; no system bus or radio."""

import json
import os
from pathlib import Path
import selectors
import subprocess
import threading
import time
import unittest

from gi.repository import Gio, GLib

DEVICE = "/org/bluez/hci0/dev_AA_BB_CC_DD_EE_FF"
XML = """<node>
<interface name="org.bluez.AgentManager1">
 <method name="RegisterAgent"><arg type="o" direction="in"/><arg type="s" direction="in"/></method>
 <method name="UnregisterAgent"><arg type="o" direction="in"/></method>
 <method name="RequestDefaultAgent"><arg type="o" direction="in"/></method>
</interface>
<interface name="org.bluez.Device1"><method name="Pair"/><method name="CancelPairing"/></interface>
<interface name="org.freedesktop.DBus.Properties">
 <method name="Set"><arg type="s" direction="in"/><arg type="s" direction="in"/><arg type="v" direction="in"/></method>
</interface></node>"""


class Bluez:
    def __init__(self):
        self.bus = subprocess.Popen(
            ["dbus-daemon", "--session", "--nofork", "--print-address=1"],
            stdout=subprocess.PIPE, stderr=subprocess.DEVNULL,
        )
        self.address = self.bus.stdout.readline().decode().strip()
        flags = Gio.DBusConnectionFlags.AUTHENTICATION_CLIENT | Gio.DBusConnectionFlags.MESSAGE_BUS_CONNECTION
        self.connection = Gio.DBusConnection.new_for_address_sync(self.address, flags, None, None)
        self.connection.call_sync(
            "org.freedesktop.DBus", "/org/freedesktop/DBus", "org.freedesktop.DBus", "RequestName",
            GLib.Variant("(su)", ("org.bluez", 0)), None, Gio.DBusCallFlags.NONE, 2000, None,
        )
        info = Gio.DBusNodeInfo.new_for_xml(XML)
        self.objects = [self.connection.register_object(
            "/org/bluez" if interface.name.endswith("AgentManager1") else DEVICE,
            interface, self.method, None, None,
        ) for interface in info.interfaces]
        self.loop = GLib.MainLoop()
        self.thread = threading.Thread(target=self.loop.run, daemon=True)
        self.thread.start()
        self.agent = None
        self.pair_call = None
        self.kind = "RequestConfirmation"
        self.agent_reply = None
        self.trusted = False
        self.trust_error = False
        self.default_calls = 0
        self.cancel_calls = 0

    def method(self, _connection, sender, _path, interface, method, parameters, invocation):
        args = parameters.unpack()
        if method == "RegisterAgent":
            self.agent = (sender, args[0], args[1])
            invocation.return_value(None)
        elif method == "UnregisterAgent":
            self.agent = None
            invocation.return_value(None)
        elif method == "RequestDefaultAgent":
            self.default_calls += 1
            invocation.return_dbus_error("org.bluez.Error.Rejected", "Must not replace global default")
        elif method == "Pair":
            self.pair_call = invocation
            if not self.agent or sender != self.agent[0]:
                self.finish_pair("Pair used a different connection from its agent")
                return
            values = {
                "RequestConfirmation": ("(ou)", (DEVICE, 123)),
                "RequestPinCode": ("(o)", (DEVICE,)),
                "RequestPasskey": ("(o)", (DEVICE,)),
                "RequestAuthorization": ("(o)", (DEVICE,)),
                "AuthorizeService": ("(os)", (DEVICE, "0000110b-0000-1000-8000-00805f9b34fb")),
                "DisplayPasskey": ("(ouq)", (DEVICE, 123, 2)),
            }
            signature, value = values[self.kind]
            self.connection.call(
                self.agent[0], self.agent[1], "org.bluez.Agent1", self.kind,
                GLib.Variant(signature, value), None, Gio.DBusCallFlags.NONE,
                4000, None, self.agent_answer, None,
            )
        elif method == "CancelPairing":
            self.cancel_calls += 1
            self.finish_pair("Canceled")
            invocation.return_value(None)
        elif interface.endswith("Properties") and method == "Set":
            if self.trust_error:
                invocation.return_dbus_error("org.bluez.Error.Failed", "Fixture trust failure")
                return
            if args[:2] != ("org.bluez.Device1", "Trusted"):
                invocation.return_dbus_error("org.bluez.Error.InvalidArguments", "Unexpected property")
                return
            self.trusted = args[2]
            invocation.return_value(None)

    def agent_answer(self, connection, result, _data):
        try:
            value = connection.call_finish(result)
            self.agent_reply = value.unpack() if value else ()
            self.finish_pair()
        except GLib.Error:
            self.finish_pair("Rejected")

    def finish_pair(self, error=None):
        invocation, self.pair_call = self.pair_call, None
        if invocation:
            if error:
                invocation.return_dbus_error("org.bluez.Error.AuthenticationRejected", error)
            else:
                invocation.return_value(None)

    def close(self):
        self.loop.quit()
        self.thread.join(timeout=2)
        for object_id in self.objects:
            self.connection.unregister_object(object_id)
        self.connection.close_sync(None)
        self.bus.terminate()
        self.bus.wait(timeout=3)
        self.bus.stdout.close()


class Client:
    def __init__(self, address):
        env = dict(os.environ, DBUS_SYSTEM_BUS_ADDRESS=address)
        self.process = subprocess.Popen(
            ["/usr/bin/python3", str(Path(__file__).with_name("pair-agent.py"))],
            stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE, env=env,
        )
        self.selector = selectors.DefaultSelector()
        self.selector.register(self.process.stdout, selectors.EVENT_READ)
        self.buffer = bytearray()
        self.events = []
        self.until("ready")

    def send(self, doc):
        self.process.stdin.write(json.dumps(doc).encode() + b"\n")
        self.process.stdin.flush()

    def until(self, event):
        deadline = time.monotonic() + 6
        while time.monotonic() < deadline:
            if b"\n" in self.buffer:
                line, _, rest = self.buffer.partition(b"\n")
                self.buffer[:] = rest
                doc = json.loads(line)
                self.events.append(doc)
                if doc["event"] == event:
                    return doc
            elif self.selector.select(max(0, deadline - time.monotonic())):
                chunk = os.read(self.process.stdout.fileno(), 4096)
                if not chunk:
                    raise AssertionError("Pairing helper exited before " + event)
                self.buffer.extend(chunk)
        raise AssertionError("Timed out waiting for " + event)

    def close(self):
        if self.process.poll() is None:
            self.process.terminate()
            self.process.wait(timeout=4)
        self.selector.close()
        for stream in (self.process.stdin, self.process.stdout, self.process.stderr):
            stream.close()


class PairingTest(unittest.TestCase):
    def setUp(self):
        self.bluez = Bluez()
        self.addCleanup(self.bluez.close)
        self.client = Client(self.bluez.address)
        self.addCleanup(self.client.close)

    def prompt(self, kind):
        self.bluez.kind = kind
        self.client.send({"action": "pair", "device": DEVICE})
        return self.client.until("prompt")

    def test_confirmation_and_trust(self):
        prompt = self.prompt("RequestConfirmation")
        self.assertEqual(prompt["code"], "000123")
        self.assertEqual(self.bluez.agent[2], "KeyboardDisplay")
        self.client.send({"action": "respond", "id": prompt["id"], "accept": True})
        self.assertTrue(self.client.until("result")["ok"])
        self.assertTrue(self.bluez.trusted)
        self.assertEqual(self.bluez.default_calls, 0)

    def test_pin_and_passkey(self):
        for kind, value, expected in [("RequestPinCode", "fixture-pin", "fixture-pin"), ("RequestPasskey", "000123", 123)]:
            with self.subTest(kind=kind):
                prompt = self.prompt(kind)
                self.client.send({"action": "respond", "id": prompt["id"], "accept": True, "value": value})
                self.assertTrue(self.client.until("result")["ok"])
                self.assertEqual(self.bluez.agent_reply, (expected,))

    def test_authorization_and_service(self):
        for kind in ("RequestAuthorization", "AuthorizeService"):
            with self.subTest(kind=kind):
                prompt = self.prompt(kind)
                self.client.send({"action": "respond", "id": prompt["id"], "accept": True})
                self.assertTrue(self.client.until("result")["ok"])

    def test_invalid_and_expired_response_keeps_request(self):
        prompt = self.prompt("RequestPasskey")
        for request_id, value in [(prompt["id"] - 1, "123"), (prompt["id"], "not-a-key")]:
            self.client.send({"action": "respond", "id": request_id, "accept": True, "value": value})
            self.client.until("error")
        self.client.send({"action": "respond", "id": prompt["id"], "accept": True, "value": "0"})
        self.assertTrue(self.client.until("result")["ok"])
        self.assertEqual(self.bluez.agent_reply, (0,))

    def test_rejection(self):
        prompt = self.prompt("RequestConfirmation")
        self.client.send({"action": "respond", "id": prompt["id"], "accept": False})
        self.assertFalse(self.client.until("result")["ok"])
        self.assertFalse(self.bluez.trusted)

    def test_trust_failure_reports_partial_success(self):
        self.bluez.trust_error = True
        prompt = self.prompt("RequestConfirmation")
        self.client.send({"action": "respond", "id": prompt["id"], "accept": True})
        result = self.client.until("result")
        self.assertTrue(result["ok"])
        self.assertIn("automatic reconnect could not be enabled", result["message"])
        self.assertFalse(self.bluez.trusted)

    def test_bluez_restart_stops_agent(self):
        self.bluez.connection.call_sync(
            "org.freedesktop.DBus", "/org/freedesktop/DBus", "org.freedesktop.DBus", "ReleaseName",
            GLib.Variant("(s)", ("org.bluez",)), None, Gio.DBusCallFlags.NONE, 2000, None,
        )
        self.assertIn("Bluetooth restarted", self.client.until("error")["message"])
        self.client.process.wait(timeout=4)
        self.assertIsNone(self.bluez.agent)

    def test_cancel(self):
        self.prompt("RequestPinCode")
        self.client.send({"action": "cancel"})
        self.assertFalse(self.client.until("result")["ok"])
        self.assertFalse(self.bluez.trusted)

    def test_untrusted_bus_caller_cannot_ask_for_pin(self):
        result = subprocess.run([
            "gdbus", "call", "--address", self.bluez.address, "--dest", self.bluez.agent[0],
            "--object-path", self.bluez.agent[1], "--method", "org.bluez.Agent1.RequestPinCode", DEVICE,
        ], capture_output=True, timeout=3)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn(b"AccessDenied", result.stderr)

    def test_invalid_path_does_not_pair(self):
        self.client.send({"action": "pair", "device": "/org/bluez/not-a-device"})
        self.assertFalse(self.client.until("result")["ok"])
        self.assertIsNone(self.bluez.pair_call)

    def test_display_code_and_typed_progress(self):
        prompt = self.prompt("DisplayPasskey")
        self.assertEqual((prompt["kind"], prompt["code"], prompt["entered"]), ("display-passkey", "000123", 2))
        self.assertTrue(self.client.until("result")["ok"])

    def test_closing_panel_cancels_and_unregisters_agent(self):
        self.prompt("RequestPinCode")
        self.client.process.stdin.close()
        self.client.process.wait(timeout=4)
        self.assertIsNone(self.bluez.agent)
        self.assertIsNone(self.bluez.pair_call)
        self.assertFalse(self.bluez.trusted)

    def test_invalid_shape_and_oversized_input_do_not_break_next_pair(self):
        for doc in ([], None, {"action": "respond", "id": True, "accept": True}):
            self.client.send(doc)
            self.client.until("error")
        self.client.process.stdin.write(b"x" * 9000 + b"\n")
        self.client.process.stdin.flush()
        self.client.until("error")
        prompt = self.prompt("RequestConfirmation")
        self.client.send({"action": "respond", "id": prompt["id"], "accept": True})
        self.assertTrue(self.client.until("result")["ok"])


if __name__ == "__main__":
    unittest.main()
