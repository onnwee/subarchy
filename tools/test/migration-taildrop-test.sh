#!/usr/bin/env bash
# The Taildrop receiver migration, with stand-ins for sudo, systemctl and
# tailscale: it enables the user's instance of subcult-taildrop@ (escaped,
# so a dash in the name survives), starts it only while tailscaled runs,
# does nothing when the unit is already enabled or tailscale is missing,
# and stays pending when sudo refuses. It never makes anyone tailscaled's
# operator (ADR 0062).
set -euo pipefail

root=$(git rev-parse --show-toplevel)
migration=$root/migrations/1794551931.sh
fail() { echo "migration-taildrop-test: $*" >&2; exit 1; }
work=$(mktemp -d)
trap 'rm -rf -- "$work"' EXIT
mkdir -p "$work/bin"
export MIG_TEST="$work" PATH="$work/bin:$PATH"

cat >"$work/bin/sudo" <<'STUB'
#!/bin/bash
[[ ! -e $MIG_TEST/sudo-refuses ]] || exit 1
echo "sudo $*" >>"$MIG_TEST/log"
exec "$@"
STUB
cat >"$work/bin/systemctl" <<'STUB'
#!/bin/bash
case $1 in
is-enabled) [[ -e $MIG_TEST/enabled ]];;
is-active) [[ -e $MIG_TEST/tailscaled-active ]];;
enable) echo "enable ${*: -1}" >>"$MIG_TEST/calls"; touch "$MIG_TEST/enabled";;
start) echo "start ${*: -1}" >>"$MIG_TEST/calls";;
*) exit 2;;
esac
STUB
cat >"$work/bin/tailscale" <<'STUB'
#!/bin/sh
echo "tailscale $*" >>"$MIG_TEST/calls"
STUB
chmod +x "$work/bin/sudo" "$work/bin/systemctl" "$work/bin/tailscale"

fresh() { rm -f "$work"/{enabled,tailscaled-active,sudo-refuses,calls,log}; }
run() { USER=$1 bash -euo pipefail "$migration" >/dev/null; }
calls() { cat "$work/calls" 2>/dev/null || true; }

# tailscaled running: enabled and started now, as root.
fresh
touch "$work/tailscaled-active"
run alice || fail "the migration failed"
[[ $(calls) == $'enable subcult-taildrop@alice.service\nstart subcult-taildrop@alice.service' ]] ||
  fail "running tailscaled: $(calls)"
[[ $(grep -c '^sudo systemctl' "$work/log") == 2 ]] || fail "not through sudo: $(cat "$work/log")"

# A dash in the user name is escaped for the instance (%I gives it back).
fresh
run jo-ann || fail "the migration failed for jo-ann"
[[ $(calls) == 'enable subcult-taildrop@jo\x2dann.service' ]] || fail "escaping: $(calls)"

# tailscaled stopped: enabled for the next boot, nothing started.
fresh
run alice || fail "the migration failed with tailscaled stopped"
[[ $(calls) == 'enable subcult-taildrop@alice.service' ]] || fail "stopped tailscaled: $(calls)"

# Already enabled (a new install): nothing to enable.
fresh
touch "$work/enabled"
run alice || fail "the migration failed when already enabled"
[[ -z $(calls) ]] || fail "already enabled: $(calls)"

# sudo refused: the migration fails, so it stays pending.
fresh
touch "$work/sudo-refuses"
if run alice 2>/dev/null; then fail "a refused sudo did not leave the migration pending"; fi

# No tailscale (a PATH with only the stand-ins and systemd-escape): nothing
# to do.
fresh
mkdir "$work/notail"
cp "$work/bin/sudo" "$work/bin/systemctl" "$work/notail/"
ln -s "$(command -v systemd-escape)" "$work/notail/systemd-escape"
USER=alice PATH="$work/notail" /bin/bash -euo pipefail "$migration" || fail "the migration failed without tailscale"
[[ -z $(calls) ]] || fail "without tailscale: $(calls)"

# Nothing in Subarchy makes an account tailscaled's operator (ADR 0062):
# no operator flag for `tailscale set`, `up` or `login`, in any position.
if git -C "$root" grep -nE -- '--operator(=|[[:space:]]|$)' -- ':!docs' ':!tools/test/tailscale-helper-test.sh' \
  ':!shell/widgets/tailscale/tests'; then
  fail "something sets tailscaled's operator"
fi
echo "migration-taildrop-test: ok"
