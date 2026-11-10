#!/usr/bin/python3
"""Panel-owned BlueZ pairing agent; JSON lines are private UI IPC, never logs."""

import json
import os
import re
import signal
import sys

from gi.repository import Gio, GLib

AGENT_PATH = "/tv/subcult/bluetooth/agent"
DEVICE = re.compile(r"/org/bluez/hci[0-9]+/dev_(?:[0-9A-Fa-f]{2}_){5}[0-9A-Fa-f]{2}\Z")
AGENT_XML = """<node><interface name="org.bluez.Agent1">
  <method name="Release"/>
  <method name="RequestPinCode"><arg type="o" direction="in"/><arg type="s" direction="out"/></method>
  <method name="DisplayPinCode"><arg type="o" direction="in"/><arg type="s" direction="in"/></method>
  <method name="RequestPasskey"><arg type="o" direction="in"/><arg type="u" direction="out"/></method>
  <method name="DisplayPasskey"><arg type="o" direction="in"/><arg type="u" direction="in"/><arg type="q" direction="in"/></method>
  <method name="RequestConfirmation"><arg type="o" direction="in"/><arg type="u" direction="in"/></method>
  <method name="RequestAuthorization"><arg type="o" direction="in"/></method>
  <method name="AuthorizeService"><arg type="o" direction="in"/><arg type="s" direction="in"/></method>
  <method name="Cancel"/>
</interface></node>"""


