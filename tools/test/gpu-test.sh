#!/usr/bin/env bash
# Checks bin/subcult-gpu-{env,run,mode} against fake sysfs and /dev trees.
set -euo pipefail

root=$(git rev-parse --show-toplevel)
work=$(mktemp -d)
cleanup() { rm -r -- "$work"; }
trap cleanup EXIT
fail() { echo "gpu-test: $*" >&2; exit 1; }

# machine NAME [hybrid] [battery|desktop] [ac|noac] [connectors...]
machine() {
  local m="$work/$1" kind=$2 power=$3 ac=$4
  shift 4
  mkdir -p "$m/dev/dri" "$m/sys/class/power_supply" "$m/sys/class/drm" "$m/icd"
  touch "$m/dev/dri/subcult-igpu" "$m/icd/intel_icd.json"
  [[ $kind == hybrid ]] && touch "$m/dev/dri/subcult-dgpu"
  if [[ $power == battery ]]; then
    mkdir -p "$m/sys/class/power_supply/BAT0" "$m/sys/class/power_supply/AC"
    echo Battery >"$m/sys/class/power_supply/BAT0/type"
    echo Mains >"$m/sys/class/power_supply/AC/type"
    [[ $ac == ac ]] && echo 1 >"$m/sys/class/power_supply/AC/online" || echo 0 >"$m/sys/class/power_supply/AC/online"
  fi
  local c
  for c in "$@"; do
    mkdir -p "$m/sys/class/drm/card1-$c"
    echo connected >"$m/sys/class/drm/card1-$c/status"
  done
  mkdir -p "$m/sys/class/drm/card1-DP-9"
  echo disconnected >"$m/sys/class/drm/card1-DP-9/status"
}

genv() { # NAME [state]
  local m="$work/$1"
  [[ -n ${2:-} ]] && echo "$2" >"$m/state"
  SUBCULT_SYSFS="$m/sys" SUBCULT_DEV="$m/dev" SUBCULT_ICD_DIR="$m/icd" SUBCULT_GPU_STATE="$m/state" \
    "$root/bin/subcult-gpu-env" 2>"$m/stderr"
}

machine intel-only single battery ac eDP-1 DP-1 DP-2
[[ -z $(genv intel-only nvidia) ]] || fail "non-hybrid machine printed an environment"

machine laptop hybrid battery ac eDP-1
out=$(genv laptop)
[[ $out == *"SUBCULT_GPU_MODE=intel"* && $out == *"AQ_DRM_DEVICES=$work/laptop/dev/dri/subcult-igpu"* &&
  $out == *"VK_DRIVER_FILES=$work/laptop/icd/intel_icd.json"* && $out == *"50_mesa.json"* ]] || fail "default intel: $out"

machine docked hybrid battery ac eDP-1 DP-1 DVI-I-1
out=$(genv docked nvidia)
[[ $out == *"SUBCULT_GPU_MODE=nvidia"* && $out == *"subcult-dgpu:$work/docked/dev/dri/subcult-igpu"* &&
  $out != *VK_DRIVER_FILES* ]] || fail "docked nvidia: $out"

machine unplugged hybrid battery noac eDP-1 DP-1 DP-2
out=$(genv unplugged nvidia)
[[ $out == *"SUBCULT_GPU_MODE=intel"* ]] || fail "battery should fall back to intel: $out"
grep -q "needs AC" "$work/unplugged/stderr" || fail "no fallback message"

machine one-screen hybrid battery ac eDP-1 HDMI-A-1
[[ $(genv one-screen nvidia) == *"SUBCULT_GPU_MODE=intel"* ]] || fail "one external monitor should stay intel"

machine desktop hybrid desktop - DP-1 DP-2
[[ $(genv desktop nvidia) == *"SUBCULT_GPU_MODE=nvidia"* ]] || fail "desktop with two monitors should allow nvidia"

