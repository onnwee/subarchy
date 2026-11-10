#!/usr/bin/env bash
# Checks bin/subcult-power-auto against fake sysfs trees.
set -euo pipefail

root=$(git rev-parse --show-toplevel)
cmd="$root/bin/subcult-power-auto"
work=$(mktemp -d)
cleanup() { rm -r -- "$work"; }
trap cleanup EXIT
fail() { echo "power-auto-test: $*" >&2; exit 1; }

supply() { # tree name type [online|scope=value]...
  local dir="$work/$1/class/power_supply/$2"
  mkdir -p "$dir"
  echo "$3" >"$dir/type"
  shift 3
  local kv
  for kv in "$@"; do echo "${kv#*=}" >"$dir/${kv%%=*}"; done
}

expect() { # tree want
  local got
  got=$(SUBCULT_SYSFS="$work/$1" "$cmd" --dry-run)
  [[ $got == "$2" ]] || fail "$1: got '$got', want '$2'"
}

supply laptop-ac BAT0 Battery; supply laptop-ac AC Mains online=1
supply laptop-battery BAT0 Battery; supply laptop-battery AC Mains online=0
supply usb-c BAT0 Battery; supply usb-c ucsi USB online=1
supply desktop AC Mains online=1
supply desktop-mouse AC Mains online=1; supply desktop-mouse hidpp Battery scope=Device

expect laptop-ac "would set balanced"
expect laptop-battery "would set power-saver"
expect usb-c "would set balanced"
expect desktop "no system battery; profile unchanged"
expect desktop-mouse "no system battery; profile unchanged"
# The udev rule: two events arrive together when a USB-C charger is pulled.
# A fixed transient unit name makes systemd refuse the second run while the
# first is loaded, so the rule must not name one, and the runs share a lock.
rules="$root/default/system/power-profile.rules"
! grep -v '^#' "$rules" | grep -q -- '--unit=' || { echo "power-auto-test: the udev rule names its transient unit; a second event would be dropped" >&2; exit 1; }
[[ $(grep -v '^#' "$rules" | grep -c '/usr/bin/flock /run/subcult-power-auto.lock /usr/bin/subcult-power-auto"$') == 2 ]] ||
  { echo "power-auto-test: both udev rules must run subcult-power-auto under the shared lock" >&2; exit 1; }
echo "power-auto-test: ok"
