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
fail() { # the message, then the shell log's last warnings when it exists
  echo "shell-headless: $*" >&2
  [[ -f ${work:-}/qs1.log ]] && grep -E 'WARN|ERROR' "$work/qs1.log" | tail -n 6 | cut -c1-300 >&2
  exit 1
}

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
# The settings panel reads the font roles and runs the tools it names.
if [ "$1 $2" = "font current" ]; then
  printf 'monospace   (default)  resolves to DejaVu Sans Mono\nsans-serif  Inter\nserif       (default)  resolves to DejaVu Serif\n'; exit 0
fi
if [ "$1 $2" = "font set" ] || [ "$1 $2" = "cursor apply" ]; then echo "$*" >>"$HOME/settings-actions"; exit 0; fi
# The default agent for the launcher's Ask row, and its answer.
if [ "$1 $2 $3" = "app ask --json" ]; then
  printf '{"id": "stub-agent", "name": "Stub Agent", "argv": ["echo"]}\n'; exit 0
fi
if [ "$1 $2" = "app ask" ]; then shift 2; [ "$1" = "--" ] && shift; echo "answer to: $*"; exit 0; fi
# Clipboard history: two entries; copy and clear leave a note for the test.
if [ "$1 $2 $3" = "clipboard list --json" ]; then
  printf '[{"id": "aaaa", "kind": "text", "mime": "text/plain", "size": 11, "time": "2026-11-07T22:00:00Z", "preview": "hello world"},'
  printf ' {"id": "bbbb", "kind": "text", "mime": "text/plain", "size": 5, "time": "2026-11-07T21:00:00Z", "preview": "older"}]\n'; exit 0
fi
if [ "$1 $2" = "clipboard show" ]; then printf 'hello world'; exit 0; fi
if [ "$1 $2" = "clipboard copy" ] || [ "$1 $2" = "clipboard clear" ]; then echo "$2 $3" >>"$HOME/clipboard-actions"; exit 0; fi
# The thermal watch: a hot trip crossed when the test asks for it (a
# trigger file), then the same trip again, down and up, which stays quiet.
if [ "$1 $2" = "thermal watch" ]; then
  while [ ! -e "$HOME/thermal-trip" ]; do sleep 0.2; done
  printf '{"zone":0,"type":"SKIN","trip":3,"kind":"hot","tripTemp":82050,"temp":83000,"direction":"up"}\n'
  while [ ! -e "$HOME/thermal-trip-again" ]; do sleep 0.2; done
  printf '{"zone":0,"type":"SKIN","trip":3,"kind":"hot","tripTemp":82050,"temp":84000,"direction":"up"}\n'
  printf '{"zone":0,"type":"SKIN","trip":3,"kind":"hot","tripTemp":82050,"temp":79000,"direction":"down"}\n'
  printf '{"zone":0,"type":"SKIN","trip":3,"kind":"hot","tripTemp":82050,"temp":83000,"direction":"up"}\n'
  exec sleep infinity
fi
# The agents' usage, as the command reads it from local files.
if [ "$1 $2 $3" = "agent usage --json" ]; then
  cat <<'JSON'
{"scannedAt": "2026-11-08T15:00:00Z", "agents": [
  {"id": "claude", "name": "Claude Code", "found": true, "today": {"input": 1515, "output": 300, "total": 1815}, "week": {"total": 4116}, "paceHour": 1210, "sessions": 1, "limits": []},
  {"id": "codex", "name": "Codex", "found": true, "today": {"total": 5700, "output": 700}, "week": {"total": 13400}, "paceHour": 2300, "sessions": 1, "plan": "pro",
   "limits": [{"name": "primary", "usedPercent": 54.2, "windowMinutes": 300, "resetsAt": "2026-11-08T17:10:00Z"}]}]}
JSON
  exit 0
fi
[ "$1 $2" = "commands --json" ] || exit 2
cat <<'JSON'
{"ok": true, "commands": [
  {"route": "subcult font set", "group": "font", "summary": "Use a font", "args": "<family>", "dangerous": false},
  {"route": "subcult app remove", "group": "app", "summary": "Remove apps", "args": "<id>...", "dangerous": true}]}
