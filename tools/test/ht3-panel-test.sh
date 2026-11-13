#!/usr/bin/env bash
# Run the real HT3 panel and helper controller with a fake Bluetooth adapter
# and a stub `subcult ht3 watch`: the helper starts with the panel, its
# readings show, it stops when the panel closes, and nothing starts without
# a connected HT3. The readings from real headphones are the owner's check.
set -euo pipefail
root=$(git rev-parse --show-toplevel)
artifacts=""
if [[ -n ${1:-} ]]; then
  mkdir -p -- "$1"
  artifacts=$(realpath "$1")
fi
for tool in quickshell python3; do
  if ! command -v "$tool" >/dev/null; then
    [[ -z ${CI:-} ]] || { echo "ht3-panel-test: $tool missing" >&2; exit 1; }
    echo "ht3-panel-test: $tool missing, skipped"
    exit 0
  fi
done
work=$(mktemp -d)
trap 'rm -rf -- "$work"' EXIT
shell="$work/shell"
mkdir -p "$shell/widgets/ht3" "$shell/Commons" "$shell/Ui" "$shell/services" "$work/imports/TestBluetooth" "$work/run" "$work/bin"
chmod 700 "$work/run"
: >"$work/started"
: >"$work/stopped"
cp "$root/shell/widgets/ht3/Model.js" "$shell/widgets/ht3/"
sed 's/^import Quickshell.Bluetooth$/import TestBluetooth/' "$root/shell/widgets/ht3/Panel.qml" >"$shell/widgets/ht3/Panel.qml"
cp "$root/shell/services/Ht3.qml" "$shell/services/"
printf 'module qs.services\nsingleton Ht3 1.0 Ht3.qml\n' >"$shell/services/qmldir"
cp "$root/shell/Ui/PanelBase.qml" "$shell/Ui/"
cp "$root/shell/Commons/Glyphs.js" "$shell/Commons/"
printf 'module qs.Commons\nsingleton Theme 1.0 Theme.qml\nsingleton Style 1.0 Style.qml\n' >"$shell/Commons/qmldir"
printf 'module qs.Ui\nPanelBase 1.0 PanelBase.qml\n' >"$shell/Ui/qmldir"
cat >"$shell/Commons/Theme.qml" <<'QML'
pragma Singleton
import QtQuick
QtObject {
 property color surface: "#1f1830"
 property color text: "#f0ece4"
 property color subtext: "#9a92a8"
 property color accent: "#8b5cf6"
 property color warning: "#f6d447"
}
QML
cat >"$shell/Commons/Style.qml" <<'QML'
pragma Singleton
import QtQuick
QtObject { property string uiFontFamily: "monospace"; property string fontFamily: "monospace"; property int fontSize: 14; property int iconSize: 16 }
QML
printf 'module TestBluetooth\nsingleton Bluetooth 1.0 Bluetooth.qml\n' >"$work/imports/TestBluetooth/qmldir"
cat >"$work/imports/TestBluetooth/Bluetooth.qml" <<'QML'
pragma Singleton
import QtQuick
QtObject {
 id: bt
 property QtObject device: QtObject {
  property string name: "TOZO HT3"
  property string address: "AA:BB:CC:DD:EE:FF"
  property bool connected: true
  property bool batteryAvailable: false
 }
 property var defaultAdapter: QtObject {
  property bool enabled: true
  property var devices: QtObject { property var values: [bt.device] }
 }
}
QML
# The stub helper: odd runs answer with PROTOCOL.md's captured readings
# (89 %, transparency) and wait to be stopped; the second reads the battery,
# then fails as when the phone app holds the control channel.
cat >"$work/bin/subcult" <<'PY'
#!/usr/bin/python3
import json
import os
from pathlib import Path
import signal
import sys

work = Path(os.environ["HT3_PANEL_TEST"])

def emit(doc):
    print(json.dumps(doc), flush=True)

def stop(*_):
    with (work / "stopped").open("a") as stream:
        stream.write(str(os.getpid()) + "\n")
    raise SystemExit(0)

signal.signal(signal.SIGTERM, stop)
with (work / "started").open("a") as stream:
    stream.write(str(os.getpid()) + "\n")
if sys.argv[1:] != ["ht3", "watch", "AA:BB:CC:DD:EE:FF"]:
    emit({"event": "error", "message": "unexpected arguments: " + " ".join(sys.argv[1:])})
    raise SystemExit(2)
runs = len((work / "started").read_text().split())
if runs % 2 == 1:
    emit({"event": "connected"})
    emit({"event": "state", "battery": 89})
    emit({"event": "state", "battery": 89, "mode": "transparency"})
    while True:
        signal.pause()
emit({"event": "connected"})
emit({"event": "state", "battery": 89})
emit({"event": "error", "message": "The headphones refused the control channel. If the TOZO app is open on a phone, close it, then open the panel again."})
raise SystemExit(1)
PY
chmod +x "$work/bin/subcult"
cp "$root/tools/test/ht3-panel.qml" "$shell/shell.qml"
export HT3_PANEL_TEST="$work" QT_QPA_PLATFORM=offscreen QT_QUICK_BACKEND=software XDG_RUNTIME_DIR="$work/run"
export PATH="$work/bin:$PATH" QML_IMPORT_PATH="$work/imports${QML_IMPORT_PATH:+:$QML_IMPORT_PATH}"
status=0
quickshell --no-duplicate -p "$shell" >"$work/log" 2>&1 || status=$?
if [[ -n $artifacts ]]; then
  cp "$work/log" "$artifacts/panel-test.log"
  for png in "$work"/*.png; do [[ ! -f $png ]] || cp "$png" "$artifacts/"; done
fi
if ((status)); then cat "$work/log"; exit "$status"; fi
grep -q 'PASS: HT3 panel' "$work/log" || { cat "$work/log"; exit 1; }
# Runs 1 and 3 read and wait; both must have been stopped by the panel.
[[ $(wc -l <"$work/started") -eq 3 && "$(sed -n '1p;3p' "$work/started")" == "$(cat "$work/stopped")" ]] || {
  cat "$work/log"; echo 'ht3-panel-test: the helper did not stop with the panel' >&2; exit 1;
}
while read -r pid; do
  if kill -0 "$pid" 2>/dev/null; then echo "ht3-panel-test: helper $pid still running" >&2; exit 1; fi
done <"$work/started"
if grep -Eq 'ReferenceError|TypeError|Unable to assign|Cannot assign|Failed to load configuration' "$work/log"; then cat "$work/log"; exit 1; fi
echo 'ht3-panel-test: PASS (helper starts with the panel, readings shown, error clears them, restarts on reconnect, stops on close, none without an HT3)'
