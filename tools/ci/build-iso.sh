#!/usr/bin/env bash
# Run as root inside the disposable Arch CI container (the subarchy-kvm
# runner: privileged, with /dev/kvm). Builds the live ISO the way `make iso`
# does on a workstation, then boots it in QEMU.
#
# The core package is built here from the checkout. The pinned rebuilds are
# not rebuilt: pacman takes them from the signed stable registry, which the
# packages workflow fills. The install set comes from Subarchy's Arch snapshot, so
# the image installs what the stable channel serves (ADR 0026).
set -euo pipefail

root=$(git rev-parse --show-toplevel)
registry=https://git.subcult.tv/api/packages/subculture-collective/arch/stable
snapshot=$(cat "$root/default/pacman/snapshot")
[[ $snapshot =~ ^[0-9]{4}/[0-9]{2}/[0-9]{2}$ ]] || { echo "build-iso: invalid snapshot date" >&2; exit 1; }
# A VM without KVM would pass the boot test slowly or time out; say why.
[[ -r /dev/kvm && -w /dev/kvm ]] || { echo "build-iso: /dev/kvm is not usable" >&2; exit 1; }

# Pacman expands its own repository and architecture placeholders.
# shellcheck disable=SC2016
printf 'Server = https://archive.archlinux.org/repos/%s/$repo/os/$arch\n' "$snapshot" >/etc/pacman.d/mirrorlist
# The archive stalls single connections for longer than pacman's ten-second
# low-speed limit when hundreds of files are fetched; waiting gets them all.
sed -i '/^\[options\]/a DisableDownloadTimeout' /etc/pacman.conf
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

# The pinned rebuilds, by package name through pacman with signatures
# required. Not by file name: the registry answers a request for
# nvidia-580xx-utils-... with the lib32 package (see publish-packages.py).
keyring="$root/packaging/subarchy-keyring"
install -Dm644 "$keyring/registry.key" /usr/share/pacman/keyrings/subarchy.gpg
install -Dm644 "$keyring/subarchy-trusted" /usr/share/pacman/keyrings/subarchy-trusted
install -Dm644 "$keyring/subarchy-revoked" /usr/share/pacman/keyrings/subarchy-revoked
pacman-key --init
pacman-key --populate archlinux subarchy
repo="$root/build/repo"
mkdir -p "$repo" /tmp/registry-db
# Pacman expands its own architecture placeholder.
# shellcheck disable=SC2016
printf '[options]\nArchitecture = auto\nDBPath = /tmp/registry-db\nCacheDir = %s\n\n[subarchy]\nSigLevel = Required\nServer = %s/$arch\n' \
  "$repo" "$registry" >/tmp/registry-pacman.conf
names=()
for dir in "$root"/packaging/*/ "$root"/packaging/aur/*/; do
  [[ -f $dir/PKGBUILD && $dir != "$root/packaging/subarchy/" ]] || continue
  mapfile -t -O "${#names[@]}" names < <(cd "$dir" && runuser -u builder -- makepkg --printsrcinfo | awk '$1 == "pkgname" {print $3}')
done
pacman --config /tmp/registry-pacman.conf -Syddw --noconfirm "${names[@]}" ||
  { echo "build-iso: a pinned package is not in the stable registry; the packages workflow publishes them on main" >&2; exit 1; }
rm -f -- "$repo"/*.sig
chown -R builder: "$repo"

cd "$root"
runuser -u builder -- make iso
# As root: the builder user cannot open /dev/kvm here. The serial log is
# kept for the workflow's artifact.
isos=("$root"/build/iso/subarchy-*.iso)
python3 tools/iso/boot-test.py --log "$root/build/iso-boot.log" "${isos[0]}"