class PairAgent:
    def __init__(self, connection, emit, quit_loop):
        self.connection = connection
        self.emit = emit
        self.quit_loop = quit_loop
        self.owner = ""
        self.registered = False
        self.object_id = 0
        self.watch_id = 0
        self.device = ""
        self.generation = 0
        self.request_id = 0
        self.pending = None
        self.cancel_requested = False
        self.cancellable = None
        self.closing = False

    def start(self):
        # Subscribing only queues the match rule. The calls below wait for
        # their replies on the same connection, so the bus has the rule
        # before "ready"; subscribed last, a restart right after "ready"
        # could be missed.
        self.watch_id = self.connection.signal_subscribe(
            "org.freedesktop.DBus", "org.freedesktop.DBus", "NameOwnerChanged",
            "/org/freedesktop/DBus", "org.bluez", Gio.DBusSignalFlags.NONE,
            self.owner_changed, None,
        )
        self.owner = self.connection.call_sync(
            "org.freedesktop.DBus", "/org/freedesktop/DBus", "org.freedesktop.DBus",
            "GetNameOwner", GLib.Variant("(s)", ("org.bluez",)), None,
            Gio.DBusCallFlags.NONE, 5000, None,
        ).unpack()[0]
        info = Gio.DBusNodeInfo.new_for_xml(AGENT_XML).interfaces[0]
        self.object_id = self.connection.register_object(AGENT_PATH, info, self.handle, None, None)
        self.connection.call_sync(
            self.owner, "/org/bluez", "org.bluez.AgentManager1", "RegisterAgent",
            GLib.Variant("(os)", (AGENT_PATH, "KeyboardDisplay")), None,
            Gio.DBusCallFlags.NONE, 5000, None,
        )
        self.registered = True
        self.emit({"event": "ready"})

    def owner_changed(self, _connection, _sender, _path, _interface, _signal, parameters, _data):
        if parameters.unpack()[2] != self.owner:
            self.emit({"event": "error", "message": "Bluetooth restarted. Reopen the panel to pair."})
            self.quit_loop()

    def clear_request(self):
        if self.pending:
            self.pending[2].return_dbus_error("org.bluez.Error.Canceled", "Pairing request canceled")
            self.pending = None
        self.emit({"event": "clear"})

    def handle(self, _connection, sender, _path, _interface, method, parameters, invocation):
        if sender != self.owner:
            invocation.return_dbus_error("org.freedesktop.DBus.Error.AccessDenied", "Only BlueZ may call this agent")
            return
        args = parameters.unpack()
        if method in ("Cancel", "Release"):
            self.clear_request()
            invocation.return_value(None)
            if method == "Release":
                self.registered = False
                self.quit_loop()
            return
        if not self.device or args[0] != self.device or self.pending:
            invocation.return_dbus_error("org.bluez.Error.Rejected", "No matching pairing request")
            return
        kinds = {
            "RequestPinCode": "pin", "RequestPasskey": "passkey",
            "RequestConfirmation": "confirmation", "RequestAuthorization": "authorization",
            "AuthorizeService": "service", "DisplayPinCode": "display-pin",
            "DisplayPasskey": "display-passkey",
        }
        kind = kinds[method]
        self.request_id += 1
        event = {"event": "prompt", "kind": kind, "id": self.request_id}
        if method == "DisplayPinCode":
            event["code"] = args[1]
        elif method in ("DisplayPasskey", "RequestConfirmation"):
            event["code"] = f"{args[1]:06d}"
            if method == "DisplayPasskey":
                event["entered"] = args[2]
        elif method == "AuthorizeService":
            event["service"] = args[1]
        if method.startswith("Display"):
            invocation.return_value(None)
        else:
            self.pending = (self.request_id, kind, invocation)
        self.emit(event)

    def command(self, doc):
        if not isinstance(doc, dict):
            self.invalid()
            return
        action = doc.get("action")
        if action == "pair":
            path = doc.get("device")
            if self.device:
                self.invalid()
                return
            if not isinstance(path, str) or not DEVICE.fullmatch(path):
                self.complete(False, "That device is no longer available. Search again.")
                return
            self.device = path
            self.generation += 1
            self.cancel_requested = False
            self.cancellable = Gio.Cancellable()
            self.emit({"event": "pairing"})
            # Pair uses this connection's agent; no global default-agent change.
            self.connection.call(
                self.owner, path, "org.bluez.Device1", "Pair", None, None,
                Gio.DBusCallFlags.NONE, 90000, self.cancellable,
                self.paired, self.generation,
            )
        elif action == "respond":
            self.respond(doc)
        elif action == "cancel":
            self.cancel()
        else:
            self.invalid()

    def invalid(self):
        self.emit({"event": "error", "message": "The pairing request is not valid. Try again."})

    def respond(self, doc):
        if not self.pending or type(doc.get("id")) is not int or doc["id"] != self.pending[0]:
            self.emit({"event": "error", "message": "That pairing request has expired."})
            return
        _, kind, invocation = self.pending
        if doc.get("accept") is not True:
            invocation.return_dbus_error("org.bluez.Error.Rejected", "Pairing rejected by user")
        elif kind in ("pin", "passkey"):
            value = doc.get("value")
            if not isinstance(value, str):
                self.invalid()
                return
            if kind == "pin":
                if not 1 <= len(value) <= 16 or not value.isascii() or not value.isprintable():
                    self.emit({"event": "error", "message": "Use the 1–16 character PIN supplied by the device."})
                    return
                invocation.return_value(GLib.Variant("(s)", (value,)))
            else:
                if not re.fullmatch(r"[0-9]{1,6}", value):
                    self.emit({"event": "error", "message": "The passkey must contain up to six digits."})
                    return
                invocation.return_value(GLib.Variant("(u)", (int(value),)))
        else:
            invocation.return_value(None)
        self.pending = None
        self.emit({"event": "clear"})

    def paired(self, connection, result, generation):
        error = None
        try:
            connection.call_finish(result)
        except GLib.Error as exc:
            error = exc
        if self.closing or generation != self.generation:
            return
        remote = Gio.DBusError.get_remote_error(error) if error else None
        if error and remote != "org.bluez.Error.AlreadyExists":
            messages = {
                "org.bluez.Error.AuthenticationCanceled": "Pairing canceled.",
                "org.bluez.Error.AuthenticationRejected": "The device rejected pairing.",
                "org.bluez.Error.AuthenticationTimeout": "The device did not respond in time.",
            }
            message = "Pairing canceled." if self.cancel_requested else messages.get(
                remote, "Pairing failed. Put the device in pairing mode and try again.")
            self.complete(False, message)
            return
        self.clear_request()
        # The UI explicitly offers "Pair and trust" for automatic reconnect.
        self.connection.call(
            self.owner, self.device, "org.freedesktop.DBus.Properties", "Set",
            GLib.Variant("(ssv)", ("org.bluez.Device1", "Trusted", GLib.Variant("b", True))),
            None, Gio.DBusCallFlags.NONE, 5000, None, self.trusted, generation,
        )

    def trusted(self, connection, result, generation):
        trusted = True
        try:
            connection.call_finish(result)
        except GLib.Error:
            trusted = False
        if not self.closing and generation == self.generation:
            self.complete(True, "Paired and trusted." if trusted else "Paired, but automatic reconnect could not be enabled.")

    def complete(self, ok, message):
        self.clear_request()
        self.device = ""
        self.cancellable = None
        self.emit({"event": "result", "ok": ok, "message": message})

    def cancel(self):
        self.clear_request()
        self.cancel_requested = True
        if self.device:
            self.connection.call(
                self.owner, self.device, "org.bluez.Device1", "CancelPairing", None,
                None, Gio.DBusCallFlags.NONE, 3000, None, None, None,
            )
            if self.cancellable:
                self.cancellable.cancel()

    def close(self):
        self.closing = True
        self.cancel()
        if self.registered:
            try:
                self.connection.call_sync(
                    self.owner, "/org/bluez", "org.bluez.AgentManager1", "UnregisterAgent",
                    GLib.Variant("(o)", (AGENT_PATH,)), None, Gio.DBusCallFlags.NONE, 1000, None,
                )
            except GLib.Error:
                pass  # BlueZ may already have released the agent or gone away.
        if self.watch_id:
            self.connection.signal_unsubscribe(self.watch_id)
        if self.object_id:
            self.connection.unregister_object(self.object_id)


