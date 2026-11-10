#!/usr/bin/env bash
# Run as root inside the disposable Arch CI container (the subarchy-kvm
# runner: privileged, with /dev/kvm). Builds the live ISO the way `make iso`
# does on a workstation, then boots it in QEMU.
#
# The core package is built here from the checkout. The pinned rebuilds are
# not rebuilt: they come from the signed stable registry, which the packages
# workflow fills. The install set comes from Subarchy's Arch snapshot, so
# the image installs what the stable channel serves (ADR 0026).
set -euo pipefail

root=$(git rev-parse --show-toplevel)
registry=https://git.subcult.tv/api/packages/subculture-collective/arch/stable/x86_64
snapshot=$(cat "$root/default/pacman/snapshot")
[[ $snapshot =~ ^[0-9]{4}/[0-9]{2}/[0-9]{2}$ ]] || { echo "build-iso: invalid snapshot date" >&2; exit 1; }
# A VM without KVM would pass the boot test slowly or time out; say why.
[[ -r /dev/kvm && -w /dev/kvm ]] || { echo "build-iso: /dev/kvm is not usable" >&2; exit 1; }

# Pacman expands its own repository and architecture placeholders.
# shellcheck disable=SC2016
printf 'Server = https://archive.archlinux.org/repos/%s/$repo/os/$arch\n' "$snapshot" >/etc/pacman.d/mirrorlist
# The container may be newer than Subarchy's staged Arch snapshot.
pacman -Syyuu --noconfirm
pacman -S --noconfirm --needed base-devel git go python sudo archiso qemu-system-x86 edk2-ovmf \
  pacman-contrib fakeroot hypridle librsvg xorg-xcursorgen hyprcursor python-pyte python-pillow \
  ffmpeg ttf-dejavu qt6-multimedia

# makepkg refuses to run as root; build.sh uses sudo for pacman and mkarchiso.
useradd -m builder
echo 'builder ALL=(ALL) NOPASSWD: ALL' >/etc/sudoers.d/builder
chown -R builder: "$root"
runuser -u builder -- git config --global --add safe.directory "$root"

# The same version the packages workflow publishes for this commit.
sed -i "s/^pkgrel=.*/pkgrel=$(git rev-list --count HEAD)/" "$root/packaging/subarchy/PKGBUILD"

repo="$root/build/repo"
runuser -u builder -- mkdir -p "$repo"
for dir in "$root"/packaging/*/ "$root"/packaging/aur/*/; do
  [[ -f $dir/PKGBUILD && $dir != "$root/packaging/subarchy/" ]] || continue
  file_list=$(cd "$dir" && runuser -u builder -- env PKGDEST="$repo" makepkg --packagelist)
  [[ -n $file_list ]] || { echo "build-iso: empty package list for $dir" >&2; exit 1; }
  while IFS= read -r file; do
    name=$(basename "$file")
    echo ">> fetching $name"
    runuser -u builder -- curl --fail --silent --show-error --location --output "$file" "$registry/$name" ||
      { echo "build-iso: $name is not in the stable registry; the packages workflow publishes it on main" >&2; exit 1; }
  done <<<"$file_list"
done

cd "$root"
runuser -u builder -- make iso
# As root: the builder user cannot open /dev/kvm here. The serial log is
# kept for the workflow's artifact.
isos=("$root"/build/iso/subarchy-*.iso)
python3 tools/iso/boot-test.py --log "$root/build/iso-boot.log" "${isos[0]}"
