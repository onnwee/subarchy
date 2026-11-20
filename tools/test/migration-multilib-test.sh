#!/usr/bin/env bash
# The multilib migration, with stand-ins for sudo, subcult-channel and
# pacman: it sets the current channel again through sudo (which enables
# [multilib]), syncs when multilib's database is missing, leaves a system on
# no channel alone, and stays pending when sudo or pacman fails.
set -euo pipefail

root=$(git rev-parse --show-toplevel)
migration=$root/migrations/1795206595.sh
fail() { echo "migration-multilib-test: $*" >&2; exit 1; }
work=$(mktemp -d)
trap 'rm -rf -- "$work"' EXIT
mkdir -p "$work/bin" "$work/root/var/lib/pacman/sync"
export MIG_TEST="$work"
bash=$(command -v bash)

cat >"$work/bin/sudo" <<'STUB'
#!/bin/bash
[[ ! -e $MIG_TEST/sudo-refuses ]] || exit 1
exec "$@"
STUB
cat >"$work/bin/subcult-channel" <<'STUB'
#!/bin/bash
if (($# == 0)); then echo "$(<"$MIG_TEST/channel")"; exit 0; fi
echo "subcult-channel $*" >>"$MIG_TEST/calls"
STUB
cat >"$work/bin/pacman" <<'STUB'
#!/bin/bash
[[ ! -e $MIG_TEST/pacman-fails ]] || exit 1
echo "pacman $*" >>"$MIG_TEST/calls"
STUB
chmod +x "$work/bin/sudo" "$work/bin/subcult-channel" "$work/bin/pacman"

fresh() {
  rm -f "$work"/{sudo-refuses,pacman-fails,calls} "$work/root/var/lib/pacman/sync/multilib.db"
  echo "$1" >"$work/channel"
}
run() { PATH="$work/bin" SUBCULT_TEST_ROOT="$work/root" "$bash" -euo pipefail "$migration" >/dev/null 2>&1; }
calls() { cat "$work/calls" 2>/dev/null || true; }

# Stable, no multilib database yet: set again, then a full sync.
fresh "stable (snapshot 2026/11/08)"
run || fail "the migration failed"
[[ $(calls) == $'subcult-channel set stable --quiet\npacman -Syu --noconfirm' ]] || fail "stable: $(calls)"

# Edge keeps edge.
fresh "edge (the Arch mirrors directly)"
run || fail "the migration failed on edge"
[[ $(calls) == $'subcult-channel set edge --quiet\npacman -Syu --noconfirm' ]] || fail "edge: $(calls)"

# Multilib's database already there (enabled by hand): set, no sync.
fresh "stable (snapshot 2026/11/08)"
touch "$work/root/var/lib/pacman/sync/multilib.db"
run || fail "the migration failed with a multilib database"
[[ $(calls) == 'subcult-channel set stable --quiet' ]] || fail "synced again: $(calls)"

# No channel: nothing.
fresh "unset (the mirrors directly; run \`subcult channel set stable\`)"
run || fail "the migration failed on no channel"
[[ -z $(calls) ]] || fail "no channel was changed: $(calls)"

# sudo refused or pacman failing: the migration fails, so it stays pending.
fresh "stable (snapshot 2026/11/08)"
touch "$work/sudo-refuses"
if run; then fail "a refused sudo did not leave the migration pending"; fi
fresh "stable (snapshot 2026/11/08)"
touch "$work/pacman-fails"
if run; then fail "a failed sync did not leave the migration pending"; fi

echo "migration-multilib-test: ok"
