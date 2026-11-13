#!/usr/bin/env bash
# The faillock migration, against a fake root with a stand-in for sudo: it
# adds Subarchy's deny and unlock_time to an existing faillock.conf and
# keeps every other line, copies Subarchy's file when there is none, leaves
# a file that sets either value alone, and stays pending when sudo refuses.
set -euo pipefail

root=$(git rev-parse --show-toplevel)
migration=$root/migrations/1794537409.sh
fail() { echo "migration-faillock-test: $*" >&2; exit 1; }
work=$(mktemp -d)
trap 'rm -rf -- "$work"' EXIT
mkdir -p "$work/bin"
export MIG_TEST="$work" PATH="$work/bin:$PATH"

cat >"$work/bin/sudo" <<'STUB'
#!/bin/bash
[[ ! -e $MIG_TEST/sudo-refuses ]] || exit 1
exec "$@"
STUB
chmod +x "$work/bin/sudo"

conf=$work/root/etc/security/faillock.conf
fresh() { # $1: the existing faillock.conf, or "none"
  rm -rf "$work/root" "$work/sudo-refuses"
  install -D -m 0644 "$root/default/security/faillock.conf" "$work/root/usr/share/subcult/default/security/faillock.conf"
  mkdir -p "$work/root/etc/security"
  [[ $1 == none ]] || printf '%s' "$1" >"$conf"
}
run() { SUBCULT_TEST_ROOT="$work/root" bash -euo pipefail "$migration"; }
value() { grep -E "^[[:space:]]*$1[[:space:]]*=" "$conf" | tr -d ' '; }

# Arch's stock file: every line a comment. The comments stay, the values land.
fresh $'# Configuration for locking the user after multiple failed\n# deny = 3\n# unlock_time = 600\n'
run || fail "the migration failed on the stock file"
[[ $(value deny) == deny=10 && $(value unlock_time) == unlock_time=120 ]] || fail "stock file: $(<"$conf")"
grep -q '^# deny = 3$' "$conf" || fail "the stock comments were dropped"

# An administrator's own settings survive (the case Codex raised on #145).
fresh $'even_deny_root\nfail_interval = 60\n'
run || fail "the migration failed on a customised file"
grep -qx 'even_deny_root' "$conf" || fail "even_deny_root was dropped: $(<"$conf")"
[[ $(value fail_interval) == fail_interval=60 ]] || fail "fail_interval was dropped: $(<"$conf")"
[[ $(value deny) == deny=10 && $(value unlock_time) == unlock_time=120 ]] || fail "customised file: $(<"$conf")"

# A file that sets either value is the administrator's choice.
for own in $'deny = 5\n' $'  unlock_time = 30\n'; do
  fresh "$own"
  run || fail "the migration failed on a file with its own value"
  [[ $(<"$conf") == "${own%$'\n'}" ]] || fail "a file with its own value was changed: $(<"$conf")"
done

# No file: Subarchy's is copied.
fresh none
run || fail "the migration failed with no faillock.conf"
cmp -s "$conf" "$root/default/security/faillock.conf" || fail "Subarchy's file was not copied"

# sudo refused: the migration fails, so it stays pending, and the file is unchanged.
fresh $'even_deny_root\n'
touch "$work/sudo-refuses"
if run 2>/dev/null; then fail "the migration succeeded without sudo"; fi
[[ $(<"$conf") == even_deny_root ]] || fail "the file changed without sudo: $(<"$conf")"

# Run again after success: nothing more is added.
fresh $'even_deny_root\n'
{ run && run; } || fail "a second run failed"
[[ $(grep -c '^deny' "$conf") == 1 ]] || fail "a second run added deny again: $(<"$conf")"

echo "migration-faillock-test: ok"
