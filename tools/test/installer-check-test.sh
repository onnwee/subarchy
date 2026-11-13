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

# A wrong disk passphrase asks again instead of ending in the initrd's
# emergency shell after three tries.
grep -q 'rd\.luks\.options=discard,tries=0 ' "$root/install/subarchy-install" || fail "the kernel command line has no tries=0"

# pacstrap runs the target's pacman hooks, so limine-mkinitcpio-hook's
# override replaces mkinitcpio's own and the kernels are built once.
target=/mnt/target
[[ $(pacman_conf 0 2>/dev/null | grep '^HookDir') == "HookDir = /mnt/target/etc/pacman.d/hooks/" ]] ||
  fail "pacman.conf for pacstrap: $(pacman_conf 0 2>/dev/null | grep '^HookDir' || echo 'no HookDir')"

# Boot entries left by earlier installs: only Limine's or Subarchy's whose
# partition is gone are removed. This install's entry, another system's,
# the firmware's own and a foreign entry with a missing partition stay.
lsblk() { printf '%s\n' "AAAAAAAA-1111-4111-8111-111111111111" "bbbbbbbb-2222-4222-8222-222222222222" ""; }
efibootmgr() {
  if [[ $1 == -v ]]; then
    printf '%s\n' "BootCurrent: 0007" "BootOrder: 0003,0001,0002,0004,0005,0006,0007" \
      "Boot0001* Limine	HD(1,GPT,aaaaaaaa-1111-4111-8111-111111111111,0x800,0x800000)/File(\\EFI\\limine\\limine_x64.efi)" \
      "Boot0002* Limine	HD(1,GPT,cccccccc-3333-4333-8333-333333333333,0x800,0x800000)/File(\\EFI\\limine\\limine_x64.efi)" \
      "Boot0003  Subarchy	HD(1,GPT,DDDDDDDD-4444-4444-8444-444444444444,0x800,0x800000)/File(\\EFI\\BOOT\\BOOTX64.EFI)" \
      "Boot0004* Windows Boot Manager	HD(1,GPT,eeeeeeee-5555-4555-8555-555555555555,0x800,0x32000)/File(\\EFI\\Microsoft\\Boot\\bootmgfw.efi)" \
      "Boot0005* ubuntu	HD(1,GPT,bbbbbbbb-2222-4222-8222-222222222222,0x800,0x100000)/File(\\EFI\\ubuntu\\shimx64.efi)" \
      "Boot0006* UEFI: PXE IPv4	PciRoot(0x0)/Pci(0x1f,0x6)/MAC(001122334455,0)/IPv4(0.0.0.0)" \
      "Boot0007* UEFI: USB DISK 3.0	PciRoot(0x0)/Pci(0x14,0x0)/USB(2,0)/HD(2,GPT,ffffffff-6666-4666-8666-666666666666,0x8d0000,0x87000)"
  else
    deleted+=("$*")
  fi
}
[[ $(stale_boot_entries | tr '\n' ' ') == "0002 0003 " ]] || fail "stale boot entries: $(stale_boot_entries | tr '\n' ' ')"

# The Wi-Fi network used during the install becomes a NetworkManager
# connection on the new system: mode 600, the passphrase escaped for the
# keyfile format and never in the output (the install log on the screen).
wifi=$(mktemp -d)
target=$wifi/root
psk_file=$wifi/wifi-psk
printf '%s\n' 'pass\word 42 ' >"$psk_file"
conf[WIFI_SSID]="Home Net" conf[WIFI_PSK_FILE]=$psk_file
(check_wifi) || fail "a good Wi-Fi network was refused"
out=$(write_wifi_connection) || fail "write_wifi_connection failed"
keyfile=$target/etc/NetworkManager/system-connections/Home_Net.nmconnection
[[ -f $keyfile && $(stat -c %a "$keyfile") == 600 ]] || fail "keyfile missing or not mode 600: $(ls -l "$keyfile" 2>&1)"
for line in "id=Home Net" "type=wifi" "ssid=Home Net" "key-mgmt=wpa-psk" 'psk=pass\\word 42\s' "method=auto"; do
  grep -qxF -- "$line" "$keyfile" || fail "keyfile lacks $line: $(grep -v '^psk=' "$keyfile")"
done
grep -qE '^uuid=[0-9a-f-]{36}$' "$keyfile" || fail "keyfile has no uuid"
[[ $out == "the installed system joins the Wi-Fi network Home Net" && $out != *word* ]] || fail "output: $out"
# Any other name is written as its bytes; an open network has no security.
conf[WIFI_SSID]="Café 5" conf[WIFI_PSK_FILE]=""
write_wifi_connection >/dev/null
keyfile=$target/etc/NetworkManager/system-connections/Caf___5.nmconnection
grep -qxF "ssid=67;97;102;195;169;32;53;" "$keyfile" || fail "SSID bytes: $(grep '^ssid=' "$keyfile" || true)"
if ! grep -qxF "id=Wi-Fi" "$keyfile" || grep -q wifi-security "$keyfile"; then fail "open network keyfile: $(cat "$keyfile")"; fi
conf[WIFI_SSID]=12345
write_wifi_connection >/dev/null
grep -qxF "ssid=49;50;51;52;53;" "$target/etc/NetworkManager/system-connections/12345.nmconnection" || fail "a digits-only SSID was written as text"
# NetworkManager skips hidden files, so a name starting with a dot is not
# written as one.
conf[WIFI_SSID]=.hidden
write_wifi_connection >/dev/null
[[ -f $target/etc/NetworkManager/system-connections/_hidden.nmconnection ]] ||
  fail "a dot SSID's keyfile: $(ls -A "$target/etc/NetworkManager/system-connections")"
rm -rf -- "$target"
conf[WIFI_SSID]=""
write_wifi_connection
[[ ! -e $target ]] || fail "wrote a connection with no Wi-Fi network in the config"
# Refused before the disk is wiped.
for bad in "|$psk_file" "$(printf 'a\tb')|" "$(printf '%033d' 0)|" "Home|$wifi/missing"; do
  conf[WIFI_SSID]=${bad%%|*} conf[WIFI_PSK_FILE]=${bad#*|}
  (check_wifi) 2>/dev/null && fail "Wi-Fi config accepted: ${bad@Q}"
done
for psk in short "$(printf '%064d' 0)x" "$(printf 'tab\there1')"; do
  printf '%s\n' "$psk" >"$psk_file"
  conf[WIFI_SSID]=Home conf[WIFI_PSK_FILE]=$psk_file
  (check_wifi) 2>/dev/null && fail "Wi-Fi passphrase accepted: ${psk@Q}"
done
printf '%064d\n' 0 >"$psk_file"
(check_wifi) || fail "a 64-digit key was refused"
rm -rf -- "$wifi"
echo "installer-check-test: ok"
