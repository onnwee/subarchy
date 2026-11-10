#!/usr/bin/env bash
# Runs the session commands through the dispatcher against stubbed
# systemctl and uwsm, and checks the flags the launcher reads: the three
# that end the session ask first, and none opens a terminal.
set -euo pipefail

bin=$(realpath "${1:?usage: system-session-test.sh path/to/subcult}")
root=$(git rev-parse --show-toplevel)
work=$(mktemp -d)
cleanup() { rm -r -- "$work"; }
trap cleanup EXIT
fail() { echo "system-session-test: $*" >&2; exit 1; }

for tool in systemctl uwsm; do
  printf '#!/bin/sh\necho "%s $*" >>"%s/calls"\n' "$tool" "$work" >"$work/$tool"
  chmod +x "$work/$tool"
done
export PATH="$work:$root/bin:$PATH"

expect() { # action want
  : >"$work/calls"
  "$bin" system "$1" || fail "$1 exited $?"
  [[ $(<"$work/calls") == "$2" ]] || fail "$1 ran '$(<"$work/calls")', want '$2'"
}
expect suspend "systemctl suspend"
expect logout "uwsm stop"
expect reboot "systemctl reboot"
expect shutdown "systemctl poweroff"

"$bin" commands --json | python3 -c '
import json, sys
c = {x["route"]: x for x in json.load(sys.stdin)["commands"]}
for action, dangerous in (("suspend", False), ("logout", True), ("reboot", True), ("shutdown", True)):
    x = c["subcult system " + action]
    assert x["silent"] is True, action + " would open a terminal"
    assert x["dangerous"] is dangerous, action + " dangerous=" + str(x["dangerous"])
    assert x["summary"], action + " has no summary"
' || fail "commands --json flags"
echo "system-session-test: ok"
