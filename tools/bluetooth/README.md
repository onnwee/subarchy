# Bluetooth pairing

The bar panel uses Quickshell for adapter/device state. New pairing goes
through `pair-agent.py`, installed as
`/usr/lib/subcult/bluetooth-pair-agent`, using the existing `python-gobject`
dependency. No additional Bluetooth applet or startup service is installed.

The shared `BluetoothPairing.qml` controller starts the helper when a panel
opens with Bluetooth on. Releasing the last panel sends SIGTERM while the
QML process object stays alive for cleanup. The helper cancels any pending
request and unregisters its own agent. A process object destroyed directly
by Quickshell is force-killed, so keep the controller outside the panel.
Discovery is a separate, user-started 30-second operation; the panel stops
only the discovery request it started.

The helper registers a `KeyboardDisplay` Agent1 and calls Device1.Pair on
the same D-Bus connection. It never calls RequestDefaultAgent. Agent calls
must come from the pinned BlueZ unique bus owner and match the device the
user selected. Confirmation requests have IDs so a stale response cannot
approve a newer prompt. "Pair and trust" sets Trusted after pairing;
failure to save that setting is reported as a partial result. PIN/passkey
input is carried on the helper's private pipe and is not logged or saved.

The wire format is one JSON object per line. UI commands are `pair`
(`device` path), `respond` (`id`, boolean `accept`, optional `value`) and
`cancel`. Replies are `ready`, `pairing`, `prompt`, `clear`, `error` and
`result`. A prompt identifies its kind and ID; display/confirmation prompts
also supply the code. Do not log wire messages.

Run these checks with the distribution's Python/Gio and Quickshell:

```sh
python3 -m unittest discover -s tools/bluetooth -p 'test_*.py' -v
tools/test/bluetooth-panel-test.sh build/bluetooth-preview
```

The protocol tests run a private D-Bus daemon and fake BlueZ, exercising the
real registered Agent1 methods, replies, cancellation, sender checks and
cleanup. The native panel test substitutes only the adapter and helper
transport; it drives the real panel/controller through search, confirmation,
PIN entry, cancel and destruction, including another client's discovery.
These checks do not prove physical pairing or reconnection; record those
owner results on #75 and #217.

API references: [BlueZ Agent1](https://bluez.readthedocs.io/en/latest/agent-api/),
[Device1](https://bluez.readthedocs.io/en/latest/device-api/),
[Quickshell process lifecycle](https://github.com/quickshell-mirror/quickshell/blob/v0.3.2/src/io/process.cpp).
