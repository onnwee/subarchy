#!/usr/bin/env bash
# Runs the Subarchy shell in a headless sway and checks it from outside.
# A copy of the shell gets a test-only probe widget (a magenta square with a
# declared timer) so the widget contract, live timers and live reload can be
# seen. Checks: no QML errors; the bar's own line and the background; the
# probe loads with its real properties and a live AC interval; a palette and
# a bar config written after start apply without a restart; outputs that
# appear and disappear gain and lose a bar; a broken bar config and a
# palette with one bad role fall back with one warning.
# Usage: tools/test/shell-headless.sh path/to/shell
set -euo pipefail

src=$(realpath "${1:?path to the shell folder}")
root=$(git rev-parse --show-toplevel)
fail() { echo "shell-headless: $*" >&2; exit 1; }

for tool in sway swaymsg quickshell grim magick python3 dbus-run-session; do
  if ! command -v "$tool" >/dev/null; then
    [[ -n ${CI:-} ]] && fail "$tool not installed"
    echo "shell-headless: $tool not installed, skipped"
    exit 0
  fi
done

work=$(mktemp -d)
pids=()
cleanup() {
  for p in "${pids[@]}"; do kill "$p" 2>/dev/null || true; done
  # Anything else this test started (the private bus daemon) carries the
  # test's own runtime folder; stop exactly those processes.
  local p
  for p in $(pgrep -u "$(id -u)" 2>/dev/null); do
    if { tr '\0' '\n' <"/proc/$p/environ"; } 2>/dev/null | grep -qxF "XDG_RUNTIME_DIR=$work/run"; then
      kill "$p" 2>/dev/null || true
    fi
  done
  wait 2>/dev/null || true
  rm -rf -- "$work"
}
trap cleanup EXIT

# The shell under test, plus the probe widget.
shell="$work/shell"
cp -r "$src" "$shell"
mkdir -p "$shell/widgets/test-probe"
cat >"$shell/widgets/test-probe/manifest.json" <<'EOF'
{"id": "subcult.test-probe", "name": "Test probe", "version": "0.0.0", "api": 0, "kind": "bar-widget",
 "cost": {"timers": [{"name": "tick", "ac": 60, "battery": 300}]}}
EOF
cat >"$shell/widgets/test-probe/Widget.qml" <<'EOF'
import QtQuick
import qs.Ui

BarWidget {
  id: root
  implicitWidth: 12
  Rectangle { anchors.centerIn: parent; width: 10; height: 10; color: "#FF00FF" }
  WidgetTimer { widget: root; timerName: "tick"; running: true; repeat: true }
  Component.onCompleted: console.info("probe: mode=" + mode + " shell=" + (shell.power ? "ok" : "missing")
    + " interval=" + (shell.power ? shell.power.interval("tick") : -1))
}
EOF
python3 "$root/tools/shell/gen-index.py" --shell "$shell"

export XDG_RUNTIME_DIR="$work/run"
mkdir -m 0700 "$XDG_RUNTIME_DIR"
export WLR_BACKENDS=headless WLR_RENDERER=pixman WLR_LIBINPUT_NO_DEVICES=1
unset WAYLAND_DISPLAY DISPLAY HYPRLAND_INSTANCE_SIGNATURE SWAYSOCK

printf 'output HEADLESS-1 resolution 1280x800\n' >"$work/sway.conf"
sway -c "$work/sway.conf" >"$work/sway.log" 2>&1 &
pids+=($!)
for _ in $(seq 50); do
  sock=$(find "$XDG_RUNTIME_DIR" -maxdepth 1 -name 'sway-ipc.*' | head -1)
  display=$(find "$XDG_RUNTIME_DIR" -maxdepth 1 -name 'wayland-*' ! -name '*.lock' | head -1)
  [[ -n $sock && -n $display ]] && break
  sleep 0.1
