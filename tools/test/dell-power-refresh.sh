#!/usr/bin/env bash
# Exercise the real DellPower service with a fake PowerProfiles singleton.
# No system bus, firmware writes or running desktop shell are used.
set -euo pipefail
root=$(git rev-parse --show-toplevel)
service=${1:-"$root/shell/services/DellPower.qml"}
if ! command -v quickshell >/dev/null; then
  [[ -z ${CI:-} ]] || { echo 'dell-power-refresh: quickshell missing' >&2; exit 1; }
  echo 'dell-power-refresh: quickshell missing, skipped'
  exit 0
fi
work=$(mktemp -d)
trap 'rm -rf -- "$work"' EXIT
mkdir -p "$work/services" "$work/widgets/dell-power" "$work/imports/TestPower" "$work/bin"
# Quickshell preloads its own UPower module. Substitute only that import in
# the private service copy; all refresh and signal-handling code is real.
sed 's/^import Quickshell.Services.UPower$/import TestPower/' \
  "$service" >"$work/services/DellPower.qml"
cp "$root/shell/widgets/dell-power/Model.js" "$work/widgets/dell-power/"
printf 'singleton DellPower 1.0 DellPower.qml\n' >"$work/services/qmldir"
printf 'module TestPower\nsingleton PowerProfiles 1.0 PowerProfiles.qml\n' >"$work/imports/TestPower/qmldir"
printf 'pragma Singleton\nimport QtQuick\nQtObject { property int profile: 0 }\n' >"$work/imports/TestPower/PowerProfiles.qml"
echo balanced >"$work/profile"
cat >"$work/bin/subcult" <<'STUB'
#!/usr/bin/env bash
set -euo pipefail
[[ $* == 'dell power state --json' ]]
read -r value <"$DELL_TEST/profile"
echo query >>"$DELL_TEST/queries"
sleep 0.5
printf '{"available":true,"profiles":[{"id":"%s","active":true}]}\n' "$value"
STUB
chmod +x "$work/bin/subcult"
cat >"$work/shell.qml" <<'QML'
import QtQuick
import Quickshell
import Quickshell.Io
import TestPower
import "services"
ShellRoot {
  id: test
  property int phase: 0
  Component.onCompleted: DellPower.refresh()
  Timer {
    interval: 150; running: true
    onTriggered: change.running = true
  }
  Process {
    id: change
    command: ["sh", "-c", "echo quiet > \"$DELL_TEST/profile\""]
    onExited: PowerProfiles.profile = 1
  }
  Process {
    id: changeAgain
    command: ["sh", "-c", "echo balanced > \"$DELL_TEST/profile\""]
    onExited: PowerProfiles.profile = 2
  }
  Timer {
    interval: 50; running: true; repeat: true
    onTriggered: {
      const report = DellPower.report
      const active = report && report.profiles ? report.profiles.find(p => p.active) : null
      if (test.phase === 0 && active && active.id === "quiet") {
        test.phase = 1
        changeAgain.running = true
      } else if (test.phase === 1 && active && active.id === "balanced") {
        console.log("PASS: external profile changes refresh, including an in-flight query")
        Qt.quit()
      }
    }
  }
  Timer {
    interval: 6000; running: true
    onTriggered: { console.error("FAIL: Dell power state stayed stale"); Qt.exit(1) }
  }
}
QML
export DELL_TEST="$work" PATH="$work/bin:$PATH" QT_QPA_PLATFORM=offscreen
export QML_IMPORT_PATH="$work/imports${QML_IMPORT_PATH:+:$QML_IMPORT_PATH}"
quickshell --no-duplicate -p "$work/shell.qml" >"$work/log" 2>&1 || { cat "$work/log"; exit 1; }
grep -q 'PASS: external profile' "$work/log" || { cat "$work/log"; exit 1; }
[[ $(wc -l <"$work/queries") == 3 ]] || { cat "$work/log"; echo 'unexpected query count' >&2; exit 1; }
echo 'dell-power-refresh: PASS (3 event-driven queries)'