JSON
STUB
chmod +x "$work/bin/subcult"
# A stand-in for yt-dlp: progress lines, then the file it "wrote".
cat >"$work/bin/yt-dlp" <<'STUB'
#!/bin/sh
dir=""; while [ $# -gt 0 ]; do case $1 in -P) dir=$2; shift 2;; --) shift; break;; *) shift;; esac; done
echo "[download]  40.0% of 10.00MiB at 2.00MiB/s ETA 00:03"; sleep 1
echo "[download] 100% of 10.00MiB in 00:00:02 at 5.00MiB/s"
mkdir -p "$dir" && : >"$dir/Clip [abc].mp4" && echo "$dir/Clip [abc].mp4"
STUB
chmod +x "$work/bin/yt-dlp"
# A stand-in for systemd-inhibit (no logind here) that holds like it does:
# its command line stays visible and SIGTERM ends it.
cat >"$work/bin/systemd-inhibit" <<'STUB'
#!/bin/sh
trap 'kill "$child" 2>/dev/null; exit 0' TERM INT
sleep infinity & child=$!
wait "$child"
STUB
chmod +x "$work/bin/systemd-inhibit"
# A stand-in for hyprctl (no Hyprland here) that records what the shell
# sends the compositor.
cat >"$work/bin/hyprctl" <<'STUB'
#!/bin/sh
printf '%s\n' "$*" >>"$HOME/hyprctl-log"
STUB
chmod +x "$work/bin/hyprctl"
# A stand-in for curl: SomaFM's channel list for the radio widget, nothing
# else answers.
cat >"$work/bin/curl" <<'STUB'
#!/bin/sh
for a; do case $a in https://somafm.com/channels.json) cat <<'JSON'
{"channels": [
  {"id": "groovesalad", "title": "Groove Salad", "description": "Ambient beats", "genre": "ambient", "dj": "Rusty", "listeners": "1200",
   "playlists": [{"url": "https://api.somafm.com/groovesalad.pls", "format": "mp3", "quality": "highest"}, {"url": "https://api.somafm.com/groovesalad130.pls", "format": "aac", "quality": "highest"}]},
  {"id": "dronezone", "title": "Drone Zone", "description": "", "genre": "ambient", "dj": "", "listeners": "900",
   "playlists": [{"url": "https://api.somafm.com/dronezone.pls", "format": "mp3", "quality": "highest"}]}]}
JSON
exit 0;; esac; done
exit 22
STUB
chmod +x "$work/bin/curl"
# A stand-in for mpv: serves the JSON IPC socket it was given, answers the
# property observations with a song title, records its arguments, and ends
# on quit or when its socket closes.
cat >"$work/bin/mpv" <<'STUB'
#!/usr/bin/python3
import json, os, socket, sys
with open(os.path.join(os.environ["HOME"], "mpv-args"), "a") as f:
    f.write(" ".join(sys.argv[1:]) + "\n")
path = next(a.split("=", 1)[1] for a in sys.argv[1:] if a.startswith("--input-ipc-server="))
try:
    os.unlink(path)
except FileNotFoundError:
    pass
srv = socket.socket(socket.AF_UNIX)
srv.bind(path)
srv.listen(1)
conn, _ = srv.accept()
buf = b""
while True:
    data = conn.recv(4096)
    if not data:
        break
    buf += data
    while b"\n" in buf:
        line, buf = buf.split(b"\n", 1)
        try:
            cmd = json.loads(line)["command"]
        except Exception:
            continue
        if cmd[0] == "observe_property":
            conn.sendall(b'{"request_id":0,"error":"success"}\n')
            if cmd[2] == "media-title":
                conn.sendall(json.dumps({"event": "property-change", "id": cmd[1], "name": "media-title", "data": "Stub Artist - Stub Song"}).encode() + b"\n")
        elif cmd[0] == "quit":
            sys.exit(0)
STUB
chmod +x "$work/bin/mpv"
# System tools before the developer's shims: a mise shim resolves its tool
# from HOME, and the test's HOME is empty, so `fd` through the shim fails
# and the launcher's file search finds nothing.
export PATH="$work/bin:/usr/bin:$PATH"
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
printf '{"layout": {"left": ["subcult.test-probe", "subcult.menu"]}}\n' >"$home1/.config/subcult/shell/bar.json"
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

# A notification replaced through replaces_id (a download's progress)
# updates its popup and history record instead of adding one. The first has
# the app's own 8 s timeout; the replacement restarts it.
notify() { # app replaces_id summary body timeout -> the id
  DBUS_SESSION_BUS_ADDRESS=unix:path=$work/bus gdbus call --session --dest org.freedesktop.Notifications \
    --object-path /org/freedesktop/Notifications --method org.freedesktop.Notifications.Notify \
    "$1" "$2" "" "$3" "$4" "[]" "{}" "$5" | sed -E 's/.*uint32 ([0-9]+).*/\1/'
}
nid=$(notify subarchy-test 0 "Download 10%" "" 8000)
sleep 1
st=$(status "$home1")
[[ $(json 'd["history"][0]["id"]') == "$nid" && $(json 'd.get("popups")') == 1 ]] || fail "no popup for the download: $st"
[[ $(notify subarchy-test "$nid" "Download 90%" "" 8000) == "$nid" ]] || fail "replaces_id gave a new id"
sleep 1
st=$(status "$home1")
[[ $(json 'd["history"][0]["summary"]') == "Download 90%" && $(json 'd["history"][0]["id"]') == "$nid" ]] ||
  fail "the replaced notification did not update its history record: $st"
[[ $(json 'd.get("popups")') == 1 && $(json 'd.get("unread")') == 2 ]] || fail "a replacement added a popup or a record: $st"
sleep 6
st=$(status "$home1")
[[ $(json 'd.get("popups")') == 1 ]] || fail "the replaced popup went before its restarted 8 s timeout: $st"
sleep 4
st=$(status "$home1")
[[ $(json 'd.get("popups")') == 0 ]] || fail "the replaced popup stayed past its timeout: $st"

# Markup and entities arrive as capped plain text in the history.
DBUS_SESSION_BUS_ADDRESS=unix:path=$work/bus gdbus call --session --dest org.freedesktop.Notifications \
  --object-path /org/freedesktop/Notifications --method org.freedesktop.Notifications.Notify \
  "$(printf 'app%.0s' $(seq 40))" 0 "" "x &amp; <b>y</b>" "$(printf 'b%.0s' $(seq 2100))" "[]" "{}" 1000 >/dev/null
sleep 1
st=$(status "$home1")
[[ $(json 'd["history"][0]["summary"]') == "x & y" ]] || fail "history summary is not plain text: $st"
[[ $(json 'len(d["history"][0]["body"])') == 2000 && $(json 'len(d["history"][0]["appName"])') == 64 ]] ||
  fail "history body or app name not capped: $(json 'len(d["history"][0]["body"]), len(d["history"][0]["appName"])')"
sleep 2

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
lfield() { # field of the launcher's state
  python3 -c "import json,sys; print(json.loads(sys.argv[1])[sys.argv[2]])" "$(launcher state)" "$1"
}
# Commands, scripts and qalc answers arrive from processes the launcher
# starts, so these checks wait for them (up to 10 s) instead of sleeping.
lwait() { # query, python condition over the rows r; leaves the state in $ls
  local _
  launcher type "$1" >/dev/null
  for _ in $(seq 20); do
    sleep 0.5
    ls=$(launcher state)
    [[ $(row "$2") == True ]] && return 0
  done
  return 1
}
filewait() { # file, expected content
  local _
  for _ in $(seq 20); do
    [[ $(cat "$1" 2>/dev/null) == "$2" ]] && return 0
    sleep 0.5
  done
  return 1
}
lwait "remove" '[x["id"] for x in r if x["kind"] == "command"] == ["subcult app remove"]' ||
  fail "subcult commands are not searched: $ls"
lwait "font set Iosevka" 'r[:1] and (r[0]["kind"], r[0]["name"]) == ("command", "font set Iosevka")' ||
  fail "a command with arguments is not offered first: $ls"
lwait "app remove" 'r[:1] and r[0]["id"] == "subcult app remove"' || fail "no row for a dangerous command: $ls"
launcher enter >/dev/null
ls=$(launcher state)
[[ $(python3 -c "import json,sys; print(json.loads(sys.argv[1])['pending'])" "$ls") == "subcult app remove" ]] ||
  fail "a dangerous command did not ask for confirmation: $ls"
ls=$(lstate "zzqx nothing here")
[[ $(row '[(x["kind"], x["url"]) for x in r if x["kind"] != "ask"]') == "[('web', 'https://duckduckgo.com/?q=zzqx%20nothing%20here')]" ]] ||
  fail "no match does not fall back to web search: $ls"
ls=$(lstate "@yt cats")
[[ $(row 'r[0]["url"]') == "https://www.youtube.com/results?search_query=cats" ]] || fail "@yt is not a quicklink: $ls"
ls=$(lstate "gh subarchy")
[[ $(row 'r[0]["url"]') == "https://github.com/search?q=subarchy" ]] || fail "a quicklink keyword in root search: $ls"
if command -v qalc >/dev/null; then
  lwait "=2+2*3" '[(x["kind"], x["name"]) for x in r] == [("calc", "8")]' || fail "= does not calculate: $ls"
  lwait "sqrt(16)" 'r[:1] and (r[0]["kind"], r[0]["name"]) == ("calc", "4")' || fail "inline math has no answer: $ls"
else
  [[ -z ${CI:-} ]] || fail "qalc not installed"
  echo "shell-headless: qalc not installed, calculator not checked"
fi
# Files ("." runs fd on demand) and symbols (":" reads the emoji data and the
# symbols file); the preview pane follows the selection.
mkdir -p "$home1/Documents"
printf 'needle text\n' >"$home1/Documents/subarchy-needle.txt"
if command -v fd >/dev/null; then
  lwait ". subarchy-needle" '[x["name"] for x in r] == ["subarchy-needle.txt"]' || fail "the launcher did not find a file with fd: $ls"
  lwait ". subarchy-needle" 'True' >/dev/null
  [[ $(lfield preview) == "needle text" ]] || fail "the file preview is not the file's text: $(launcher state)"
else
  [[ -z ${CI:-} ]] || fail "fd not installed"
  echo "shell-headless: fd not installed, file search not checked"
fi
ls=$(lstate ":em dash")
[[ $(row 'r[0]["id"]') == "symbol:—" ]] || fail "the symbols file is not searched: $ls"
[[ $(lfield preview) == "—" ]] || fail "the symbol preview is not the character: $(launcher state)"
if [[ -f /usr/share/unicode/emoji/emoji-test.txt ]]; then
  lwait ":red heart" 'any(x["id"] == "symbol:\u2764\ufe0f" for x in r)' || fail "emoji are not searched: $ls"
else
  [[ -z ${CI:-} ]] || fail "unicode-emoji not installed"
  echo "shell-headless: unicode-emoji not installed, emoji not checked"
fi
# Ask AI: the last row of a root search names the agent and says the text
# leaves the machine; Enter on it asks, and the answer lands in the preview.
ls=$(lstate "what is subarchy")
[[ $(row 'r[-1]["kind"]') == ask && $(row 'r[-1]["name"].startswith("Ask Stub Agent: ") and "what is subarchy" in r[-1]["name"]') == True ]] ||
  fail "the Ask row is not the last root result: $ls"
launcher last >/dev/null
launcher enter >/dev/null
for _ in $(seq 20); do
  [[ $(lfield preview) == "answer to: what is subarchy" ]] && break
  sleep 0.5
done
[[ $(lfield preview) == "answer to: what is subarchy" ]] || fail "the agent's answer did not reach the preview: $(launcher state)"
launcher close >/dev/null

# Clipboard history: "$" lists the entries newest first with a clear row
# last, the preview shows the entry, Enter copies it back.
lwait '$' '[x["id"] for x in r] == ["clip:aaaa", "clip:bbbb", "clip:clear"]' || fail "the clipboard history is not listed: $ls"
for _ in $(seq 10); do
  [[ $(lfield preview) == "hello world" ]] && break
  sleep 0.5
done
[[ $(lfield preview) == "hello world" ]] || fail "the clipboard preview is not the entry: $(launcher state)"
lwait "\$old" '[x["id"] for x in r] == ["clip:bbbb"]' || fail "typing after \$ does not filter: $ls"
launcher enter >/dev/null
filewait "$home1/clipboard-actions" "copy bbbb" || fail "Enter did not copy the entry back: $(cat "$home1/clipboard-actions" 2>/dev/null)"
[[ $(json 'd.get("launcher")') == False ]] || fail "the launcher stayed open after a copy"

# Script commands with Raycast headers, aliases and snippets. The script
# runs silently and writes its argument where the test can read it.
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
lwait "greet" 'r[:1] and (r[0]["kind"], r[0]["id"]) == ("script", "script:greet.sh")' ||
  fail "a Raycast script is not a command: $ls"
launcher enter >/dev/null
[[ $(lfield argument) == 1 ]] || fail "the script did not ask for its argument: $(launcher state)"
launcher type "world" >/dev/null
launcher enter >/dev/null
filewait "$home1/greet-out" world || fail "the script did not run with its argument"
lwait "hi there friend" 'r[:1] and r[0]["id"] == "script:greet.sh"' || fail "an alias does not lead: $ls"
launcher enter >/dev/null
filewait "$home1/greet-out" "there friend" || fail "an alias did not pass its arguments"
launcher close >/dev/null
[[ $(lfield aliases) == "['hi', 'fs']" ]] || fail "the aliases are not registered: $(launcher state)"
launcher hotkey hi >/dev/null
[[ $(lfield argument) == 1 ]] || fail "an alias hotkey for a script with an argument did not ask for it: $(launcher state)"
launcher close >/dev/null
ls=$(lstate "sig")
[[ $(row '(r[0]["kind"], r[0]["name"])') == "('snippet', 'Sign-off')" ]] || fail "snippets are not searched: $ls"
launcher close >/dev/null

# Keep-awake holds a logind idle inhibitor (the stub here) and writes its
# state file; off releases it and removes the file.
inhibitor() { pgrep -u "$(id -u)" -f '[s]ystemd-inhibit --what=idle --who=SUBCULT' >/dev/null; }
HOME=$home1 quickshell ipc -p "$shell" call subcult.shell keepAwake true >/dev/null
for _ in $(seq 10); do inhibitor && break; sleep 0.5; done
inhibitor || fail "keep-awake holds no inhibitor: $(status "$home1")"
for _ in $(seq 10); do [[ $(cat "$home1/.local/state/subcult/keep-awake" 2>/dev/null) == 1 ]] && break; sleep 0.5; done
[[ $(cat "$home1/.local/state/subcult/keep-awake" 2>/dev/null) == 1 ]] || fail "keep-awake state not saved"
st=$(status "$home1")
[[ $(json 'd.get("keepAwake")') == True ]] || fail "keep-awake not reported on: $st"
HOME=$home1 quickshell ipc -p "$shell" call subcult.shell keepAwake false >/dev/null
for _ in $(seq 10); do inhibitor || break; sleep 0.5; done
! inhibitor || fail "keep-awake off left the inhibitor: $(pgrep -u "$(id -u)" -af '[s]ystemd-inhibit --what=idle' | head -3); $(status "$home1")"
for _ in $(seq 10); do [[ ! -e "$home1/.local/state/subcult/keep-awake" ]] && break; sleep 0.5; done
[[ ! -e "$home1/.local/state/subcult/keep-awake" ]] || fail "keep-awake off left the state file"

# The media widget loads and stays hidden without a player (no MPRIS here).
st=$(status "$home1")
[[ $(json '"subcult.media" in d["loaded"]["HEADLESS-1"] and "subcult.media" not in d["shown"]["HEADLESS-1"]') == True ]] ||
  fail "the media widget is not loaded-and-hidden without a player: $st"

# The settings panel (SUBCULT mark): current values, a preview of pending
# changes, apply to the user files only, undo the last apply.
settings() { HOME=$home1 quickshell ipc -p "$shell" call subcult.settings "$@"; }
sfield() { python3 -c "import json,sys; print(json.loads(sys.argv[1])[sys.argv[2]])" "$(settings state)" "$1"; }
HOME=$home1 quickshell ipc -p "$shell" call subcult.shell panel subcult.menu >/dev/null
sleep 1.5
st=$(status "$home1")
[[ $(json 'd.get("panel")') == subcult.menu ]] || fail "the settings panel did not open: $st"
for _ in $(seq 10); do [[ $(sfield current) == *"'font.ui': 'Inter'"* ]] && break; sleep 0.5; done
[[ $(sfield current) == *"'font.ui': 'Inter'"* && $(sfield current) == *"'idle.lock': 7"* ]] || fail "settings current values: $(settings state)"
settings set bar.minimal "subcult.workspaces" >/dev/null
settings set cursor.size 32 >/dev/null
settings set idle.lock 5 >/dev/null
settings set font.ui "Iosevka Aile" >/dev/null
[[ $(settings set idle.lock 900) == false && $(sfield errors) == *"between 0 and 240"* ]] || fail "a bad value is not refused: $(settings state)"
settings set idle.lock 5 >/dev/null
[[ $(python3 -c "import json,sys; print(len(json.loads(sys.argv[1])['preview']))" "$(settings state)") == 4 ]] || fail "four pending changes do not preview: $(settings state)"
settings apply >/dev/null
filewait "$home1/.config/subcult/idle.json" '{
  "lockAfterMinutes": 5
}' || fail "apply did not write idle.json: $(cat "$home1/.config/subcult/idle.json" 2>/dev/null)"
[[ $(python3 -c "import json,sys; d=json.load(open(sys.argv[1])); print(d['layout']['minimal'], d.get('widgets', {}))" "$home1/.config/subcult/shell/bar.json") == "['subcult.workspaces'] {}" ]] ||
  fail "apply did not scope the bar layout write: $(cat "$home1/.config/subcult/shell/bar.json")"
