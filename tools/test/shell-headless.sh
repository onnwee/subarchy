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

for tool in sway swaymsg quickshell grim magick python3 dbus-run-session gdbus; do
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

# A stand-in for `subcult commands --json` on the shell's PATH: two
# commands, one marked dangerous.
mkdir -p "$work/bin"
cat >"$work/bin/subcult" <<'STUB'
#!/bin/sh
[ "$1 $2" = "commands --json" ] || exit 2
cat <<'JSON'
{"ok": true, "commands": [
  {"route": "subcult font set", "group": "font", "summary": "Use a font", "args": "<family>", "dangerous": false},
  {"route": "subcult app remove", "group": "app", "summary": "Remove apps", "args": "<id>...", "dangerous": true}]}
JSON
STUB
chmod +x "$work/bin/subcult"
export PATH="$work/bin:$PATH"
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
  <listen>unix:path=$work/bus</listen>
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
  # No PipeWire daemon, NetworkManager, Hyprland or GPU may be here; those
  # messages are the environment, not the shell.
  if grep -vE 'Failed to (connect|create) pipewire context|Network will not work. Could not find an available backend|^MESA|ZINK' "$1" |
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

# A notification reaches the shell's daemon and pops up.
DBUS_SESSION_BUS_ADDRESS=unix:path=$work/bus gdbus call --session --dest org.freedesktop.Notifications \
  --object-path /org/freedesktop/Notifications --method org.freedesktop.Notifications.Notify \
  "subarchy-test" 0 "" "Subarchy test" "hello" "[]" "{}" 5000 >/dev/null ||
  fail "notify-send could not reach the shell's notification daemon"
sleep 1
st=$(status "$home1")
[[ $(json 'd.get("popups")') == 1 && $(json 'd.get("unread")') == 1 ]] || fail "no popup for a notification: $st"
sleep 6
st=$(status "$home1")
[[ $(json 'd.get("popups")') == 0 && $(json 'd.get("unread")') == 1 ]] ||
  fail "the popup did not go after five seconds, or its record was lost: $st"

# Without UPower (CI) there is no battery: the battery widget is not shown.
if [[ -n ${CI:-} ]]; then
  [[ $(json '"subcult.battery" in d["shown"]["HEADLESS-1"]') == False && $(json 'd["onBattery"]') == False ]] ||
    fail "a machine without a battery shows one: $st"
fi

# The OSD answers its IPC call (media keys use it; capslock needs no
# backlight or brightnessctl, which CI lacks).
HOME=$home1 quickshell ipc -p "$shell" call subcult.osd flash capslock >/dev/null 2>&1 ||
  fail "the OSD has no IPC handler"
st=$(status "$home1")
[[ $(json 'd.get("osd")') == capslock ]] || fail "the OSD did not show: $st"

# Alt-Tab answers its IPC calls (no windows here, so nothing to show).
for call in next prev cancel; do
  HOME=$home1 quickshell ipc -p "$shell" call subcult.altswitch "$call" >/dev/null 2>&1 ||
    fail "Alt-Tab IPC call $call failed"
done

# The launcher: a desktop entry written after start is found without a
# restart (the shell creates the user's applications folder, which did not
# exist, so it can be watched), and the user's favorites make the home
# screen. It opens and closes.
launcher() { HOME=$home1 quickshell ipc -p "$shell" call subcult.launcher "$@"; }
mkdir -p "$home1/.local/share/applications" "$home1/.config/subcult/launcher"
printf '[Desktop Entry]\nType=Application\nName=Subarchy Test App\nExec=true\n' \
  >"$home1/.local/share/applications/subarchy-test-app.desktop"
printf '{"favorites": ["subarchy-test-app"]}\n' >"$home1/.config/subcult/launcher/favorites.json"
sleep 2
[[ $(launcher search "test app") == '["subarchy-test-app"]' ]] ||
  fail "the launcher did not find a new desktop entry: $(launcher search "test app")"
[[ $(launcher search "") == '["subarchy-test-app"]' ]] ||
  fail "the launcher home screen is not the user's favorites: $(launcher search "")"
launcher open >/dev/null
st=$(status "$home1")
[[ $(json 'd.get("launcher")') == True ]] || fail "the launcher did not open: $st"
if [[ -n ${SHELL_HEADLESS_LAUNCHER_SHOT:-} ]]; then shot HEADLESS-1; cp "$work/shot.png" "$SHELL_HEADLESS_LAUNCHER_SHOT"; fi
launcher close >/dev/null
st=$(status "$home1")
[[ $(json 'd.get("launcher")') == False ]] || fail "the launcher did not close: $st"

