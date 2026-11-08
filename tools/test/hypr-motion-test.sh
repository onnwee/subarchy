#!/usr/bin/env bash
# The motion gate in default/hypr/looknfeel.lua: with motion off (the
# setting, or `auto` on battery) a last hl.config turns animations, blur and
# shadows off after the theme; with motion on nothing is added. Runs the Lua
# with a stand-in `hl` and a fake /sys.
set -euo pipefail

root=$(git rev-parse --show-toplevel)
fail() { echo "hypr-motion-test: $*" >&2; exit 1; }
lua=$(command -v lua5.4 || command -v lua || true)
[[ -n $lua ]] || { echo "hypr-motion-test: lua not installed, skipped"; exit 0; }

home=$(mktemp -d)
trap 'rm -rf -- "$home"' EXIT
mkdir -p "$home/.config/subcult"
ps="$home/sys/class/power_supply"

supply() { # name type [online|status value]
  mkdir -p "$ps/$1"
  echo "$2" >"$ps/$1/type"
  [[ $# -ge 4 ]] && echo "$4" >"$ps/$1/$3"
  return 0
}

# Prints the number of hl.config calls and whether the last one is the gate.
run() {
  HOME=$home SUBCULT_PATH=$root SUBCULT_SYS=$home/sys "$lua" - <<'LUA'
local configs = {}
hl = { config = function(t) configs[#configs + 1] = t end }
sub = {}
dofile(os.getenv("SUBCULT_PATH") .. "/default/hypr/looknfeel.lua")
local last = configs[#configs]
local gate = last.animations and last.animations.enabled == false and last.decoration
  and last.decoration.blur and last.decoration.blur.enabled == false
  and last.decoration.shadow and last.decoration.shadow.enabled == false and not last.general
print(#configs .. " " .. (gate and "gated" or "open") .. " " .. tostring(sub.motion))
LUA
}

# No setting, mains online: auto is on.
supply AC Mains online 1
supply BAT0 Battery status Charging
[[ $(run) == "2 open true" ]] || fail "auto on AC: $(run)"

# Unplugged: auto is off, and the gate comes last.
echo 0 >"$ps/AC/online"
echo Discharging >"$ps/BAT0/status"
[[ $(run) == "3 gated false" ]] || fail "auto on battery: $(run)"

# The setting wins over the power source.
printf '{"mode": "on"}\n' >"$home/.config/subcult/motion.json"
[[ $(run) == "2 open true" ]] || fail "on while on battery: $(run)"
echo 1 >"$ps/AC/online"
printf '{ "mode" : "off" }\n' >"$home/.config/subcult/motion.json"
[[ $(run) == "3 gated false" ]] || fail "off while on AC: $(run)"

# A user theme turning animations on is still gated when motion is off.
mkdir -p "$home/.config/subcult/theme"
printf 'hl.config({ animations = { enabled = true } })\n' >"$home/.config/subcult/theme/hyprland.lua"
[[ $(run) == "4 gated false" ]] || fail "the theme's animations escape the gate: $(run)"
rm "$home/.config/subcult/motion.json" "$home/.config/subcult/theme/hyprland.lua"

# An unknown value reads as auto; a broken file too.
printf '{"mode": "reduced"}\n' >"$home/.config/subcult/motion.json"
[[ $(run) == "2 open true" ]] || fail "an unknown mode is not auto: $(run)"
printf '{ broken' >"$home/.config/subcult/motion.json"
[[ $(run) == "2 open true" ]] || fail "a broken file is not auto: $(run)"
rm "$home/.config/subcult/motion.json"

# A battery without a mains device: discharging means battery.
rm -r "$ps/AC"
[[ $(run) == "3 gated false" ]] || fail "a discharging battery alone: $(run)"
echo Full >"$ps/BAT0/status"
[[ $(run) == "2 open true" ]] || fail "a full battery alone: $(run)"

# A desktop: no supplies at all is AC.
rm -r "$home/sys"
[[ $(run) == "2 open true" ]] || fail "no power supplies: $(run)"

echo "hypr-motion-test: ok"
