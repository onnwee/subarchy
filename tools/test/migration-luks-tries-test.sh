#!/usr/bin/env bash
# The migration that adds tries=0 to the disk unlock options, against a fake
# root with stand-ins for sudo and limine-mkinitcpio: it edits both command
# lines once, rebuilds the boot images only when it changed something, and
# a failed rebuild, of all kernels or of one, leaves the command lines as
# they were.
set -euo pipefail

root=$(git rev-parse --show-toplevel)
migration=$root/migrations/1794532900.sh
fail() { echo "migration-luks-tries-test: $*" >&2; exit 1; }
work=$(mktemp -d)
trap 'rm -rf -- "$work"' EXIT
mkdir -p "$work/bin"
export MIG_TEST="$work" PATH="$work/bin:$PATH"

cat >"$work/bin/sudo" <<'STUB'
#!/bin/bash
echo "sudo $*" >>"$MIG_TEST/calls"
exec "$@"
STUB
# Like limine-mkinitcpio 1.40.0: a kernel whose mkinitcpio run fails is
# skipped and the command still exits 0.
cat >"$work/bin/limine-mkinitcpio" <<'STUB'
#!/bin/bash
[[ ! -e $MIG_TEST/rebuild-fails ]] || exit 1
later=@$(($(date +%s) + 60))
touch -d "$later" "$SUBCULT_TEST_ROOT/boot/EFI/Linux/subarchy_linux-zen.efi"
[[ -e $MIG_TEST/lts-fails ]] || touch -d "$later" "$SUBCULT_TEST_ROOT/boot/EFI/Linux/subarchy_linux-lts.efi"
STUB
chmod +x "$work/bin/sudo" "$work/bin/limine-mkinitcpio"

uuid=0b5c4e2a-1111-2222-3333-444455556666
fresh() { # $1: the rd.luks.options value an earlier install wrote
  rm -rf "$work/root" "$work/calls" "$work/rebuild-fails" "$work/lts-fails"
  mkdir -p "$work/root/etc/default" "$work/root/etc/kernel" "$work/root/boot/EFI/Linux"
  touch -d 2026-01-01 "$work/root/boot/EFI/Linux/subarchy_linux-zen.efi" "$work/root/boot/EFI/Linux/subarchy_linux-lts.efi"
  local line="rd.luks.name=$uuid=root rd.luks.options=$1 root=/dev/mapper/root rootflags=subvol=@ rw quiet splash"
  echo "$line" >"$work/root/etc/kernel/cmdline"
  printf '# Subarchy boot entries\nKERNEL_CMDLINE[default]="%s"\nENABLE_UKI=yes\n' "$line" >"$work/root/etc/default/limine"
  : >"$work/calls"
}
run() { SUBCULT_TEST_ROOT="$work/root" bash -euo pipefail "$migration"; }
rebuilds() { grep -c 'sudo limine-mkinitcpio' "$work/calls" || true; }

fresh discard
run >/dev/null || fail "the migration failed"
grep -q 'rd.luks.options=discard,tries=0 root=' "$work/root/etc/kernel/cmdline" || fail "kernel/cmdline: $(<"$work/root/etc/kernel/cmdline")"
grep -q '"rd.luks.name=.* rd.luks.options=discard,tries=0 root=' "$work/root/etc/default/limine" || fail "default/limine: $(<"$work/root/etc/default/limine")"
[[ $(rebuilds) == 1 ]] || fail "boot images rebuilt $(rebuilds) times, want 1"

# Run again (another user on the same machine): nothing to do, no sudo.
: >"$work/calls"
run >/dev/null || fail "the second run failed"
[[ ! -s $work/calls ]] || fail "the second run used sudo: $(<"$work/calls")"
[[ $(grep -o 'tries=0' "$work/root/etc/default/limine" | wc -l) == 1 ]] || fail "tries=0 added twice"

# TPM unlock on (subcult disk tpm enable): the option joins the list.
fresh discard,tpm2-device=auto
run >/dev/null || fail "the migration failed with TPM unlock on"
grep -q 'rd.luks.options=discard,tpm2-device=auto,tries=0 ' "$work/root/etc/default/limine" || fail "TPM line: $(<"$work/root/etc/default/limine")"

# A count the owner chose is kept, and nothing is rebuilt.
fresh discard,tries=5
run >/dev/null || fail "the migration failed with tries=5"
grep -q 'rd.luks.options=discard,tries=5 root=' "$work/root/etc/default/limine" || fail "tries=5 was changed"
[[ ! -s $work/calls ]] || fail "an unchanged command line was rebuilt"

# A failed rebuild puts the line back, so the next run tries again.
fresh discard
touch "$work/rebuild-fails"
run >/dev/null 2>&1 && fail "the migration passed although the rebuild failed"
grep -q 'rd.luks.options=discard root=' "$work/root/etc/default/limine" || fail "default/limine kept tries=0 after a failed rebuild"
grep -q 'rd.luks.options=discard root=' "$work/root/etc/kernel/cmdline" || fail "kernel/cmdline kept tries=0 after a failed rebuild"
rm "$work/rebuild-fails"
run >/dev/null || fail "the run after a failed rebuild failed"
grep -q 'rd.luks.options=discard,tries=0 root=' "$work/root/etc/default/limine" || fail "the run after a failed rebuild did not add tries=0"

# mkinitcpio fails for one kernel and limine-mkinitcpio still exits 0: its
# UKI keeps the old line, so the change is taken back.
fresh discard
touch "$work/lts-fails"
run >/dev/null 2>&1 && fail "the migration passed although one kernel was not rebuilt"
grep -q 'rd.luks.options=discard root=' "$work/root/etc/default/limine" || fail "default/limine kept tries=0 after one kernel was not rebuilt"

# A splash recoloured by apply-system: the user is told to run it again.
fresh discard,tries=0
mkdir -p "$work/root/etc/plymouth"
printf '[Daemon]\nTheme=subarchy-user\n' >"$work/root/etc/plymouth/plymouthd.conf"
[[ $(run) == *"subcult theme apply-system"* ]] || fail "no hint for a recoloured splash"
printf '[Daemon]\nTheme=subarchy\n' >"$work/root/etc/plymouth/plymouthd.conf"
[[ -z $(run) ]] || fail "a hint for the packaged splash"

# No LUKS options at all: left alone.
fresh discard
sed -i 's/ rd.luks.options=discard//' "$work/root/etc/default/limine" "$work/root/etc/kernel/cmdline"
run >/dev/null || fail "the migration failed without rd.luks.options"
[[ ! -s $work/calls ]] || fail "a command line without rd.luks.options was changed"

echo "migration-luks-tries-test: ok"
