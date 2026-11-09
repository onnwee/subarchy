#!/usr/bin/env bash
# Run the real panel/controller with a fake adapter and private helper pipe.
set -euo pipefail
root=$(git rev-parse --show-toplevel)
artifacts=""
if [[ -n ${1:-} ]]; then
  mkdir -p -- "$1"
  artifacts=$(realpath "$1")
fi
for tool in quickshell python3; do
  if ! command -v "$tool" >/dev/null; then
    [[ -z ${CI:-} ]] || { echo "bluetooth-panel-test: $tool missing" >&2; exit 1; }
    echo "bluetooth-panel-test: $tool missing, skipped"
    exit 0
  fi
done
work=$(mktemp -d)
trap 'rm -rf -- "$work"' EXIT
shell="$work/shell"
mkdir -p "$shell/widgets/bluetooth" "$shell/Commons" "$shell/Ui" "$shell/services" "$work/imports/TestBluetooth" "$work/run"
chmod 700 "$work/run"
: >"$work/started"
: >"$work/stopped"
cp "$root/shell/widgets/bluetooth/Model.js" "$shell/widgets/bluetooth/"
sed 's/^import Quickshell.Bluetooth$/import TestBluetooth/' "$root/shell/widgets/bluetooth/Panel.qml" >"$shell/widgets/bluetooth/Panel.qml"
sed 's/^import Quickshell.Bluetooth$/import TestBluetooth/' "$root/shell/services/BluetoothPairing.qml" >"$shell/services/BluetoothPairing.qml"
sed -i "s|/usr/lib/subcult/bluetooth-pair-agent|$work/mock-agent|" "$shell/services/BluetoothPairing.qml"
printf 'module qs.services\nsingleton BluetoothPairing 1.0 BluetoothPairing.qml\n' >"$shell/services/qmldir"
cp "$root/shell/Ui/PanelBase.qml" "$shell/Ui/"
cp "$root/shell/Commons/Glyphs.js" "$shell/Commons/"
printf 'module qs.Commons\nsingleton Theme 1.0 Theme.qml\nsingleton Style 1.0 Style.qml\n' >"$shell/Commons/qmldir"
printf 'module qs.Ui\nPanelBase 1.0 PanelBase.qml\nIconButton 1.0 IconButton.qml\n' >"$shell/Ui/qmldir"
cat >"$shell/Commons/Theme.qml" <<'QML'
pragma Singleton
import QtQuick
QtObject {
 property color base: "#100b19"
 property color surface: "#1f1830"
 property color text: "#f0ece4"
 property color subtext: "#9a92a8"
 property color muted: "#5e5570"
 property color accent: "#8b5cf6"
 property color selection: "#3b2470"
}
QML
cat >"$shell/Commons/Style.qml" <<'QML'
pragma Singleton
import QtQuick
QtObject { property string uiFontFamily: "monospace"; property string fontFamily: "monospace"; property int fontSize: 14 }
QML
cat >"$shell/Ui/IconButton.qml" <<'QML'
import QtQuick
Item { property string glyph: ""; property color color: "white"; property string tooltip: ""; signal clicked(var mouse) }
QML
printf 'module TestBluetooth\nsingleton Bluetooth 1.0 Bluetooth.qml\n' >"$work/imports/TestBluetooth/qmldir"
cat >"$work/imports/TestBluetooth/Bluetooth.qml" <<'QML'
pragma Singleton
import QtQuick
QtObject {
 id: bt
 property var device: ({name: "Fixture headphones", dbusPath: "/org/bluez/hci0/dev_AA_BB_CC_DD_EE_FF", paired: false, bonded: false, connected: false})
 property var defaultAdapter: QtObject {
  property bool enabled: true
  property bool discovering: false
  property var devices: QtObject { property var values: [bt.device] }
 }
}
QML
cat >"$work/mock-agent" <<'PY'
#!/usr/bin/python3
import json
import os
from pathlib import Path
import signal
import sys

def emit(doc):
    print(json.dumps(doc), flush=True)

def stop(*_):
    with Path(os.environ["BT_PANEL_TEST"], "stopped").open("a") as stream:
        stream.write(str(os.getpid()) + "\n")
    raise SystemExit(0)

signal.signal(signal.SIGTERM, stop)
with Path(os.environ["BT_PANEL_TEST"], "started").open("a") as stream:
    stream.write(str(os.getpid()) + "\n")
emit({"event": "ready"})
count = 0
for line in sys.stdin:
    doc = json.loads(line)
    if doc["action"] == "pair":
        count += 1
        emit({"event": "pairing"})
        kind = {1: "confirmation", 2: "pin", 3: "authorization"}[count]
        prompt = {"event": "prompt", "kind": kind, "id": count}
        if kind == "confirmation":
            prompt["code"] = "000123"
        emit(prompt)
    elif doc["action"] == "respond":
        assert doc["id"] == count and doc["accept"] is True
        if count == 2:
            assert doc["value"] == "fixture-pin"
        emit({"event": "clear"})
        emit({"event": "result", "ok": True, "message": "Paired and trusted."})
    elif doc["action"] == "cancel":
        emit({"event": "clear"})
        emit({"event": "result", "ok": False, "message": "Pairing canceled."})
stop()
PY
chmod +x "$work/mock-agent"
cp "$root/tools/test/bluetooth-panel.qml" "$shell/shell.qml"
export BT_PANEL_TEST="$work" QT_QPA_PLATFORM=offscreen QT_QUICK_BACKEND=software XDG_RUNTIME_DIR="$work/run"
export QML_IMPORT_PATH="$work/imports${QML_IMPORT_PATH:+:$QML_IMPORT_PATH}"
status=0
quickshell --no-duplicate -p "$shell" >"$work/log" 2>&1 || status=$?
if [[ -n $artifacts ]]; then
  cp "$work/log" "$artifacts/panel-test.log"
  cp "$work/started" "$work/stopped" "$artifacts/"
  for png in "$work"/*.png; do [[ ! -f $png ]] || cp "$png" "$artifacts/"; done
fi
if ((status)); then cat "$work/log"; exit "$status"; fi
grep -q 'PASS: Bluetooth panel' "$work/log" || { cat "$work/log"; exit 1; }
[[ -s $work/started && $(sort -u "$work/started") == "$(sort -u "$work/stopped")" ]] || {
  cat "$work/log"; echo 'helper did not stop with the panel' >&2; exit 1;
}
if grep -Eq 'ReferenceError|TypeError|Unable to assign|Cannot assign|Failed to load configuration' "$work/log"; then cat "$work/log"; exit 1; fi
echo 'bluetooth-panel-test: PASS (search ownership, prompts, PIN pipe, cancel and helper cleanup)'