def main():
    loop = GLib.MainLoop()

    def emit(doc):
        try:
            print(json.dumps(doc), flush=True)
        except BrokenPipeError:
            loop.quit()

    agent = None
    try:
        connection = Gio.bus_get_sync(Gio.BusType.SYSTEM, None)
        agent = PairAgent(connection, emit, loop.quit)
        agent.start()
    except GLib.Error:
        emit({"event": "error", "message": "Bluetooth pairing is unavailable. Reopen the panel to retry."})
        if agent:
            agent.close()
        return 1

    os.set_blocking(sys.stdin.fileno(), False)
    buffer = bytearray()

    def read_input(fd, condition):
        try:
            chunk = os.read(fd, 4096)
        except BlockingIOError:
            return GLib.SOURCE_CONTINUE
        if not chunk:
            loop.quit()
            return GLib.SOURCE_REMOVE
        buffer.extend(chunk)
        if len(buffer) > 8192:
            buffer.clear()
            agent.invalid()
        while b"\n" in buffer:
            line, _, rest = buffer.partition(b"\n")
            buffer[:] = rest
            try:
                agent.command(json.loads(line))
            except (ValueError, RecursionError):
                agent.invalid()
        return GLib.SOURCE_CONTINUE

    GLib.io_add_watch(sys.stdin.fileno(), GLib.IOCondition.IN | GLib.IOCondition.HUP, read_input)

    def stop_signal():
        loop.quit()
        return GLib.SOURCE_REMOVE

    for sig in (signal.SIGTERM, signal.SIGINT):
        GLib.unix_signal_add(GLib.PRIORITY_DEFAULT, sig, stop_signal)
    try:
        loop.run()
    finally:
        agent.close()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
