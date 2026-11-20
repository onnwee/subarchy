#!/usr/bin/env bash
# Reads back the version a built core package reports and checks that its
# parts agree (set-core-version.sh, packaging/subarchy/PKGBUILD):
#
#   release (BUILD_ID=v<version>):  pkgrel <commits>.1, VERSION=<version>,
#                                    `subcult --version` = subcult <version>
#   any other build:                 pkgrel without .1, VERSION=<version>+<build>,
#                                    `subcult --version` = subcult <VERSION>
#
# VERSION_ID is the package's pkgver in both (ADR 0066).
#
# Usage: check-core-version.sh DIR   (DIR holds the extracted package:
# .PKGINFO, etc/os-release and usr/bin/subcult)
set -euo pipefail

fail() { echo "check-core-version: $*" >&2; exit 1; }

dir=${1:?usage: check-core-version.sh DIR}
pkgver=$(sed -n 's/^pkgver = //p' "$dir/.PKGINFO")
[[ $pkgver == *-* ]] || fail "no pkgver in .PKGINFO"
version=${pkgver%-*} release=${pkgver##*-}

field() { sed -n "s/^$1=//p" "$dir/etc/os-release" | tr -d '"'; }
version_id=$(field VERSION_ID) os_version=$(field VERSION) build=$(field BUILD_ID)
said=$("$dir/usr/bin/subcult" --version)

[[ $version_id == "$version" ]] || fail "VERSION_ID=$version_id, package version $version"
[[ -n $build ]] || fail "no BUILD_ID in os-release"
if [[ $build == "v$version" ]]; then
  [[ $release == *.1 ]] || fail "release $build has pkgrel $release, want <commits>.1"
  [[ $os_version == "$version" ]] || fail "release $build has VERSION=$os_version, want $version"
else
  [[ $build == v* ]] && fail "BUILD_ID=$build is a tag that does not match version $version"
  [[ $release != *.* ]] || fail "development build $build has release pkgrel $release"
  [[ $os_version == "$version+$build" ]] || fail "VERSION=$os_version, want $version+$build"
fi
[[ $said == "subcult $os_version" ]] || fail "subcult --version said '$said', want 'subcult $os_version'"
echo "check-core-version: $pkgver, $said, BUILD_ID=$build"