[[ $(python3 -c "import json,sys; print(json.load(open(sys.argv[1]))['size'])" "$home1/.config/subcult/cursor.json") == 32 ]] || fail "apply did not write cursor.json"
for _ in $(seq 20); do [[ $(grep -c . "$home1/settings-actions" 2>/dev/null) == 2 ]] && break; sleep 0.5; done
[[ $(sort "$home1/settings-actions" 2>/dev/null | tr '\n' '|') == "cursor apply|font set Iosevka Aile --ui|" ]] || fail "apply did not run the tools: $(cat "$home1/settings-actions" 2>/dev/null)"
for _ in $(seq 10); do [[ $(sfield canUndo) == True ]] && break; sleep 0.5; done
[[ $(sfield canUndo) == True ]] || fail "no undo record after apply: $(settings state)"
settings undo >/dev/null
filewait "$home1/.config/subcult/idle.json" '{
  "lockAfterMinutes": 7
}' || fail "undo did not restore idle.json: $(cat "$home1/.config/subcult/idle.json")"
[[ $(python3 -c "import json,sys; print(json.load(open(sys.argv[1]))['layout']['minimal'])" "$home1/.config/subcult/shell/bar.json") == "['subcult.workspaces', 'subcult.display']" ]] ||
  fail "undo did not restore the bar layout: $(cat "$home1/.config/subcult/shell/bar.json")"