# A desktop with its monitor on the NVIDIA card: the integrated GPU has no
# connected output, so Intel mode would give no picture.
machine tower hybrid desktop -
rm "$work/tower/dev/dri/subcult-igpu" "$work/tower/dev/dri/subcult-dgpu"
touch "$work/tower/dev/dri/card0" "$work/tower/dev/dri/card1"
ln -s card0 "$work/tower/dev/dri/subcult-igpu"
ln -s card1 "$work/tower/dev/dri/subcult-dgpu"
mkdir -p "$work/tower/sys/class/drm/card1-DP-1" "$work/tower/sys/class/drm/card0-HDMI-A-1"
echo connected >"$work/tower/sys/class/drm/card1-DP-1/status"
echo disconnected >"$work/tower/sys/class/drm/card0-HDMI-A-1/status"
out=$(genv tower)
[[ $out == *"SUBCULT_GPU_MODE=nvidia"* && $out == *"AQ_DRM_DEVICES=$work/tower/dev/dri/subcult-dgpu:"* ]] ||
  fail "monitor on the NVIDIA card must start in NVIDIA mode: $out"
grep -q "on the NVIDIA card" "$work/tower/stderr" || fail "no message for the NVIDIA-wired desktop"
# The same cards with the monitor moved to the integrated GPU stay in Intel mode.
echo connected >"$work/tower/sys/class/drm/card0-HDMI-A-1/status"
[[ $(genv tower) == *"SUBCULT_GPU_MODE=intel"* ]] || fail "a monitor on the integrated GPU keeps Intel mode"

# gpu.rules: udev matches a rule's ATTRS keys all on one parent device. Walk a
# fake parent chain the same way and list the links each card gets.
links() { # PARENT... each "vendor class boot_vga", nearest first
  local line keys parent got=() ok k v
  local -A have
  while IFS= read -r line; do
    [[ $line == SUBSYSTEM* ]] || continue
    keys=$(grep -o 'ATTRS{[a-z_]*}=="[^"]*"' <<<"$line")
    for parent in "$@"; do
      read -r "have[vendor]" "have[class]" "have[boot_vga]" <<<"$parent"
      ok=1
      while IFS= read -r k; do
        v=${k#*==\"} v=${v%\"} k=${k#ATTRS\{} k=${k%%\}*}
        # shellcheck disable=SC2053 # udev values are glob patterns
        [[ ${have[$k]:-} == $v ]] || ok=
      done <<<"$keys"
      [[ -n $ok ]] && { got+=("${line##*SYMLINK+=\"dri/}"); break; }
    done
  done <"$root/default/system/gpu.rules"
  echo "${got[*]//\"/}"
}
[[ $(links "0x10de 0x030200 -" "0x8086 0x060400 -") == subcult-dgpu ]] ||
  fail "an NVIDIA card behind an Intel root port also matched the Intel rule (#194)"
[[ $(links "0x8086 0x030000 1" "0x8086 0x060000 -") == subcult-igpu ]] || fail "intel igpu"
[[ $(links "0x1002 0x030000 1" "0x1022 0x060400 -") == subcult-igpu ]] || fail "amd boot igpu"
[[ -z $(links "0x1002 0x030000 0" "0x1022 0x060400 -") ]] || fail "non-boot amd card got a link"

out=$(__EGL_VENDOR_LIBRARY_FILENAMES=x VK_DRIVER_FILES=y "$root/bin/subcult-gpu-run" env)
[[ $out == *"__NV_PRIME_RENDER_OFFLOAD=1"* && $out != *"VK_DRIVER_FILES="* && $out != *"__EGL_VENDOR_LIBRARY_FILENAMES="* ]] ||
  fail "gpu run environment"
if "$root/bin/subcult-gpu-run" >/dev/null 2>&1; then fail "gpu run without a command"; fi

state="$work/mode/state"
SUBCULT_GPU_STATE=$state "$root/bin/subcult-gpu-mode" nvidia >/dev/null
[[ $(<"$state") == nvidia ]] || fail "gpu mode did not record nvidia"
[[ $(SUBCULT_GPU_STATE=$state "$root/bin/subcult-gpu-mode") == *"chosen:  nvidia"* ]] || fail "gpu mode status"
if SUBCULT_GPU_STATE=$state "$root/bin/subcult-gpu-mode" amd >/dev/null 2>&1; then fail "gpu mode accepted amd"; fi

echo "gpu-test: ok"
