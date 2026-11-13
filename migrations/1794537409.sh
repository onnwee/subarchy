#!/usr/bin/env bash
# Failed passwords (ADR 0063): Subarchy locks an account after 10 failures
# for 2 minutes. Before, Arch's defaults applied (3 failures, 10 minutes),
# and three typos at the greeter or the lock screen locked the account.
# New installs get the file from the installer; this brings an install from
# before up to date. A faillock.conf with its own deny or unlock_time line
# is left alone. Otherwise Subarchy's two lines are added to the end and
# every other setting in the file (even_deny_root, fail_interval and so on)
# stays as it was; with no file at all, Subarchy's is copied. Plain sudo,
# like the update's privileged steps: inside `subcult update` the cached
# timestamp answers, and with no cache (`subcult update migrate`, or a
# policy that asks every time) sudo asks on the terminal. If sudo is
# refused the migration stays pending.
# SUBCULT_TEST_ROOT: a stand-in filesystem root for tools/test/migration-faillock-test.sh.
root=${SUBCULT_TEST_ROOT:-}
conf=$root/etc/security/faillock.conf
ours=$root/usr/share/subcult/default/security/faillock.conf
need_sudo() { echo "faillock settings need sudo: run subcult update migrate again" >&2; exit 1; }
[[ -r $ours ]] || exit 0
if grep -Eq '^[[:space:]]*(deny|unlock_time)[[:space:]]*=' "$conf" 2>/dev/null; then
  exit 0
fi
if [[ ! -e $conf ]]; then
  sudo install -D -m 0644 "$ours" "$conf" || need_sudo
  exit 0
fi
{
  printf '\n# Subarchy (ADR 0063): 10 failures lock the account for 2 minutes.\n'
  grep -E '^[[:space:]]*(deny|unlock_time)[[:space:]]*=' "$ours"
} | sudo tee -a "$conf" >/dev/null || need_sudo