for _ in $(seq 10); do [[ $(sfield canUndo) == False ]] && break; sleep 0.5; done
[[ $(sfield canUndo) == False ]] || fail "undo is not one step: $(settings state)"
HOME=$home1 quickshell ipc -p "$shell" call subcult.shell panel close >/dev/null
rm -f "$home1/settings-actions"
# The calendar widget reads the sync cache, watched (no polling): written
# after start, it is picked up; the widget shows with or without it.
mkdir -p "$home1/.local/state/subcult/calendar"
printf '{"version": 1, "syncedAt": "2026-11-07T09:30:00Z", "events": [{"id": "x", "calendar": "Test", "title": "Headless standup", "start": "2099-01-01T10:00:00", "end": "2099-01-01T10:30:00", "allDay": false}]}\n' \
  >"$home1/.local/state/subcult/calendar/events.json"
[[ $(json '"subcult.calendar" in d["shown"]["HEADLESS-1"]') == True ]] || fail "the calendar widget is not shown: $st"
calendar() { HOME=$home1 quickshell ipc -p "$shell" call subcult.shell widgetProperty subcult.calendar label; }
for _ in $(seq 20); do
  [[ $(calendar) == *"Headless standup 10:00" ]] && break
  sleep 0.5
done
[[ $(calendar) == *"Headless standup 10:00" ]] || fail "the calendar widget did not pick up the written cache: $(calendar)"
# The network and Bluetooth panels open without NetworkManager or BlueZ
# (nothing to list, nothing scans) and close like any panel.
for w in network bluetooth; do
  HOME=$home1 quickshell ipc -p "$shell" call subcult.shell panel "subcult.$w" >/dev/null
  sleep 1
  st=$(status "$home1")
  [[ $(json 'd.get("panel")') == "subcult.$w" ]] || fail "the $w panel did not open: $st"
  HOME=$home1 quickshell ipc -p "$shell" call subcult.shell panel close >/dev/null
