#!/usr/bin/env bash
# Real battery widget/panel and persistent Config; only hardware is faked.
set -euo pipefail
root=$(git rev-parse --show-toplevel)
for tool in quickshell python3; do
  if ! command -v "$tool" >/dev/null; then
    [[ -z ${CI:-} ]] || { echo "battery-panel-test: $tool missing" >&2; exit 1; }
    echo "battery-panel-test: $tool missing, skipped"
    exit 0
  fi
done
artifacts=""
if [[ -n ${1:-} ]]; then mkdir -p -- "$1"; artifacts=$(realpath "$1"); fi
work=$(mktemp -d)
trap 'rm -rf -- "$work"' EXIT
shell="$work/shell"
mkdir -p "$shell/widgets" "$shell/Commons" "$shell/Ui" "$shell/services" "$work/imports/TestPower" "$work/run" "$work/home/.config/subcult/shell" "$work/etc/shell" "$work/system/default/shell"
chmod 700 "$work/run"
cp -r "$root/shell/widgets/battery" "$root/shell/widgets/dell-power" "$shell/widgets/"
for qml in Widget Panel; do
  sed -i 's/^import Quickshell.Services.UPower$/import TestPower/' "$shell/widgets/battery/$qml.qml"
done
cp "$root/shell/Ui/"{BarWidget,PanelBase,IconButton,Tooltip}.qml "$shell/Ui/"
printf 'module qs.Ui\nBarWidget 1.0 BarWidget.qml\nPanelBase 1.0 PanelBase.qml\nIconButton 1.0 IconButton.qml\nTooltip 1.0 Tooltip.qml\n' >"$shell/Ui/qmldir"
cp "$root/shell/Commons/"{Config.qml,ConfigModel.js,WatchedFile.qml,Glyphs.js} "$shell/Commons/"
printf 'module qs.Commons\nsingleton Config 1.0 Config.qml\nsingleton Theme 1.0 Theme.qml\nsingleton Style 1.0 Style.qml\nWatchedFile 1.0 WatchedFile.qml\n' >"$shell/Commons/qmldir"
cat >"$shell/Commons/Theme.qml" <<'QML'
pragma Singleton
import QtQuick
QtObject {
 property color base: "#100b19"; property color surface: "#1f1830"
 property color text: "#f0ece4"; property color subtext: "#9a92a8"
 property color muted: "#786c8b"; property color accent: "#8b5cf6"
 property color selection: "#3b2470"; property color error: "#d52032"
 property color warning: "#ffb000"; property color mantle: "#191226"
 property color border: "#8f4bc8"
}
QML
cat >"$shell/Commons/Style.qml" <<'QML'
pragma Singleton
import QtQuick
QtObject {
 property string uiFontFamily: "DejaVu Sans"; property string fontFamily: "IosevkaTerm Nerd Font Mono"
 property int fontSize: 14; property int iconSize: 15; property int padding: 12
 property int barHeight: 28; property int spacing: 8
}
QML
printf 'module TestPower\nsingleton UPower 1.0 UPower.qml\nsingleton PowerProfiles 1.0 PowerProfiles.qml\nsingleton PowerProfile 1.0 PowerProfile.qml\nsingleton UPowerDeviceState 1.0 UPowerDeviceState.qml\nsingleton PerformanceDegradationReason 1.0 PerformanceDegradationReason.qml\n' >"$work/imports/TestPower/qmldir"
cat >"$work/imports/TestPower/UPower.qml" <<'QML'
pragma Singleton
import QtQuick
QtObject { property var displayDevice: ({isPresent:true, isLaptopBattery:true, percentage:0.73, state:2, timeToEmpty:9000, timeToFull:0, changeRate:9.5, healthPercentage:94}) }
QML
cat >"$work/imports/TestPower/PowerProfiles.qml" <<'QML'
pragma Singleton
import QtQuick
QtObject { property int profile: 1; property bool hasPerformanceProfile: true; property int degradationReason: 0 }
QML
for item in 'PowerProfile:PowerSaver, Balanced, Performance' 'UPowerDeviceState:Unknown, Charging, Discharging' 'PerformanceDegradationReason:None'; do
  name=${item%%:*}
  printf 'pragma Singleton\nimport QtQuick\nQtObject { enum Values { %s } }\n' "${item#*:}" >"$work/imports/TestPower/$name.qml"
done
printf 'module qs.services\nsingleton DellPower 1.0 DellPower.qml\n' >"$shell/services/qmldir"
cat >"$shell/services/DellPower.qml" <<'QML'
pragma Singleton
import QtQuick
QtObject {
 property bool busy: false
 property string error: ""
 property var lastCharging: []
 property var report: ({available:true, profiles:[{id:"quiet",active:true},{id:"cool",active:false},{id:"balanced",active:false},{id:"performance",active:false}], charging:{available:true,modes:[{id:"adaptive",active:false},{id:"standard",active:false},{id:"custom",active:true}], custom:{start:60,stop:80,startMin:50,startMax:95,stopMin:55,stopMax:100,step:1}}})
 function refresh() {}
 function setProfile(id) {
   const next = JSON.parse(JSON.stringify(report))
   next.profiles = next.profiles.map(p => ({id:p.id, active:p.id === id}))
   report = next
 }
 function setCharging(id, start, stop) { lastCharging = [id, start, stop] }
}
QML
cp "$root/default/shell/bar.json" "$work/system/default/shell/"
printf '{"enable":["subcult.dell-power"]}\n' >"$work/etc/shell/bar.json"
printf '{"primary":"DP-3","widgets":{"subcult.clock":{"zone":"UTC"}},"layout":{"right":["subcult.battery","subcult.dell-power"]}}\n' >"$work/home/.config/subcult/shell/bar.json"
cp "$root/tools/test/battery-panel.qml" "$shell/shell.qml"
export BATTERY_PANEL_TEST="$work" HOME="$work/home" SUBCULT_PATH="$work/system" SUBCULT_ETC="$work/etc"
export QT_QPA_PLATFORM=offscreen QT_QUICK_BACKEND=software XDG_RUNTIME_DIR="$work/run" QML_IMPORT_PATH="$work/imports"
status=0
quickshell --no-duplicate -p "$shell" >"$work/log" 2>&1 || status=$?
if [[ -n $artifacts ]]; then
  cp "$work/log" "$artifacts/panel-test.log"
  for png in "$work"/*.png; do [[ ! -f $png ]] || cp "$png" "$artifacts/"; done
fi
if ((status)) || ! grep -q 'PASS: combined battery panel' "$work/log"; then cat "$work/log"; exit 1; fi
if grep -Eq 'ReferenceError|TypeError|Unable to assign|Cannot assign|Failed to load configuration' "$work/log"; then cat "$work/log"; exit 1; fi
python3 - "$work/home/.config/subcult/shell/bar.json" <<'CHECK'
import json, sys
with open(sys.argv[1]) as stream:
    doc = json.load(stream)
assert doc["primary"] == "DP-3" and doc["widgets"]["subcult.clock"]["zone"] == "UTC", doc
assert doc["widgets"]["subcult.battery"] == {"chargeDisplay":"icon-percentage", "profileDisplay":"icon-text"}, doc
CHECK
echo 'battery-panel-test: PASS (six displays, persistence, Dell/custom controls, fallback and error states)'
