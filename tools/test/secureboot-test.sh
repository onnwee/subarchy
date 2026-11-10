#!/usr/bin/env bash
# `subcult secureboot setup` and `subcult disk tpm` against stand-ins for
# sbctl, limine-update, cryptsetup and systemd-cryptenroll, in a fake root:
# the order of the steps, and that a run interrupted half way can be
# finished by running the command again.
set -euo pipefail

root=$(git rev-parse --show-toplevel)
fail() { echo "secureboot-test: $*" >&2; exit 1; }
work=$(mktemp -d)
trap 'rm -rf -- "$work"' EXIT
mkdir -p "$work/bin"
export SB_TEST="$work" PATH="$work/bin:$PATH"

cat >"$work/bin/sbctl" <<'STUB'
#!/bin/bash
echo "sbctl $*" >>"$SB_TEST/calls"
case $1 in
  status) printf '{"installed": %s, "setup_mode": %s}\n' "$([[ -e $SB_TEST/keys ]] && echo true || echo false)" "$(<"$SB_TEST/setup_mode")" ;;
  create-keys) touch "$SB_TEST/keys" ;;
  enroll-keys) echo false >"$SB_TEST/setup_mode" ;;
  verify) [[ ! -e $SB_TEST/unsigned ]] || echo "/boot/EFI/Linux/x.efi is not signed" ;;
esac
STUB
cat >"$work/bin/limine-update" <<'STUB'
#!/bin/bash
echo "limine-update" >>"$SB_TEST/calls"
[[ ! -e $SB_TEST/limine-fails ]]
STUB
chmod +x "$work/bin/sbctl" "$work/bin/limine-update"

fresh() { # a machine in setup mode with no keys
  rm -rf "$work/root" "$work/keys" "$work/calls" "$work/unsigned" "$work/limine-fails"
  mkdir -p "$work/root/sys/firmware/efi" "$work/root/etc/default" "$work/root/boot/EFI/BOOT"
  echo 'KERNEL_CMDLINE[default]="rd.luks.options=discard root=/dev/mapper/root"' >"$work/root/etc/default/limine"
  touch "$work/root/boot/EFI/BOOT/BOOTX64.EFI"
  echo true >"$work/setup_mode"
  : >"$work/calls"
}
setup() { SUBCULT_TEST_ROOT="$work/root" "$root/bin/subcult-secureboot-setup"; }
line() { grep -n -m1 -- "$1" "$work/calls" | cut -d: -f1; }

# Keys are enrolled last: once they are, firmware may enforce Secure Boot,
# and everything must already be signed.
fresh
setup >/dev/null || fail "a clean setup failed"
[[ -n $(line 'sbctl enroll-keys') ]] || fail "keys were not enrolled"
(($(line 'sbctl enroll-keys') > $(line 'limine-update'))) || fail "keys were enrolled before Limine was signed: $(tr '\n' ';' <"$work/calls")"
(($(line 'sbctl enroll-keys') > $(line 'sbctl verify'))) || fail "keys were enrolled before the signatures were checked"
grep -q '^ENABLE_ENROLL_LIMINE_CONFIG=yes' "$work/root/etc/default/limine" || fail "config enrollment not turned on"

# Signing fails: nothing is enrolled, so the machine still boots as before.
fresh
touch "$work/limine-fails"
setup >/dev/null 2>&1 && fail "a failed limine-update was accepted"
[[ -z $(line 'sbctl enroll-keys') ]] || fail "keys were enrolled although signing failed"
# The same command finishes the job once the cause is gone.
rm "$work/limine-fails"
: >"$work/calls"
setup >/dev/null || fail "the second run did not finish the setup"
[[ -z $(line 'sbctl create-keys') ]] || fail "the second run created keys again"
[[ -n $(line 'sbctl enroll-keys') ]] || fail "the second run did not enroll the keys"

# An unsigned boot file stops before enrollment too.
fresh
touch "$work/unsigned"
setup >/dev/null 2>&1 && fail "unsigned boot files were accepted"
[[ -z $(line 'sbctl enroll-keys') ]] || fail "keys were enrolled with unsigned boot files"

# Keys enrolled already (not in setup mode): signs again, enrolls nothing.
fresh
touch "$work/keys"
echo false >"$work/setup_mode"
out=$(setup) || fail "a run on an enrolled machine failed"
[[ -z $(line 'sbctl enroll-keys') && -n $(line 'limine-update') ]] || fail "enrolled machine: $(tr '\n' ';' <"$work/calls")"
[[ $out == *"already enrolled"* ]] || fail "enrolled machine message: $out"

# --- subcult disk tpm -------------------------------------------------------
cat >"$work/bin/cryptsetup" <<'STUB'
#!/bin/bash
[[ $1 == status ]] && echo "  device:  /dev/vda2"
STUB
cat >"$work/bin/systemd-cryptenroll" <<'STUB'
#!/bin/bash
echo "systemd-cryptenroll $*" >>"$SB_TEST/calls"
case $* in
  *--tpm2-device=auto*) touch "$SB_TEST/tpm-slot" ;;
  *--wipe-slot=tpm2*) rm -f "$SB_TEST/tpm-slot" ;;
  *) echo "SLOT TYPE"; echo "   0 password"; [[ ! -e $SB_TEST/tpm-slot ]] || echo "   1 tpm2" ;;
esac
STUB
chmod +x "$work/bin/cryptsetup" "$work/bin/systemd-cryptenroll"
tpm() { SUBCULT_TEST_ROOT="$work/root" "$root/bin/subcult-disk-tpm" "$@"; }
tpm_machine() {
  fresh
  rm -f "$work/tpm-slot"
  mkdir -p "$work/root/sys/firmware/efi/efivars" "$work/root/dev"
  printf '\x06\x00\x00\x00\x01' >"$work/root/sys/firmware/efi/efivars/SecureBoot-8be4df61-93ca-11d2-aa0d-00e098032b8c"
  touch "$work/root/dev/tpmrm0"
}

tpm_machine
[[ $(tpm enable | tail -1) == "TPM unlock is on."* ]] || fail "tpm enable"
grep -q 'rd.luks.options=discard,tpm2-device=auto' "$work/root/etc/default/limine" || fail "the boot entry did not get the TPM option"
[[ $(tpm status) == "TPM unlock: on (/dev/vda2)" ]] || fail "tpm status: $(tpm status)"

# The boot entry update failed after the key was enrolled: running enable
# again finishes it, where it used to stop at "already on".
tpm_machine
touch "$work/limine-fails"
tpm enable >/dev/null 2>&1 && fail "tpm enable passed although limine-update failed"
rm "$work/limine-fails"
: >"$work/calls"
tpm enable >/dev/null || fail "the second tpm enable did not finish"
[[ -z $(line 'tpm2-device=auto --tpm2-pcrs') ]] || fail "the second run enrolled a second TPM key"
[[ -n $(line 'limine-update') ]] || fail "the second run did not update the boot entry"

# A kernel command line without the option the edit looks for: say so,
# not "TPM unlock is on" while the disk would keep asking.
tpm_machine
echo 'KERNEL_CMDLINE[default]="root=/dev/mapper/root rw"' >"$work/root/etc/default/limine"
out=$(tpm enable 2>&1) && fail "tpm enable claimed success without changing the boot entry: $out"
[[ $out == *"tpm2-device=auto"* && $out != *"TPM unlock is on."* ]] || fail "missing option message: $out"

echo "secureboot-test: ok"