done
# Motion: the setting file is read live and the compositor is told. With no
# battery here, `auto` means on.
st=$(status "$home1")
[[ $(json 'd.get("motion")') == True && $(json 'd.get("motionMode")') == auto ]] || fail "motion is not on by default: $st"
printf '{"mode": "off"}\n' >"$home1/.config/subcult/motion.json"
sleep 2
st=$(status "$home1")
[[ $(json 'd.get("motion")') == False && $(json 'd.get("motionMode")') == off ]] || fail "motion off did not apply live: $st"
grep -q 'eval dofile(\[==\[.*/default/hypr/looknfeel.lua\]==\])' "$home1/hyprctl-log" 2>/dev/null || fail "the motion change did not reach the compositor: $(cat "$home1/hyprctl-log" 2>/dev/null)"
printf '{"mode": "on"}\n' >"$home1/.config/subcult/motion.json"
sleep 2
st=$(status "$home1")
[[ $(json 'd.get("motion")') == True ]] || fail "motion on did not apply live: $st"
rm "$home1/.config/subcult/motion.json"
# Thermal alerts: a hot trip crossed (from the stub `subcult thermal watch`)
# is one notification; the same trip again, and down and up within the
# cooldown, add none.
st=$(status "$home1")
before=$(json 'd.get("unread")')
touch "$home1/thermal-trip"
for _ in $(seq 20); do st=$(status "$home1"); [[ $(json 'd["history"][0]["summary"] if d["history"] else ""') == "Running hot" ]] && break; sleep 0.5; done
[[ $(json 'd["history"][0]["summary"] if d["history"] else ""') == "Running hot" && $(json 'd.get("unread")') == $((before + 1)) ]] ||
  fail "a hot trip did not alert once: $st"