done
[[ -n ${sock:-} && -n ${display:-} ]] || { tail -5 "$work/sway.log" >&2; fail "headless sway did not start"; }
export SWAYSOCK=$sock WAYLAND_DISPLAY=${display##*/}

# A private session bus without service activation: the shell must not join
# the desktop's session (it would become a tray host there), and nothing
# (portals, gvfs) may start on the private one and outlive the test. The
# system bus stays real.
cat >"$work/session-bus.conf" <<EOF
<!DOCTYPE busconfig PUBLIC "-//freedesktop//DTD D-Bus Bus Configuration 1.0//EN"
 "http://www.freedesktop.org/standards/dbus/1.0/busconfig.dtd">
<busconfig>
  <type>session</type>
  <listen>unix:dir=$work</listen>
  <policy context="default">
    <allow send_destination="*" eavesdrop="true"/>
    <allow eavesdrop="true"/>
    <allow own="*"/>
  </policy>
</busconfig>
EOF

start_shell() { # home log
  HOME=$1 SUBCULT_PATH=$root QS_NO_RELOAD_POPUP=1 \
    dbus-run-session --config-file="$work/session-bus.conf" -- quickshell -p "$shell" >"$2" 2>&1 &
  pids+=($!)
  sleep 5
}

check_log() { # log
  # No PipeWire daemon, Hyprland or GPU here; those messages are the
  # environment, not the shell.
  if grep -vE 'Failed to connect pipewire context|^MESA|ZINK' "$1" |
    grep -nE 'ERROR|TypeError|ReferenceError|is not a type|is not installed|Cannot assign'; then
    fail "QML errors in the shell log"
  fi
}

shot() { # output
  grim -o "$1" "$work/shot.png"
}

# The bar's dominant colour (rows 2-21 of the last shot), not one pixel:
# widgets sit anywhere along the bar.
bar_colour() {
  magick "$work/shot.png" -crop "x20+0+2" +repage -format %c histogram:info:- | sort -rn | head -1 |
    grep -oE "#[0-9A-F]{6}" | head -1 | cut -c2-
}

pixel() { # x y (of the last shot) -> RRGGBB
  magick "$work/shot.png" -format "%[hex:p{$1,$2}]" info: | cut -c1-6
}

status() { # home
  HOME=$1 quickshell ipc -p "$shell" call subcult.shell status
}

json() { # expression over the status JSON in $st
  python3 -c "import json,sys; d=json.loads(sys.argv[1]); print($1)" "$st"
}

# 1. Defaults, with the probe on the left.
home1="$work/home1"
mkdir -p "$home1/.config/subcult/shell"
printf '{"layout": {"left": ["subcult.test-probe"]}}\n' >"$home1/.config/subcult/shell/bar.json"
start_shell "$home1" "$work/qs1.log"
check_log "$work/qs1.log"
shot HEADLESS-1
[[ $(pixel 640 25) == 1F1830 ]] || fail "no bar line at y=25 (got $(pixel 640 25))"
[[ $(bar_colour) == 100B19 ]] || fail "the bar is not base #100B19 (got $(bar_colour))"
[[ $(pixel 640 40) == 100B19 ]] || fail "the background is not base #100B19 (got $(pixel 640 40))"
magick "$work/shot.png" -crop "x24+0+0" +repage -format %c histogram:info:- | grep -q '#FF00FF' ||
  fail "the probe widget did not draw"
if [[ -n ${SHELL_HEADLESS_SHOT:-} ]]; then cp "$work/shot.png" "$SHELL_HEADLESS_SHOT"; fi
grep -q 'probe: mode=full shell=ok interval=60000' "$work/qs1.log" ||
  { tail -15 "$work/qs1.log" >&2; fail "the probe did not start with its real properties"; }
st=$(status "$home1")
[[ $(json 'd["intervals"].get("subcult.test-probe.tick")') == "{'interval': 60000, 'running': True}" ]] ||
  fail "live timer not reported: $st"

# 2. A palette written after start applies without a restart.
mkdir -p "$home1/.config/subcult/theme"
printf '{"schema": 1, "colors": {"base": "#FF0000", "surface0": "#00FF00"}}\n' >"$home1/.config/subcult/theme/palette.json"
sleep 2
shot HEADLESS-1
[[ $(bar_colour) == FF0000 && $(pixel 640 25) == 00FF00 ]] ||
  fail "a new palette was not applied live (bar $(bar_colour), line $(pixel 640 25))"

# 3. A bar config changed after start applies without a restart.
printf '{"layout": {"left": []}}\n' >"$home1/.config/subcult/shell/bar.json"
sleep 2
st=$(status "$home1")
[[ $(json '"subcult.test-probe" in d["loaded"]["HEADLESS-1"]') == False ]] ||
  fail "a changed bar config was not applied live: $st"

# 4. Outputs that appear and disappear gain and lose a bar.
swaymsg -q create_output
sleep 3
st=$(status "$home1")
[[ $(json 'len(d["bars"])') == 2 ]] || fail "after adding an output: $st"
shot HEADLESS-2
[[ $(pixel 640 25) == 00FF00 ]] || fail "the new output has no bar"
swaymsg -q output HEADLESS-2 unplug
sleep 2
st=$(status "$home1")
[[ $(json 'len(d["bars"])') == 1 ]] || fail "after unplugging an output: $st"
check_log "$work/qs1.log"
# Stopping dbus-run-session leaves its child running; stop the shell itself.
HOME=$home1 quickshell kill -p "$shell" >/dev/null 2>&1 || fail "could not stop the first shell"
sleep 1

# 5. A broken bar config and a palette with one bad role.
home2="$work/home2"
mkdir -p "$home2/.config/subcult/theme" "$home2/.config/subcult/shell"
printf '{"schema": 1, "colors": {"base": "red", "surface0": "#00FF00"}}\n' >"$home2/.config/subcult/theme/palette.json"
printf '{ "layout": ' >"$home2/.config/subcult/shell/bar.json"
start_shell "$home2" "$work/qs2.log"
check_log "$work/qs2.log"
shot HEADLESS-1
[[ $(bar_colour) == 100B19 ]] || fail "a bad base role was not replaced by the system colour (got $(bar_colour))"
[[ $(pixel 640 25) == 00FF00 ]] || fail "a good role next to a bad one was not applied (got $(pixel 640 25))"
warnings=$(grep -c 'subcult shell config' "$work/qs2.log" || true)
[[ $warnings == 1 ]] || fail "want exactly one config warning, got $warnings"

echo "shell-headless: ok"
