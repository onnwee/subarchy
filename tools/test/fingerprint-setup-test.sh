#!/usr/bin/env bash
# `subcult setup fingerprint` against stand-ins for sudo, pacman, fprintd's
# tools and `subcult hw`: it installs fprintd only where a reader is, stops
# before enrolling when fprintd finds none, enrolls before it verifies, and
# `remove` deletes the enrolled fingers. PATH holds only the stand-ins and
# the few tools the script needs, so a real fprintd is never reached.
# shellcheck disable=SC2016 # the stand-ins' bodies expand when they run
set -euo pipefail

root=$(git rev-parse --show-toplevel)
fail() { echo "fingerprint-setup-test: $*" >&2; exit 1; }
[[ $EUID -ne 0 ]] || { echo "fingerprint-setup-test: the command refuses root, skipped"; exit 0; }
work=$(mktemp -d)
trap 'rm -rf -- "$work"' EXIT
mkdir -p "$work/bin" "$work/sys" "$work/fprintd"
for tool in bash id ln; do
  ln -s "$(command -v "$tool")" "$work/sys/$tool"
done
export FP_TEST="$work"

# name, body, directory (bin by default): each call is logged.
stub() {
  printf '#!/usr/bin/env bash\necho "%s $*" >>"$FP_TEST/calls"\n%s\n' "$1" "$2" >"$work/${3:-bin}/$1"
  chmod +x "$work/${3:-bin}/$1"
}
stub sudo '"$@"'
stub subcult '[[ -e $FP_TEST/reader ]]'
# Installing fprintd puts its tools on PATH.
stub pacman 'for t in "$FP_TEST"/fprintd/*; do ln -sf "$t" "$FP_TEST/bin/"; done'
# Like fprintd 1.94: the list names each enrolled finger; enroll -f FINGER adds it.
stub fprintd-list 'if [[ -e $FP_TEST/no-devices ]]; then echo "No devices available"; exit 1; fi
if [[ -s $FP_TEST/enrolled ]]; then echo "Fingerprints for user x on Reader (press):"; n=0
  while read -r f; do echo " - #$n: $f"; n=$((n + 1)); done <"$FP_TEST/enrolled"; exit 0; fi
echo "User x has no fingers enrolled for Reader."' fprintd
stub fprintd-enroll '[[ ! -e $FP_TEST/enroll-fails && $1 == -f && -n $2 ]] && echo "$2" >>"$FP_TEST/enrolled"' fprintd
stub fprintd-verify '' fprintd
stub fprintd-delete '' fprintd

fresh() { # no fprintd; "reader" plugs one in
  rm -f "$work/calls" "$work/reader" "$work/enrolled" "$work"/bin/fprintd-*
  : >"$work/calls"
  [[ ${1:-} != reader ]] || : >"$work/reader"
}
run() { PATH="$work/bin:$work/sys" "$root/bin/subcult-setup-fingerprint" "$@" >"$work/out" 2>&1; }
line() { grep -n -m1 -- "$1" "$work/calls" | cut -d: -f1; }
called() { grep -q -- "$1" "$work/calls"; }

# No reader: nothing is installed or enrolled.
fresh
run && fail "a machine without a reader was set up"
grep -q 'no fingerprint reader' "$work/out" || fail "no reason given: $(<"$work/out")"
called pacman && fail "fprintd was installed without a reader"

# A reader: fprintd is installed, then the finger enrolled, then checked.
fresh reader
run || fail "setup with a reader failed: $(<"$work/out")"
called 'pacman -S --needed --noconfirm fprintd' || fail "fprintd was not installed"
grep -q '^sudo fprintd-enroll' "$work/calls" || fail "enrollment did not run through sudo"
(($(line 'fprintd-enroll') > $(line 'pacman'))) || fail "enrolled before fprintd was installed"
(($(line 'fprintd-verify') > $(line 'fprintd-enroll'))) || fail "verified before enrolling: $(tr '\n' ';' <"$work/calls")"
grep -q 'password still works' "$work/out" || fail "the result does not say the password still works"
called 'fprintd-enroll -f right-index-finger' || fail "the first finger was not asked for by name: $(tr '\n' ';' <"$work/calls")"
grep -q 'Enrolled: right-index-finger' "$work/out" || fail "the result does not say which finger was enrolled: $(<"$work/out")"

# Again with fprintd in place: it is not installed twice, and the next
# finger is added rather than the first one replaced.
: >"$work/calls"
run || fail "a second setup failed: $(<"$work/out")"
called pacman && fail "fprintd was installed again"
called 'fprintd-enroll -f left-index-finger' || fail "the second run did not pick the next finger: $(tr '\n' ';' <"$work/calls")"
grep -q 'Enrolled: right-index-finger left-index-finger' "$work/out" || fail "both fingers are not listed: $(<"$work/out")"

# All ten enrolled: it stops before enrolling.
printf '%s\n' right-index-finger left-index-finger right-middle-finger left-middle-finger right-thumb \
  left-thumb right-ring-finger left-ring-finger right-little-finger left-little-finger >"$work/enrolled"
: >"$work/calls"
run && fail "an eleventh finger was enrolled"
called fprintd-enroll && fail "enrolled with every finger taken"
grep -q 'all ten fingers' "$work/out" || fail "no reason given: $(<"$work/out")"
: >"$work/enrolled"

# fprintd installed but no reader it can drive: stop before enrolling.
: >"$work/calls"
: >"$work/no-devices"
run && fail "setup went on without a usable reader"
called fprintd-enroll && fail "enrolled without a usable reader"
grep -q 'no reader it can use' "$work/out" || fail "no reason given: $(<"$work/out")"
rm "$work/no-devices"

# A failed enrollment is not verified.
: >"$work/calls"
: >"$work/enroll-fails"
run && fail "a failed enrollment passed"
called fprintd-verify && fail "verified after a failed enrollment"
rm "$work/enroll-fails"

# remove deletes the fingers through sudo; without fprintd there is nothing to do.
: >"$work/calls"
run remove || fail "remove failed: $(<"$work/out")"
grep -q '^sudo fprintd-delete' "$work/calls" || fail "remove did not delete the fingers"
fresh
run remove || fail "remove without fprintd failed"
called sudo && fail "remove without fprintd ran sudo"
run bogus && fail "an unknown argument was accepted"

echo "fingerprint-setup-test: PASS"