[[ $(json 'd["history"][0]["body"]') == "SKIN at 83 °C, past its hot trip at 82 °C. Ease the load or check the airflow." ]] || fail "thermal alert text: $st"
touch "$home1/thermal-trip-again"
sleep 2
st=$(status "$home1")
[[ $(json 'd.get("unread")') == $((before + 1)) ]] || fail "a repeated trip alerted again within the cooldown: $st"

# The notification centre opens from the bell and closes like any panel.
HOME=$home1 quickshell ipc -p "$shell" call subcult.shell panel subcult.notifications >/dev/null
sleep 1
st=$(status "$home1")
[[ $(json 'd.get("panel")') == subcult.notifications ]] || fail "the notifications panel did not open: $st"
HOME=$home1 quickshell ipc -p "$shell" call subcult.shell panel close >/dev/null

# A widget's click-out panel: the audio panel opens on request (no
# PipeWire here, so it shows no devices), one at a time, and closes.
HOME=$home1 quickshell ipc -p "$shell" call subcult.shell panel subcult.audio >/dev/null
sleep 1
st=$(status "$home1")
[[ $(json 'd.get("panel")') == subcult.audio ]] || fail "the audio panel did not open: $st"
HOME=$home1 quickshell ipc -p "$shell" call subcult.shell panel subcult.audio >/dev/null
sleep 1
st=$(status "$home1")
[[ $(json 'd.get("panel")') == "" ]] || fail "a second request did not close the panel: $st"
HOME=$home1 quickshell ipc -p "$shell" call subcult.shell panel subcult.audio >/dev/null
HOME=$home1 quickshell ipc -p "$shell" call subcult.shell panel close >/dev/null
sleep 1
st=$(status "$home1")
[[ $(json 'd.get("panel")') == "" ]] || fail "the panel did not close: $st"

