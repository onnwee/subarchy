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
# A VM without KVM would pass the boot test slowly or time out; say why.
[[ -r /dev/kvm && -w /dev/kvm ]] || { echo "build-iso: /dev/kvm is not usable" >&2; exit 1; }

# The container may be newer than Subarchy's staged Arch snapshot.
"$root/tools/ci/pin-snapshot.sh"
pacman -S --noconfirm --needed base-devel git go python sudo archiso qemu-system-x86 edk2-ovmf

# makepkg refuses to run as root; build.sh uses sudo for pacman and mkarchiso.
useradd -m builder
echo 'builder ALL=(ALL) NOPASSWD: ALL' >/etc/sudoers.d/builder
chown -R builder: "$root"
runuser -u builder -- git config --global --add safe.directory "$root"

# What the core package needs to build and to pass makepkg's dependency
# check, read from its PKGBUILD so this list cannot fall behind it.
mapfile -t deps < <(cd "$root/packaging/subarchy" && runuser -u builder -- makepkg --printsrcinfo |
  awk '$1 ~ /^(make)?depends$/ {print $3}' | sort -u)
pacman -S --noconfirm --needed "${deps[@]}"

# The same version the packages workflow publishes for this commit.
sed -i "s/^pkgrel=.*/pkgrel=$(git rev-list --count HEAD)/" "$root/packaging/subarchy/PKGBUILD"

# The pinned rebuilds, by exact package version through pacman with signatures
# required. An older published version must not qualify a new source pin.
# Not by file name: the registry answers a request for
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
  mapfile -t -O "${#names[@]}" names < <(cd "$dir" && runuser -u builder -- makepkg --printsrcinfo | awk '
    $1 == "epoch" {epoch = $3 ":"}
    $1 == "pkgver" {version = $3}
    $1 == "pkgrel" {release = $3}
    $1 == "pkgname" {print $3 "=" epoch version "-" release}')
done
# Retry only the interrupted transfer observed in CI. Keep pacman's cache
# (including completed packages) and exact arguments for every attempt.
download_log="$root/build/registry-download.log"
for attempt in 1 2 3; do
  if LC_ALL=C pacman --config /tmp/registry-pacman.conf -Syddw --noconfirm "${names[@]}" >"$download_log" 2>&1; then
    cat "$download_log"
    break
  else
    status=$?
  fi
  cat "$download_log" >&2
  # Require a specific transport error, not just "download library error".
  # Any other error, even alongside a reset, must fail without retrying.
  if ! awk '
    /^error: failed retrieving file .* : Recv failure: Connection reset by peer$/ {reset = 1; next}
    /^error: failed to commit transaction \(download library error\)$/ {next}
    /^error:/ {other = 1}
    END {exit !(reset && !other)}' "$download_log"; then
    echo "build-iso: signed pinned-package download failed; see pacman diagnostics above" >&2
    exit "$status"
  fi
  if (( attempt == 3 )); then
    echo "build-iso: pinned-package transport failed after 3 attempts; see pacman diagnostics above" >&2
    exit "$status"
  fi
  echo "build-iso: package transfer reset (attempt $attempt/3); retrying in ${attempt}s" >&2
  sleep "$attempt"
done
rm -f -- "$repo"/*.sig
# build/ and the repository were made by root just now.
chown -R builder: "$root/build"

cd "$root"
runuser -u builder -- make iso
# As root: the builder user cannot open /dev/kvm here. The serial log is
# kept for the workflow's artifact.
isos=("$root"/build/iso/subarchy-*.iso)
python3 tools/iso/boot-test.py --log "$root/build/iso-boot.log" "${isos[0]}"
