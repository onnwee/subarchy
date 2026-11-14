#!/usr/bin/env bash
# The hostname migration, with stand-ins for sudo and pacman: it installs
# inetutils through sudo when hostname is missing, does nothing when it is there
# (a new install), and stays pending when sudo or pacman fails.
set -euo pipefail

root=$(git rev-parse --show-toplevel)
migration=$root/migrations/1794684878.sh
fail() { echo "migration-hostname-test: $*" >&2; exit 1; }
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
cat >"$work/bin/pacman" <<'STUB'
#!/bin/bash
[[ ! -e $MIG_TEST/pacman-fails ]] || exit 1
echo "pacman $*" >>"$MIG_TEST/calls"
STUB
chmod +x "$work/bin/sudo" "$work/bin/pacman"

fresh() { rm -f "$work"/{sudo-refuses,pacman-fails,calls,log} "$work/bin/hostname"; }
# Only the stand-ins on PATH: a hostname on the host must not count.
run() { PATH="$work/bin" "$bash" -euo pipefail "$migration" >/dev/null 2>&1; }
calls() { cat "$work/calls" 2>/dev/null || true; }

# Missing: installed through sudo.
fresh
run || fail "the migration failed"
[[ $(calls) == 'pacman -S --needed --noconfirm inetutils' ]] || fail "missing hostname: $(calls)"
[[ $(cat "$work/log") == 'sudo pacman -S --needed --noconfirm inetutils' ]] || fail "not through sudo: $(cat "$work/log")"

# Already installed (a new install): nothing to do.
fresh
printf '#!/bin/sh\n' >"$work/bin/hostname"
chmod +x "$work/bin/hostname"
run || fail "the migration failed with hostname installed"
[[ -z $(calls) ]] || fail "inetutils installed: $(calls)"

# sudo refused or pacman failing: the migration fails, so it stays pending.
fresh
touch "$work/sudo-refuses"
if run; then fail "a refused sudo did not leave the migration pending"; fi
fresh
touch "$work/pacman-fails"
if run; then fail "a failed pacman did not leave the migration pending"; fi

# A new install gets inetutils from an install list.
grep -qx inetutils "$root/install/packages/base.txt" || fail "no install list names inetutils"
echo "migration-hostname-test: ok"