# The auto-wallpaper widget, off by default: enabled in bar.json with a
# folder of two images, it loads, reports its timer, and its IPC call
# writes the next image to the wallpaper state file, which the background
# shows at once.
mkdir -p "$home1/walls"
magick -size 64x64 xc:'#FF0000' "$home1/walls/a.png"
magick -size 64x64 xc:'#0000FF' "$home1/walls/b.png"
printf '{"layout": {"left": ["subcult.test-probe", "subcult.auto-wallpaper"]}, "widgets": {"subcult.auto-wallpaper": {"directory": "%s"}}}\n' "$home1/walls" >"$home1/.config/subcult/shell/bar.json"
sleep 2
st=$(status "$home1")
[[ $(json '"subcult.auto-wallpaper" in d["loaded"]["HEADLESS-1"]') == True ]] || fail "auto-wallpaper did not load when enabled: $st"
[[ $(json 'd["intervals"].get("subcult.auto-wallpaper.rotate", {}).get("interval")') == 1800000 ]] || fail "auto-wallpaper timer not reported: $st"
HOME=$home1 quickshell ipc -p "$shell" call subcult.wallpaper next >/dev/null || fail "auto-wallpaper IPC failed"
sleep 2
[[ $(cat "$home1/.local/state/subcult/wallpaper" 2>/dev/null) == "$home1/walls/a.png" ]] || fail "auto-wallpaper did not write the first image: $(cat "$home1/.local/state/subcult/wallpaper" 2>/dev/null)"
shot HEADLESS-1
[[ $(pixel 640 300) == FF0000 ]] || fail "the background does not show the chosen wallpaper (got $(pixel 640 300))"
HOME=$home1 quickshell ipc -p "$shell" call subcult.wallpaper next >/dev/null
sleep 2
[[ $(cat "$home1/.local/state/subcult/wallpaper") == "$home1/walls/b.png" ]] || fail "auto-wallpaper did not go to the next image"
rm -f "$home1/.local/state/subcult/wallpaper"
# The downloads widget, off by default: enabled in bar.json it loads and
# stays hidden; a queued URL runs the (stub) yt-dlp, shows while running,
# finishes with the file, and hides again.
printf '{"layout": {"left": ["subcult.test-probe", "subcult.downloads"]}, "widgets": {"subcult.downloads": {"directory": "%s/dl"}}}\n' "$home1" >"$home1/.config/subcult/shell/bar.json"
sleep 2
st=$(status "$home1")
[[ $(json '"subcult.downloads" in d["loaded"]["HEADLESS-1"] and "subcult.downloads" not in d["shown"]["HEADLESS-1"]') == True ]] ||
  fail "downloads did not load hidden when enabled: $st"
HOME=$home1 quickshell ipc -p "$shell" call subcult.downloads add "https://x.test/v/1" >/dev/null || fail "downloads IPC failed"
sleep 0.5
st=$(status "$home1")
[[ $(json '"subcult.downloads" in d["shown"]["HEADLESS-1"]') == True ]] || fail "downloads not shown while a job runs: $st"
for _ in $(seq 10); do [[ -e "$home1/dl/Clip [abc].mp4" ]] && break; sleep 0.5; done
sleep 1
dl=$(HOME=$home1 quickshell ipc -p "$shell" call subcult.downloads state)
[[ $(python3 -c "import json,sys; j=json.loads(sys.argv[1]); print(j[0]['status'], j[0]['percent'], j[0]['file'].endswith('Clip [abc].mp4'))" "$dl") == "done 100 True" ]] ||
  fail "the download did not finish as expected: $dl"
st=$(status "$home1")
[[ $(json '"subcult.downloads" in d["shown"]["HEADLESS-1"]') == False ]] || fail "downloads still shown when idle: $st"
# The agents widget, off by default: enabled in bar.json it loads, reports
# its timer, shows the (stub) usage and opens its panel.
printf '{"layout": {"left": ["subcult.test-probe", "subcult.agents"]}}\n' >"$home1/.config/subcult/shell/bar.json"
sleep 2
st=$(status "$home1")
[[ $(json '"subcult.agents" in d["shown"]["HEADLESS-1"]') == True ]] || fail "agents did not load when enabled: $st"
[[ $(json 'd["intervals"].get("subcult.agents.refresh", {}).get("interval")') == 600000 ]] || fail "agents timer not reported: $st"
[[ $(HOME=$home1 quickshell ipc -p "$shell" call subcult.shell widgetProperty subcult.agents label) == "C 1.8k · X 54%" ]] ||
  fail "agents label: $(HOME=$home1 quickshell ipc -p "$shell" call subcult.shell widgetProperty subcult.agents label)"
