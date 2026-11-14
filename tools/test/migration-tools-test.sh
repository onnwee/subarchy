#!/usr/bin/env bash
# The usbutils/inotify-tools/rtkit migration (#198), with stand-ins for sudo
# and pacman: it installs only the missing packages through sudo, does nothing
# when all are there (a new install), and stays pending when sudo or pacman
# fails.
set -euo pipefail

root=$(git rev-parse --show-toplevel)
migration=$root/migrations/1794690530.sh
fail() { echo "migration-tools-test: $*" >&2; exit 1; }
work=$(mktemp -d)
trap 'rm -rf -- "$work"' EXIT
mkdir -p "$work/bin"
export MIG_TEST="$work"
bash=$(command -v bash)

cat >"$work/bin/sudo" <<'STUB'
#!/bin/bash
[[ ! -e $MIG_TEST/sudo-refuses ]] || exit 1
echo "sudo $*" >>"$MIG_TEST/log"
exec "$@"
STUB
# pacman -T prints the packages not in $MIG_TEST/installed and exits 127 if any.
cat >"$work/bin/pacman" <<'STUB'
#!/bin/bash
if [[ $1 == -T ]]; then
  shift
  rc=0
  have=; [[ ! -e $MIG_TEST/installed ]] || have=$(<"$MIG_TEST/installed")
  for p; do [[ $'\n'$have$'\n' == *$'\n'$p$'\n'* ]] || { echo "$p"; rc=127; }; done
  exit $rc
fi
[[ ! -e $MIG_TEST/pacman-fails ]] || exit 1
echo "pacman $*" >>"$MIG_TEST/calls"
STUB
chmod +x "$work"/bin/*

fresh() { rm -f "$work"/{sudo-refuses,pacman-fails,calls,log,installed}; }
run() { PATH="$work/bin" "$bash" -euo pipefail "$migration" >/dev/null 2>&1; }
calls() { cat "$work/calls" 2>/dev/null || true; }

# All three missing: installed together through sudo.
fresh
run || fail "the migration failed"
[[ $(calls) == 'pacman -S --needed --noconfirm usbutils inotify-tools rtkit' ]] || fail "all missing: $(calls)"
[[ $(cat "$work/log") == 'sudo pacman -S --needed --noconfirm usbutils inotify-tools rtkit' ]] ||
  fail "not through sudo: $(cat "$work/log")"

# Only rtkit missing: only rtkit installed.
fresh
printf '%s\n' usbutils inotify-tools >"$work/installed"
run || fail "the migration failed with two installed"
[[ $(calls) == 'pacman -S --needed --noconfirm rtkit' ]] || fail "one missing: $(calls)"

# All installed (a new install): nothing to do.
fresh
printf '%s\n' usbutils inotify-tools rtkit >"$work/installed"
run || fail "the migration failed with everything installed"
[[ -z $(calls) ]] || fail "packages installed: $(calls)"

# sudo refused or pacman failing: the migration fails, so it stays pending.
fresh
touch "$work/sudo-refuses"
if run; then fail "a refused sudo did not leave the migration pending"; fi
fresh
touch "$work/pacman-fails"
if run; then fail "a failed pacman did not leave the migration pending"; fi

# A new install gets them from an install list.
for p in usbutils inotify-tools rtkit; do
  grep -qx "$p" "$root"/install/packages/*.txt || fail "no install list names $p"
done
echo "migration-tools-test: ok"
