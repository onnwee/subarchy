#!/usr/bin/env bash
# Run as root inside the disposable Arch CI container; makepkg runs as builder.
set -euo pipefail

root=$(git rev-parse --show-toplevel)
snapshot=$(cat "$root/default/pacman/snapshot")
[[ $snapshot =~ ^[0-9]{4}/[0-9]{2}/[0-9]{2}$ ]] || { echo "build-packages: invalid snapshot date" >&2; exit 1; }
# Pacman expands its own repository and architecture placeholders.
# shellcheck disable=SC2016
printf 'Server = https://archive.archlinux.org/repos/%s/$repo/os/$arch\n' "$snapshot" >/etc/pacman.d/mirrorlist
# The container may be newer than Subarchy's staged Arch snapshot.
pacman -Syyuu --noconfirm
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

for dir in "$root"/packaging/*/ "$root"/packaging/aur/*/; do
  [[ -f $dir/PKGBUILD ]] || continue
  cd "$dir"
  info=$(runuser -u builder -- makepkg --printsrcinfo)
  awk '$1 == "pkgname" {print $3}' <<<"$info" >>"$out/package-names.txt"
  file_list=$(runuser -u builder -- env PKGDEST="$out" makepkg --packagelist)
  [[ -n $file_list ]] || { echo "build-packages: empty package list for $dir" >&2; exit 1; }
  mapfile -t files <<<"$file_list"
  # Published package versions are immutable. Always build the core and
  # keyring; otherwise reuse a version only if both channels already have it.
  cached=1
  for file in "${files[@]}"; do
    for channel in stable edge; do
      status=$(curl --silent --show-error --head --output /dev/null --write-out '%{http_code}' \
        "https://git.subcult.tv/api/packages/subculture-collective/arch/$channel/x86_64/$(basename "$file")?ci-check=$(date +%s%N)")
      case $status in
        200) ;;
        404) cached=0 ;;
        *) echo "build-packages: registry lookup returned HTTP $status" >&2; exit 1 ;;
      esac
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