HOME=$home1 quickshell ipc -p "$shell" call subcult.shell panel subcult.agents >/dev/null
sleep 1
st=$(status "$home1")
[[ $(json 'd.get("panel")') == subcult.agents ]] || fail "the agents panel did not open: $st"
HOME=$home1 quickshell ipc -p "$shell" call subcult.shell panel close >/dev/null
# SomaFM: in the default layout; its panel fetches the channel list (stub
# curl), playing a channel starts the (stub) mpv with the aac stream and the
# song arrives over mpv's IPC socket; stop ends mpv.
printf '{"layout": {"left": ["subcult.test-probe", "subcult.soma"]}}\n' >"$home1/.config/subcult/shell/bar.json"
sleep 2
st=$(status "$home1")
[[ $(json '"subcult.soma" in d["shown"]["HEADLESS-1"]') == True ]] || fail "soma did not load: $st"
HOME=$home1 quickshell ipc -p "$shell" call subcult.shell panel subcult.soma >/dev/null
for _ in $(seq 20); do so=$(HOME=$home1 quickshell ipc -p "$shell" call subcult.soma state); [[ $(python3 -c "import json,sys; print(json.loads(sys.argv[1])['channels'])" "$so") == 2 ]] && break; sleep 0.5; done
[[ $(python3 -c "import json,sys; print(json.loads(sys.argv[1])['channels'])" "$so") == 2 ]] || fail "the channel list did not load on panel open: $so"
HOME=$home1 quickshell ipc -p "$shell" call subcult.shell panel close >/dev/null
[[ $(HOME=$home1 quickshell ipc -p "$shell" call subcult.soma play groovesalad) == true ]] || fail "play refused"
for _ in $(seq 30); do so=$(HOME=$home1 quickshell ipc -p "$shell" call subcult.soma state); [[ $(python3 -c "import json,sys; print(json.loads(sys.argv[1])['song'])" "$so") == "Stub Artist - Stub Song" ]] && break; sleep 0.5; done
[[ $(python3 -c "import json,sys; j=json.loads(sys.argv[1]); print(j['playing'], j['channel'], j['song'])" "$so") == "True groovesalad Stub Artist - Stub Song" ]] || fail "no song over mpv's IPC: $so"
grep -q -- '--input-ipc-server=.*subcult-soma.sock -- https://api.somafm.com/groovesalad130.pls' "$home1/mpv-args" || fail "mpv was not given the aac stream: $(cat "$home1/mpv-args")"
[[ $(HOME=$home1 quickshell ipc -p "$shell" call subcult.shell widgetProperty subcult.soma label) == "Groove Salad · Stub Artist - Stub Song" ]] ||
  fail "soma label: $(HOME=$home1 quickshell ipc -p "$shell" call subcult.shell widgetProperty subcult.soma label)"
HOME=$home1 quickshell ipc -p "$shell" call subcult.soma stop >/dev/null
sleep 1
so=$(HOME=$home1 quickshell ipc -p "$shell" call subcult.soma state)
[[ $(python3 -c "import json,sys; j=json.loads(sys.argv[1]); print(j['playing'], j['song'])" "$so") == "False " ]] || fail "stop did not end playback: $so"
[[ $(HOME=$home1 quickshell ipc -p "$shell" call subcult.soma play nosuch) == false ]] || fail "an unknown channel played"
# Opening another widget's panel while one is open switches to it.
HOME=$home1 quickshell ipc -p "$shell" call subcult.shell panel subcult.audio >/dev/null
HOME=$home1 quickshell ipc -p "$shell" call subcult.shell panel subcult.notifications >/dev/null
sleep 1
st=$(status "$home1")
[[ $(json 'd.get("panel")') == subcult.notifications ]] || fail "a second widget's panel did not replace the first: $st"
HOME=$home1 quickshell ipc -p "$shell" call subcult.shell panel close >/dev/null
check_log "$work/qs1.log"

# Workspace names written after start reach the bar's labels; the switch
# overlay answers its OSD call.
mkdir -p "$home1/.config/subcult/shell"
printf '{"workspaces": [{"id": 3, "name": "Workbench", "short": "wrk"}]}\n' >"$home1/.config/subcult/shell/workspaces.json"
sleep 2
st=$(status "$home1")
[[ $(json 'd["workspaceLabels"].get("3")') == WRK ]] || fail "a workspace name did not reach the bar: $st"
HOME=$home1 quickshell ipc -p "$shell" call subcult.osd flash workspace >/dev/null 2>&1 || fail "the OSD has no workspace kind"
st=$(status "$home1")
[[ $(json 'd.get("osd")') == workspace ]] || fail "the workspace OSD did not show: $st"
sleep 2

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
