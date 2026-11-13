#!/usr/bin/env bash
# Native lock-view focus recovery; no session lock or real password is used.
set -euo pipefail
root=$(git rev-parse --show-toplevel)
if ! command -v quickshell >/dev/null; then
  [[ -z ${CI:-} ]] || { echo 'lock-focus-test: quickshell missing' >&2; exit 1; }
  echo 'lock-focus-test: quickshell missing, skipped'
  exit 0
fi
work=$(mktemp -d)
trap 'rm -rf -- "$work"' EXIT
mkdir -p "$work/lock" "$work/run"
chmod 700 "$work/run"
cp "$root/lock/"{LockView.qml,LockModel.js,FingerprintModel.js} "$work/lock/"
"$root/tools/branding/lockup-png.sh" 720 "$work/lock/lockup-dark.png"
cp "$root/tools/test/lock-focus.qml" "$work/shell.qml"
# A short loop for the still/loop check.
ffmpeg -loglevel error -f lavfi -i color=c=0x100b19:s=64x36:d=2 -c:v libvpx-vp9 "$work/lock/loop.webm"
export QT_QPA_PLATFORM=offscreen QT_QUICK_BACKEND=software XDG_RUNTIME_DIR="$work/run" LOCK_TEST_VIDEO="$work/lock/loop.webm"
status=0
quickshell --no-duplicate -p "$work" >"$work/log" 2>&1 || status=$?
if ((status)) || ! grep -q 'PASS: lock focus' "$work/log"; then cat "$work/log"; exit 1; fi
if grep -Eq 'ReferenceError|TypeError|Unable to assign|Cannot assign|Failed to load configuration' "$work/log"; then cat "$work/log"; exit 1; fi
echo 'lock-focus-test: PASS (click, Tab, activation and password key handling, hidden pointer, still art only without a loop, fingerprint line only with a reader)'
