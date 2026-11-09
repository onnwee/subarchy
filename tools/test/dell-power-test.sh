#!/usr/bin/env bash
# Checks bin/subcult-dell-power against a fake sysfs tree and a stub
# powerprofilesctl.
set -euo pipefail

root=$(git rev-parse --show-toplevel)
cmd="$root/bin/subcult-dell-power"
work=$(mktemp -d)
cleanup() { rm -r -- "$work"; }
trap cleanup EXIT
fail() { echo "dell-power-test: $*" >&2; exit 1; }

# A Dell with the four firmware profiles and the charging controls.
dell="$work/dell/class"
mkdir -p "$dell/platform-profile/platform-profile-0" "$dell/firmware-attributes/dell-wmi-sysman/attributes"/{PrimaryBattChargeCfg,CustomChargeStart,CustomChargeStop}
echo dell-pc >"$dell/platform-profile/platform-profile-0/name"
echo "quiet cool balanced performance" >"$dell/platform-profile/platform-profile-0/choices"
echo balanced >"$dell/platform-profile/platform-profile-0/profile"
attrs="$dell/firmware-attributes/dell-wmi-sysman/attributes"
echo Adaptive >"$attrs/PrimaryBattChargeCfg/current_value"
echo "Adaptive;Standard;Express;PrimAcUse;Custom" >"$attrs/PrimaryBattChargeCfg/possible_values"
for kv in current_value=50 min_value=50 max_value=95 scalar_increment=5; do echo "${kv#*=}" >"$attrs/CustomChargeStart/${kv%%=*}"; done
for kv in current_value=80 min_value=55 max_value=100 scalar_increment=5; do echo "${kv#*=}" >"$attrs/CustomChargeStop/${kv%%=*}"; done
# A machine without the firmware.
mkdir -p "$work/other/class/platform-profile/platform-profile-0"
echo thinkpad-acpi >"$work/other/class/platform-profile/platform-profile-0/name"

mkdir -p "$work/bin"
cat >"$work/bin/powerprofilesctl" <<'STUB'
#!/bin/sh
case $1 in
  get) cat "$PPD_STATE" 2>/dev/null || echo balanced ;;
  set) echo "$2" >"$PPD_STATE" ;;
esac
STUB
chmod +x "$work/bin/powerprofilesctl"
export PATH="$work/bin:$PATH" PPD_STATE="$work/ppd"

run() { SUBCULT_SYSFS="$work/$1" "$cmd" "${@:2}"; }

run dell probe || fail "probe did not find the Dell profile"
run other probe && fail "probe found a profile on the other machine"
[[ $(run other state --json) == '{"available": false}' ]] || fail "other state: $(run other state --json)"

st=$(run dell state --json)
python3 -c '
import json, sys
d = json.loads(sys.argv[1])
assert d["available"] and [p["id"] for p in d["profiles"]] == ["quiet", "cool", "balanced", "performance"], d
assert [p["id"] for p in d["profiles"] if p["active"]] == ["balanced"], d
assert [m["id"] for m in d["charging"]["modes"]] == ["adaptive", "standard", "express", "primarily-ac", "custom"], d
assert [m["id"] for m in d["charging"]["modes"] if m["active"]] == ["adaptive"], d
assert d["charging"]["custom"] == {"start": 50, "stop": 80, "startMin": 50, "startMax": 95, "stopMin": 55, "stopMax": 100, "step": 5}, d
' "$st" || fail "state --json: $st"

[[ $(run dell set quiet) == "set quiet (power-profiles-daemon: power-saver)" ]] || fail "set quiet"
[[ $(<"$dell/platform-profile/platform-profile-0/profile") == quiet && $(<"$work/ppd") == power-saver ]] || fail "quiet did not reach the firmware and the daemon"
run dell set performance >/dev/null
[[ $(<"$work/ppd") == performance ]] || fail "performance did not reach the daemon"
run dell set turbo 2>"$work/err" && fail "an unknown profile was accepted"
grep -q "does not offer 'turbo'" "$work/err" || fail "unknown profile message: $(cat "$work/err")"
run other set quiet 2>/dev/null && fail "set worked without the firmware"

[[ $(run dell charging set express) == "set charging express" ]] || fail "charging set express"
[[ $(<"$attrs/PrimaryBattChargeCfg/current_value") == Express ]] || fail "express did not reach the firmware"
[[ $(run dell charging set custom 60 90) == "set charging custom 60-90" ]] || fail "charging set custom"
[[ $(<"$attrs/PrimaryBattChargeCfg/current_value") == Custom && $(<"$attrs/CustomChargeStart/current_value") == 60 && $(<"$attrs/CustomChargeStop/current_value") == 90 ]] || fail "custom thresholds did not reach the firmware"
# A start above the old stop minus the gap: the stop is written first, so
# both land.
run dell charging set custom 90 95 >/dev/null
[[ $(<"$attrs/CustomChargeStart/current_value") == 90 && $(<"$attrs/CustomChargeStop/current_value") == 95 ]] || fail "widening the gap first failed"
run dell charging set custom 80 80 2>"$work/err" && fail "a gap under 5 was accepted"
grep -q "at least 5 above" "$work/err" || fail "gap message: $(cat "$work/err")"
run dell charging set custom 52 80 2>"$work/err" && fail "an off-step start was accepted"
run dell charging set custom 40 80 2>"$work/err" && fail "a start under the minimum was accepted"
run dell charging set standard 60 80 2>"$work/err" && fail "thresholds were accepted for a fixed mode"
run dell charging set turbo 2>/dev/null && fail "an unknown mode was accepted"

# Without write permission the message names the udev rule.
chmod a-w "$dell/platform-profile/platform-profile-0/profile"
run dell set quiet 2>"$work/err" && fail "a read-only profile was written"
grep -q "not writable" "$work/err" || fail "read-only message: $(cat "$work/err")"
chmod u+w "$dell/platform-profile/platform-profile-0/profile"

echo "dell-power-test: ok"
