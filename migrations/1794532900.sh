#!/usr/bin/env bash
# A mistyped disk passphrase no longer ends the boot. New installs put
# tries=0 in rd.luks.options, so systemd-cryptsetup asks again until the
# passphrase is right. Before, the third wrong one dropped the initrd to an
# emergency shell that the locked root account cannot open. Add the option
# to an earlier install's kernel command line and rebuild the boot images
# that carry it. A command line that already sets tries= is left alone, as
# is one without rd.luks.options.
# SUBCULT_TEST_ROOT: a stand-in filesystem root for tools/test/migration-luks-tries-test.sh.
root=${SUBCULT_TEST_ROOT:-}
# A splash recoloured by `subcult theme apply-system` is a copy of the
# theme made then; it keeps the old prompt until apply-system runs again.
# Each user's own palette decides the colours, so say so rather than
# rewrite the splash from whichever user runs this first.
if grep -qx 'Theme=subarchy-user' "$root/etc/plymouth/plymouthd.conf" 2>/dev/null; then
  echo "Your recoloured boot splash keeps the old passphrase prompt; run 'subcult theme apply-system' to get the new one."
fi
files=()
for f in "$root/etc/default/limine" "$root/etc/kernel/cmdline"; do
  [[ -f $f ]] || continue
  grep -q 'rd\.luks\.options=' "$f" || continue
  grep -q 'rd\.luks\.options=[^[:space:]"]*tries=' "$f" && continue
  files+=("$f")
done
((${#files[@]})) || exit 0
echo "The disk passphrase prompt now asks again after a wrong passphrase (tries=0); rebuilding the boot images."
sudo sed -i '/rd\.luks\.options=/{/rd\.luks\.options=[^[:space:]"]*tries=/!s/\(rd\.luks\.options=[^[:space:]"]*\)/\1,tries=0/}' "${files[@]}"
# Limine reads the command line from /etc/default/limine into each UKI and
# its menu entry; snapshots keep the line they were made with. If the
# rebuild fails, take the option out again, so the next run finds the
# command line unchanged and rebuilds then. limine-mkinitcpio exits 0 when
# mkinitcpio fails for one kernel (it skips that kernel), so check that
# every UKI is newer than the edited command line too.
rebuilt() {
  sudo limine-mkinitcpio || return 1
  local fresh stale
  fresh=$(sudo find "$root/boot/EFI/Linux" -maxdepth 1 -name 'subarchy_*.efi' -newer "${files[0]}")
  stale=$(sudo find "$root/boot/EFI/Linux" -maxdepth 1 -name 'subarchy_*.efi' ! -newer "${files[0]}")
  [[ -n $fresh && -z $stale ]] || { echo "Not rebuilt: ${stale:-no boot images found}" >&2; return 1; }
}
if ! rebuilt; then
  sudo sed -i 's/\(rd\.luks\.options=[^[:space:]"]*\),tries=0/\1/' "${files[@]}"
  echo "The boot images could not all be rebuilt; the kernel command line files are as they were, and the next update tries again." >&2
  exit 1
fi