# Commands, the calculator and web search, through the launcher's state.
lstate() { # query -> the launcher's state after typing it
  launcher type "$1" >/dev/null
  sleep 1
  launcher state
}
row() { # python expression over the rows of the state in $ls
  python3 -c "import json,sys; r=json.loads(sys.argv[1])['rows']; print($1)" "$ls"
}
ls=$(lstate "remove")
[[ $(row '[x["id"] for x in r if x["kind"] == "command"]') == "['subcult app remove']" ]] ||
  fail "subcult commands are not searched: $ls"
ls=$(lstate "font set Iosevka")
[[ $(row '(r[0]["kind"], r[0]["name"])') == "('command', 'font set Iosevka')" ]] ||
  fail "a command with arguments is not offered first: $ls"
ls=$(lstate "app remove")
launcher enter >/dev/null
ls=$(launcher state)
[[ $(python3 -c "import json,sys; print(json.loads(sys.argv[1])['pending'])" "$ls") == "subcult app remove" ]] ||
  fail "a dangerous command did not ask for confirmation: $ls"
ls=$(lstate "zzqx nothing here")
[[ $(row '[(x["kind"], x["url"]) for x in r]') == "[('web', 'https://duckduckgo.com/?q=zzqx%20nothing%20here')]" ]] ||
  fail "no match does not fall back to web search: $ls"
ls=$(lstate "@yt cats")
[[ $(row 'r[0]["url"]') == "https://www.youtube.com/results?search_query=cats" ]] || fail "@yt is not a quicklink: $ls"
ls=$(lstate "gh subarchy")
[[ $(row 'r[0]["url"]') == "https://github.com/search?q=subarchy" ]] || fail "a quicklink keyword in root search: $ls"
if command -v qalc >/dev/null; then
  ls=$(lstate "=2+2*3")
  [[ $(row '[(x["kind"], x["name"]) for x in r]') == "[('calc', '8')]" ]] || fail "= does not calculate: $ls"
  ls=$(lstate "sqrt(16)")
  [[ $(row '(r[0]["kind"], r[0]["name"])') == "('calc', '4')" ]] || fail "inline math has no answer: $ls"
else
  [[ -z ${CI:-} ]] || fail "qalc not installed"
  echo "shell-headless: qalc not installed, calculator not checked"
fi
launcher close >/dev/null

# Script commands with Raycast headers, aliases and snippets. The script
# runs silently and writes its argument where the test can read it.
lfield() { # field of the launcher's state
  python3 -c "import json,sys; print(json.loads(sys.argv[1])[sys.argv[2]])" "$(launcher state)" "$1"
}
mkdir -p "$home1/.config/subcult/commands"
cat >"$home1/.config/subcult/commands/greet.sh" <<'SCRIPT'
#!/bin/sh
# @raycast.schemaVersion 1
# @raycast.title Greet someone
# @raycast.mode silent
# @raycast.argument1 { "type": "text", "placeholder": "Name" }
printf '%s\n' "$1" >"$HOME/greet-out"
SCRIPT
chmod +x "$home1/.config/subcult/commands/greet.sh"
printf '{"aliases": {"hi": "script:greet.sh", "fs": "subcult font set"}}\n' >"$home1/.config/subcult/launcher/aliases.json"
printf '{"snippets": [{"name": "Sign-off", "keyword": "sig", "text": "Best, {date}"}]}\n' >"$home1/.config/subcult/launcher/snippets.json"
sleep 1
ls=$(lstate "greet")
[[ $(row '(r[0]["kind"], r[0]["id"])') == "('script', 'script:greet.sh')" ]] || fail "a Raycast script is not a command: $ls"
launcher enter >/dev/null
[[ $(lfield argument) == 1 ]] || fail "the script did not ask for its argument: $(launcher state)"
launcher type "world" >/dev/null
launcher enter >/dev/null
sleep 1
[[ $(cat "$home1/greet-out" 2>/dev/null) == world ]] || fail "the script did not run with its argument"
ls=$(lstate "hi there friend")
[[ $(row 'r[0]["id"]') == "script:greet.sh" ]] || fail "an alias does not lead: $ls"
launcher enter >/dev/null
sleep 1
[[ $(cat "$home1/greet-out" 2>/dev/null) == "there friend" ]] || fail "an alias did not pass its arguments"
launcher close >/dev/null
[[ $(lfield aliases) == "['hi', 'fs']" ]] || fail "the aliases are not registered: $(launcher state)"
launcher hotkey hi >/dev/null
[[ $(lfield argument) == 1 ]] || fail "an alias hotkey for a script with an argument did not ask for it: $(launcher state)"
launcher close >/dev/null
ls=$(lstate "sig")
[[ $(row '(r[0]["kind"], r[0]["name"])') == "('snippet', 'Sign-off')" ]] || fail "snippets are not searched: $ls"
launcher close >/dev/null

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
