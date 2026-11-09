#!/usr/bin/env bash
# Builds a vendored package in a clean Arch container and adds it to the
# local repository build/repo (ADR 0025: AUR packages Subarchy ships are
# rebuilt into its own repository from reviewed, pinned PKGBUILDs; Subarchy's
# own packages under packaging/<name>, such as linecast, build the same way).
#
# Usage: packaging/aur/build.sh <package>...   (needs docker)
set -euo pipefail

root=$(git rev-parse --show-toplevel)
repo="$root/build/repo"
mkdir -p "$repo"

for name in "$@"; do
  dir="$root/packaging/aur/$name"
  [[ -f $dir/PKGBUILD ]] || dir="$root/packaging/$name"
  [[ -f $dir/PKGBUILD ]] || { echo "build.sh: no packaging/aur/$name/PKGBUILD or packaging/$name/PKGBUILD" >&2; exit 1; }
  out="$root/build/aur/$name"
  mkdir -p "$out"
  echo ">> building $name"
  # makedepends are read from the PKGBUILD; runtime depends are not needed
  # to build, so makepkg runs with --nodeps.
  docker run --rm \
    -v "$dir:/src:ro" -v "$out:/out" \
    -e HOST_UID="$(id -u)" -e HOST_GID="$(id -g)" \
    archlinux:latest bash -euo pipefail -c '
      pacman -Syu --noconfirm --needed base-devel git >/dev/null
      makedeps=$(bash -c "source /src/PKGBUILD; echo \${makedepends[*]}")
      # A package with no makedepends (subarchy-keyring) gives pacman no
      # targets, which it refuses.
      [ -z "$makedeps" ] || pacman -S --noconfirm --needed $makedeps >/dev/null
      useradd -m builder
      cp -r /src /home/builder/pkg
      chown -R builder /home/builder/pkg
      su builder -c "cd ~/pkg && makepkg --nodeps --noconfirm"
      cp /home/builder/pkg/*.pkg.tar.zst /out/
      chown -R "$HOST_UID:$HOST_GID" /out
    ' >"$out/build.log" 2>&1 || { tail -30 "$out/build.log" >&2; exit 1; }
  for pkg in "$out"/*.pkg.tar.zst; do
    cp "$pkg" "$repo/"
    repo-add --quiet "$repo/subarchy.db.tar.gz" "$repo/$(basename "$pkg")" >/dev/null
    echo ">> added $(basename "$pkg")"
  done
done
