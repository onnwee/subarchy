#!/usr/bin/env bash
# Runs the Subarchy shell in a headless sway and checks it from outside:
# no QML errors, a bar in the palette's base colour on every output (also
# after an output is added), and a broken user palette and bar config fall
# back to the defaults with one warning.
# Usage: tools/test/shell-headless.sh path/to/shell
set -euo pipefail

shell=$(realpath "${1:?path to the shell folder}")
root=$(git rev-parse --show-toplevel)
fail() { echo "shell-headless: $*" >&2; exit 1; }

for tool in sway swaymsg quickshell grim magick python3; do
  command -v "$tool" >/dev/null || { echo "shell-headless: $tool not installed, skipped"; exit 0; }
done

work=$(mktemp -d)
pids=()
cleanup() {
  for p in "${pids[@]}"; do kill "$p" 2>/dev/null || true; done
  wait 2>/dev/null || true
  rm -rf -- "$work"
}
trap cleanup EXIT

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

start_shell() { # home log
  HOME=$1 SUBCULT_PATH=$root QS_NO_RELOAD_POPUP=1 quickshell -p "$shell" >"$2" 2>&1 &
  pids+=($!)
  sleep 5
}

check_log() { # log
  if grep -nE 'ERROR|TypeError|ReferenceError|is not a type|is not installed|Cannot assign' "$1"; then
    fail "QML errors in the shell log"
  fi
}

top_colour() { # output
  grim -o "$1" "$work/shot.png"
  magick "$work/shot.png" -crop "x20+0+0" +repage -format %c histogram:info:- | sort -rn | head -1 |
    grep -oE '#[0-9A-F]{6}' | head -1
}

ipc_status() { # home
  HOME=$1 quickshell ipc -p "$shell" call subcult.shell status
}

# 1. The defaults.
home1="$work/home1"
mkdir -p "$home1"
start_shell "$home1" "$work/qs1.log"
check_log "$work/qs1.log"
[[ $(top_colour HEADLESS-1) == "#100B19" ]] || fail "the bar is not base #100B19 (got $(top_colour HEADLESS-1))"
# The widgets draw: the bar strip holds more than its background and line.
others=$(magick "$work/shot.png" -crop "x24+0+0" +repage -format %c histogram:info:- |
  grep -vcE '#100B19|#1F1830' || true)
[[ $others -gt 0 ]] || fail "the bar draws nothing but its background"
loaded=$(ipc_status "$home1" | python3 -c 'import json,sys; print(" ".join(json.load(sys.stdin)["loaded"]["HEADLESS-1"]))')
[[ " $loaded " == *" subcult.menu "* ]] || fail "the full bar did not load the menu (loaded: $loaded)"
# SHELL_HEADLESS_SHOT=file keeps the screenshot for a look.
if [[ -n ${SHELL_HEADLESS_SHOT:-} ]]; then cp "$work/shot.png" "$SHELL_HEADLESS_SHOT"; fi

# 2. An output appears: it gets a bar.
swaymsg -q create_output
sleep 3
bars=$(ipc_status "$home1" | python3 -c 'import json,sys; print(len(json.load(sys.stdin)["bars"]))')
[[ $bars == 2 ]] || fail "after adding an output the shell reports $bars bars, want 2"
[[ $(top_colour HEADLESS-2) == "#100B19" ]] || fail "the new output has no bar"
check_log "$work/qs1.log"
kill "${pids[-1]}"
sleep 1

# 3. A broken user palette and bar config: defaults, one config warning.
home2="$work/home2"
mkdir -p "$home2/.config/subcult/theme" "$home2/.config/subcult/shell"
printf '{ "colors": ' >"$home2/.config/subcult/theme/palette.json"
printf '{ "layout": ' >"$home2/.config/subcult/shell/bar.json"
start_shell "$home2" "$work/qs2.log"
check_log "$work/qs2.log"
[[ $(top_colour HEADLESS-1) == "#100B19" ]] || fail "a broken palette changed the bar colour"
warnings=$(grep -c 'subcult shell config' "$work/qs2.log" || true)
[[ $warnings == 1 ]] || fail "want exactly one config warning, got $warnings"

echo "shell-headless: ok"
