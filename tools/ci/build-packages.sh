#!/usr/bin/env bash
# Run as root inside the disposable Arch CI container; makepkg runs as builder.
set -euo pipefail

root=$(git rev-parse --show-toplevel)
# The container may be newer than Subarchy's staged Arch snapshot.
"$root/tools/ci/pin-snapshot.sh"
out="$root/build/packages"
mkdir -p "$out"
useradd -m builder
chown -R builder: "$root"
runuser -u builder -- git config --global --add safe.directory "$root"

# Keep VERSION_ID semantic (ADR 0066); order main builds by Git history in
# pkgrel so a new commit never tries to replace an immutable registry version.
sed -i "s/^pkgrel=.*/pkgrel=$(git rev-list --count HEAD)/" "$root/packaging/subarchy/PKGBUILD"
export MAKEFLAGS=-j4
export JAVA_TOOL_OPTIONS=-XX:ActiveProcessorCount=4
export GRADLE_OPTS='-Dorg.gradle.workers.max=2 -Dorg.gradle.daemon=false -Xmx512m'

# What each channel's signed database lists, as "<channel> <name-version>".
# A file lookup by name is not enough: see publish-packages.py.
published=$(python3 "$root/tools/ci/publish-packages.py" --published)

# The registry finds a package file by substring, so two file names where
# one contains the other cannot both be served. Refuse before building.
all_files=()
for dir in "$root"/packaging/*/ "$root"/packaging/aur/*/; do
  [[ -f $dir/PKGBUILD ]] || continue
  mapfile -t -O "${#all_files[@]}" all_files < <(cd "$dir" && runuser -u builder -- env PKGDEST="$out" makepkg --packagelist)
done
python3 "$root/tools/ci/publish-packages.py" --check-names "${all_files[@]##*/}"

for dir in "$root"/packaging/*/ "$root"/packaging/aur/*/; do
  [[ -f $dir/PKGBUILD ]] || continue
  cd "$dir"
  info=$(runuser -u builder -- makepkg --printsrcinfo)
  awk '$1 == "pkgname" {print $3}' <<<"$info" >>"$out/package-names.txt"
  file_list=$(runuser -u builder -- env PKGDEST="$out" makepkg --packagelist)
  [[ -n $file_list ]] || { echo "build-packages: empty package list for $dir" >&2; exit 1; }
  mapfile -t files <<<"$file_list"
  # Published package versions are immutable. Always build the core and
  # keyring; otherwise reuse a version only if both channels' databases
  # list every package the PKGBUILD makes.
  cached=1
  for file in "${files[@]}"; do
    entry=$(basename "$file" .pkg.tar.zst)
    entry=${entry%-*}
    for channel in stable edge; do
      grep -qxF "$channel $entry" <<<"$published" || cached=0
    done
  done
  if ((cached)) && [[ $dir != "$root/packaging/subarchy/" && $dir != "$root/packaging/subarchy-keyring/" ]]; then
    echo ">> already published: $(basename "$dir")"
    continue
  fi
  mapfile -t deps < <(awk '$1 ~ /^makedepends(_x86_64)?$/ {print $3}' <<<"$info" | sort -u)
  ((${#deps[@]} == 0)) || pacman -S --noconfirm --needed "${deps[@]}"
  work=$(mktemp -d)
  trap 'rm -rf -- "$work"' EXIT
  chown builder: "$work"
  echo ">> building $(basename "$dir")"
  runuser -u builder -- env PKGDEST="$out" BUILDDIR="$work" \
    makepkg --force --cleanbuild --nodeps --noconfirm
  rm -rf -- "$work"
  trap - EXIT
done
sort -u -o "$out/package-names.txt" "$out/package-names.txt"
