#!/usr/bin/env bash
# Compile and exercise the shipped SDDM QML against a fake SDDM context.
# Optional argument keeps the rendered previews (1280x800, 2560x1440, 320x480
# and the error, locked, busy and Caps Lock states).
set -euo pipefail
root=$(git rev-parse --show-toplevel)
qt=${QT6BIN:-/usr/lib/qt6/bin}
for tool in "$qt/qmltestrunner" rsvg-convert magick; do
  if ! command -v "$tool" >/dev/null; then
    [[ -z ${CI:-} ]] || { echo "greeter-test: $tool missing" >&2; exit 1; }
    echo "greeter-test: $tool missing, skipped"
    exit 0
  fi
done
artifacts=""
if [[ -n ${1:-} ]]; then
  mkdir -p -- "$1"
  artifacts=$(realpath "$1")
fi
work=$(mktemp -d)
trap 'rm -rf -- "$work"' EXIT
mkdir -p "$work/theme" "$work/tests" "$work/run"
chmod 700 "$work/run"
cp "$root/default/sddm/theme/Main.qml" "$work/theme/"
cp "$root/tools/test/greeter/tst_greeter.qml" "$work/tests/"
# Use the real brand fonts without installing anything into the host.
export FONTCONFIG_FILE="$root/branding/fontconfig.xml" XDG_RUNTIME_DIR="$work/run" QT_QUICK_BACKEND=software
"$root/tools/branding/lockup-png.sh" 2000 "$work/theme/lockup-dark.png"
cd "$work"
status=0
"$qt/qmltestrunner" -platform offscreen -input "$work/tests" >"$work/greeter-test.log" 2>&1 || status=$?
if grep -Eq 'QWARN|ReferenceError|TypeError|Unable to assign|Cannot assign' "$work/greeter-test.log"; then status=1; fi
if ((status == 0)); then
  magick "$work/greeter-wide.png" -format %c histogram:info:- >"$work/histogram.txt"
  green=$(awk '/#00[Ff][Ff]88/ { sum += $1 } END { print sum + 0 }' "$work/histogram.txt")
  if ((green < 8)); then
    echo 'FAIL: the rendered master mark is missing its green block' >>"$work/greeter-test.log"
    status=1
  fi
fi
if [[ -n $artifacts ]]; then
  cp "$work/greeter-test.log" "$artifacts/"
  for png in "$work"/greeter-*.png; do [[ ! -f $png ]] || cp "$png" "$artifacts/"; done
fi
if ((status)); then cat "$work/greeter-test.log"; exit "$status"; fi
grep '^Totals:' "$work/greeter-test.log"
echo 'greeter-test: PASS (keyboard, Escape, Caps Lock, mouse, authentication states, screen sizes and artwork)'
