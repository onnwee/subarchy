#!/usr/bin/env bash
# The installer's checks that need no disk: what it refuses before wiping,
# and that a failed hardware detection stops it. Sources the installer and
# replaces the programs it asks.
# The functions and variables below stand in for programs and state the
# sourced installer reads.
# shellcheck disable=SC2317,SC2329,SC2034
set -euo pipefail

root=$(git rev-parse --show-toplevel)
fail() { echo "installer-check-test: $*" >&2; exit 1; }

# shellcheck source=/dev/null
source "$root/install/subarchy-install"
set +e # the installer's own `set -e` would end the test at the first expected failure

# A disk with an active LVM volume group, a RAID member and an open LUKS
# volume, as the live image leaves them after starting what it found.
lsblk() {
  printf '%s\n' "disk sda" "part sda1" "part sda2" "lvm  vg0-root" "raid1 md0" "crypt backup"
}
[[ $(busy_volumes /dev/sda | tr '\n' ' ') == "vg0-root md0 backup " ]] || fail "busy volumes: $(busy_volumes /dev/sda | tr '\n' ' ')"
lsblk() { printf '%s\n' "disk sda" "part sda1"; }
[[ -z $(busy_volumes /dev/sda) ]] || fail "a plain disk was reported busy"

# Hardware detection that fails must end the install, not install nothing.
subcult-hw() { echo "partial"; return 3; }
out=$( (hardware_list packages) 2>&1) && fail "a failed hardware detection was accepted: $out"
[[ $out == *"hardware detection failed"* ]] || fail "failure message: $out"
subcult-hw() { printf '%s\n' intel-ucode thermald; }
[[ $(hardware_list packages | tr '\n' ' ') == "intel-ucode thermald " ]] || fail "hardware list"
subcult-hw() { :; }
[[ -z $(hardware_list services) ]] || fail "no services must give no lines"

# Nothing to close when this run opened nothing; after an open, the volume
# is closed.
closed=0
cryptsetup() { [[ $1 == close && $2 == root ]] && closed=1; }
umount() { :; }
target=/nonexistent
luks_open=0
close_after_failure
((closed == 0)) || fail "closed a volume this run did not open"
luks_open=1
close_after_failure
((closed == 1)) || fail "the encrypted volume was left open after a failure"

# A locale must be spelled as locale.gen lists it.
gen=$(mktemp)
printf '%s\n' "# comment" "#de_DE.UTF-8 UTF-8  " "#de_DE ISO-8859-1  " "en_US.UTF-8 UTF-8  " >"$gen"
(SUBARCHY_LOCALE_GEN=$gen check_locale de_DE.UTF-8) 2>/dev/null || fail "a listed locale was refused"
(SUBARCHY_LOCALE_GEN=$gen check_locale en_US.UTF-8) 2>/dev/null || fail "an enabled locale was refused"
out=$( (SUBARCHY_LOCALE_GEN=$gen check_locale de_DE.utf8) 2>&1) && fail "de_DE.utf8 was accepted"
[[ $out == *"not in locale.gen"* ]] || fail "locale message: $out"
(SUBARCHY_LOCALE_GEN=$gen check_locale "") 2>/dev/null && fail "an empty locale was accepted"
rm -f -- "$gen"

# An install from the mirrors that fails (an old image, a package signed with
# a key newer than its keyring) is tried again from the image's repository
# alone; a repository that is not on the image has no second try.
step() { :; }
mirrors_reachable() { return 0; }
subcult-hw() { echo amd-ucode; }
calls=$(mktemp)
pacstrap() { # records whether this call had the mirrors; fails while it has
  if grep -q '^\[core\]' "$2"; then echo mirrors >>"$calls"; return 1; fi
  echo image >>"$calls"
}
conf[SUBARCHY_REPO]=file:///run/archiso/bootmnt/subarchy/repo
(pacstrap_packages) >/dev/null 2>&1 || fail "the install did not fall back to the image's repository"
[[ $(tr '\n' ' ' <"$calls") == "mirrors image " ]] || fail "pacstrap calls: $(tr '\n' ' ' <"$calls")"
: >"$calls"
conf[SUBARCHY_REPO]=https://packages.example/subarchy
(pacstrap_packages) >/dev/null 2>&1 && fail "a failed install without the image's repository was reported as done"
[[ $(tr '\n' ' ' <"$calls") == "mirrors " ]] || fail "pacstrap calls without the image's repository: $(tr '\n' ' ' <"$calls")"
: >"$calls"
mirrors_reachable() { return 1; }
conf[SUBARCHY_REPO]=file:///run/archiso/bootmnt/subarchy/repo
(pacstrap_packages) >/dev/null 2>&1 || fail "an offline install failed"
[[ $(tr '\n' ' ' <"$calls") == "image " ]] || fail "an offline install asked the mirrors: $(tr '\n' ' ' <"$calls")"
rm -f -- "$calls"

# All keyboard drivers go into the initramfs: the hook before autodetect,
# which would keep only those of the keyboards present during the install.
hooks=$(grep -o '^HOOKS=([^)]*)' "$root/install/subarchy-install")
[[ $hooks == *" keyboard autodetect "* ]] || fail "keyboard must come before autodetect: $hooks"

echo "installer-check-test: ok"
