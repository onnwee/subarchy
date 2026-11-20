#!/usr/bin/env bash
# Sets the core package's release number and build identity for a CI build of
# the checked-out commit. build-packages.sh and build-iso.sh run it before
# makepkg, so both build the same version from the same commit.
#
#   main build:     pkgrel=<commits>    _build=dev.<commits>.g<commit>
#   release build:  pkgrel=<commits>.1  _build=<tag>
#
# A release build is one started by a tag push: GITHUB_REF=refs/tags/<tag>.
# The tag must be v<pkgver> (the version stays as ADR 0066 sets it), must name
# the checked-out commit, and the tracked files must be unchanged, so the
# package is built from exactly the tagged source. Its pkgrel sorts after the
# main build of the same commit and before the next main commit, and differs
# from it: published versions are immutable.
#
# Usage: set-core-version.sh [PKGBUILD]   (default: packaging/subarchy/PKGBUILD)
set -euo pipefail

fail() { echo "set-core-version: $*" >&2; exit 1; }

root=$(git rev-parse --show-toplevel)
pkgbuild=${1:-$root/packaging/subarchy/PKGBUILD}
[[ -f $pkgbuild ]] || fail "no PKGBUILD at $pkgbuild"
pkgver=$(sed -n 's/^pkgver=//p' "$pkgbuild")
[[ -n $pkgver ]] || fail "no pkgver in $pkgbuild"

count=$(git rev-list --count HEAD)
ref=${GITHUB_REF:-}
if [[ $ref == refs/tags/* ]]; then
  tag=${ref#refs/tags/}
  [[ $tag == "v$pkgver" ]] || fail "tag $tag does not match the package version $pkgver (want v$pkgver)"
  tagged=$(git rev-parse --verify --quiet "refs/tags/$tag^{commit}") || fail "tag $tag is not in this checkout"
  [[ $tagged == "$(git rev-parse HEAD)" ]] || fail "the checkout is not the commit tag $tag names"
  git diff --quiet HEAD -- || fail "tracked files differ from tag $tag"
  release=$count.1
  build=$tag
else
  release=$count
  build=dev.$count.g$(git rev-parse --short=12 HEAD)
fi

sed -i -e "s/^pkgrel=.*/pkgrel=$release/" -e "s/^_build=.*/_build=$build/" "$pkgbuild"
if ! grep -qx "pkgrel=$release" "$pkgbuild" || ! grep -qx "_build=$build" "$pkgbuild"; then
  fail "could not set pkgrel and _build in $pkgbuild"
fi
echo "set-core-version: $pkgver-$release ($build)"
