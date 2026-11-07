#!/usr/bin/env bash
# Builds the Subarchy install ISO:
#   1. builds the subarchy package with makepkg into a local repository;
#   2. copies iso/profile, pointing its [subarchy] repository at that path;
#   3. runs mkarchiso (needs root) with a work directory outside the checkout.
#
# Usage: tools/iso/build.sh [out-dir]       (default: build/iso)
#        tools/iso/build.sh --package-only  (step 1 only, for make install-test)
# Env:   SUBARCHY_ISO_WORK  mkarchiso work dir (default /var/tmp/subarchy-iso-work)
set -euo pipefail

root=$(git rev-parse --show-toplevel)
package_only=0
if [[ ${1:-} == --package-only ]]; then
  package_only=1
  shift
fi
out=$(realpath -m "${1:-$root/build/iso}")
work=${SUBARCHY_ISO_WORK:-/var/tmp/subarchy-iso-work}
repo="$root/build/repo"
profile="$root/build/iso-profile"

((package_only)) || command -v mkarchiso >/dev/null || { echo "build.sh: mkarchiso not found (pacman -S archiso)" >&2; exit 1; }

echo ">> building the subarchy package"
mkdir -p "$repo"
# makepkg's build directory must sit outside the checkout: the package's
# check() runs `go test ./...`, which would walk into makepkg's pkg/ tree.
mkbuild=$(mktemp -d)
cleanup() { rm -r -- "$mkbuild"; }
trap cleanup EXIT
nodeps=()
pacman -T go >/dev/null 2>&1 || nodeps=(--nodeps)
(
  cd "$root/packaging/subarchy"
  BUILDDIR="$mkbuild" PKGDEST="$repo" \
    makepkg --force --cleanbuild --noconfirm "${nodeps[@]}"
) >"$root/build/makepkg.log" 2>&1 || { tail -30 "$root/build/makepkg.log" >&2; exit 1; }
pkg=$(find "$repo" -maxdepth 1 -name 'subarchy-*.pkg.tar.zst' -printf '%T@ %p\n' | sort -n | tail -1 | cut -d' ' -f2-)
repo-add --quiet "$repo/subarchy.db.tar.gz" "$pkg" >/dev/null
((package_only)) && exit 0

echo ">> preparing the profile"
mkdir -p "$profile"
cp -a --no-preserve=ownership "$root/iso/profile/." "$profile/"
sed -i "s|@LOCAL_REPO@|$repo|" "$profile/pacman.conf"
# The installer and its package lists, run as `subarchy-install` on the image.
lib="$profile/airootfs/usr/local/lib/subarchy-install"
mkdir -p "$lib" "$profile/airootfs/usr/local/bin"
cp -a --no-preserve=ownership "$root/install/subarchy-install" "$root/install/packages" "$lib/"
ln -sfn ../lib/subarchy-install/subarchy-install "$profile/airootfs/usr/local/bin/subarchy-install"

echo ">> running mkarchiso (work: $work, out: $out)"
mkdir -p "$out"
sudo mkarchiso -v -r -w "$work" -o "$out" "$profile"
sudo chown "$(id -u):$(id -g)" "$out"/*.iso
ls -l "$out"/*.iso
