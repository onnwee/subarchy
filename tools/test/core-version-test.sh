#!/usr/bin/env bash
# The core package's version for main, release and local builds (#278):
# tools/ci/set-core-version.sh in a scratch repository with the real PKGBUILD
# and os-release template, the PKGBUILD's _version and _os_release, and
# tools/ci/check-core-version.sh on stand-in extracted packages.
set -euo pipefail

root=$(git rev-parse --show-toplevel)
work=$(mktemp -d)
cleanup() { rm -rf -- "$work"; }
trap cleanup EXIT

fail() { echo "core-version-test: $*" >&2; exit 1; }

repo=$work/repo
mkdir -p "$repo/packaging/subarchy" "$repo/branding"
cp "$root/packaging/subarchy/PKGBUILD" "$repo/packaging/subarchy/PKGBUILD"
cp "$root/branding/os-release.in" "$repo/branding/os-release.in"
cp "$root/tools/ci/set-core-version.sh" "$work/set-core-version.sh"
g() { git -C "$repo" -c user.name=test -c user.email=test@example.invalid -c commit.gpgsign=false -c tag.gpgsign=false "$@"; }
g init -q
g add -A && g commit -qm one
echo two >"$repo/two" && g add two && g commit -qm two
head=$(g rev-parse HEAD)

# Runs the helper in the scratch repository with the given ref.
set_version() { (cd "$repo" && GITHUB_REF=$1 "$work/set-core-version.sh") >"$work/out" 2>&1; }
reset() { g checkout -q -- packaging/subarchy/PKGBUILD; }
# Evaluates the PKGBUILD as makepkg would and prints one of its values.
pkg() {
  (
    cd "$repo/packaging/subarchy"
    # shellcheck disable=SC2034 # the PKGBUILD's _root reads it
    startdir=$PWD
    # shellcheck source=/dev/null
    source ./PKGBUILD
    "$@"
  )
}
var() { pkg eval "printf '%s\n' \"\$$1\""; }
osr() { pkg _os_release | sed -n "s/^$1=//p"; }

# A local build: the checked-in values.
[[ $(pkg _version) == 0.0.0+dev ]] || fail "local _version is $(pkg _version)"
[[ $(osr VERSION) == '"0.0.0+dev"' && $(osr VERSION_ID) == 0.0.0 && $(osr BUILD_ID) == dev ]] ||
  fail "local os-release: $(pkg _os_release | tr '\n' ' ')"

# A main build: the commit count as pkgrel, as before; the build names the commit.
set_version refs/heads/main || fail "main build refused: $(cat "$work/out")"
[[ $(var pkgrel) == 2 ]] || fail "main pkgrel is $(var pkgrel)"
want=dev.2.g${head:0:12}
[[ $(pkg _version) == "0.0.0+$want" ]] || fail "main _version is $(pkg _version)"
[[ $(osr VERSION) == "\"0.0.0+$want\"" && $(osr VERSION_ID) == 0.0.0 && $(osr BUILD_ID) == "$want" ]] ||
  fail "main os-release: $(pkg _os_release | tr '\n' ' ')"
# Without a ref (a local run of the CI scripts) it is a main-style build too.
reset
set_version '' || fail "build without a ref refused"
[[ $(var _build) == "$want" ]] || fail "no-ref build is $(var _build)"

# A release build from tag v0.0.0 at the checkout.
reset
g tag v0.0.0
set_version refs/tags/v0.0.0 || fail "release build refused: $(cat "$work/out")"
[[ $(var pkgrel) == 2.1 ]] || fail "release pkgrel is $(var pkgrel)"
[[ $(pkg _version) == 0.0.0 ]] || fail "release _version is $(pkg _version)"
[[ $(osr VERSION) == '"0.0.0"' && $(osr VERSION_ID) == 0.0.0 && $(osr BUILD_ID) == v0.0.0 ]] ||
  fail "release os-release: $(pkg _os_release | tr '\n' ' ')"
# The release sorts after the main build of its commit and before the next one.
if command -v vercmp >/dev/null; then
  [[ $(vercmp 0.0.0-2 0.0.0-2.1) == -1 && $(vercmp 0.0.0-2.1 0.0.0-3) == -1 ]] || fail "vercmp order"
fi

# Refusals: each leaves the PKGBUILD as it was.
refuse() {
  local why=$1 ref=$2
  reset
  if set_version "$ref"; then fail "built a release with $why"; fi
  grep -q '^set-core-version: ' "$work/out" || fail "no reason given for $why: $(cat "$work/out")"
  [[ "$(var pkgrel) $(var _build)" == '1 dev' ]] || fail "PKGBUILD changed after refusing $why"
}
g tag v0.1.0
refuse "a tag for another version" refs/tags/v0.1.0
refuse "a tag missing from the checkout" refs/tags/v0.0.1
g tag -d v0.0.0 >/dev/null && g tag v0.0.0 HEAD~1
refuse "a tag on another commit" refs/tags/v0.0.0
g tag -d v0.0.0 >/dev/null && g tag v0.0.0
echo changed >>"$repo/two"
refuse "changed tracked files" refs/tags/v0.0.0
g checkout -q -- two

# check-core-version.sh on stand-ins for extracted packages.
fake() {
  local dir=$work/$1 pkgver=$2 version=$3 build=$4 said=$5
  mkdir -p "$dir/etc" "$dir/usr/bin"
  printf 'pkgname = subarchy\npkgver = %s\n' "$pkgver" >"$dir/.PKGINFO"
  printf 'ID=subarchy\nVERSION="%s"\nVERSION_ID=0.0.0\nBUILD_ID=%s\n' "$version" "$build" >"$dir/etc/os-release"
  printf '#!/bin/sh\necho "%s"\n' "$said" >"$dir/usr/bin/subcult"
  chmod +x "$dir/usr/bin/subcult"
  echo "$dir"
}
check() { "$root/tools/ci/check-core-version.sh" "$1" >/dev/null 2>&1; }
check "$(fake release 0.0.0-640.1 0.0.0 v0.0.0 'subcult 0.0.0')" || fail "check refused a release"
check "$(fake main 0.0.0-641 0.0.0+dev.641.gabc 'dev.641.gabc' 'subcult 0.0.0+dev.641.gabc')" || fail "check refused a main build"
check "$(fake local 0.0.0-1 0.0.0+dev dev 'subcult 0.0.0+dev')" || fail "check refused a local build"
for bad in \
  "a release with a main pkgrel|0.0.0-640|0.0.0|v0.0.0|subcult 0.0.0" \
  "a main build with a release pkgrel|0.0.0-640.1|0.0.0+dev.640.gabc|dev.640.gabc|subcult 0.0.0+dev.640.gabc" \
  "a main build that prints the bare version|0.0.0-641|0.0.0+dev.641.gabc|dev.641.gabc|subcult 0.0.0" \
  "a tag for another version|0.0.0-640.1|0.0.0|v0.1.0|subcult 0.0.0" \
  "os-release without the build|0.0.0-641|0.0.0|dev.641.gabc|subcult 0.0.0"; do
  IFS='|' read -r why pkgver version build said <<<"$bad"
  if check "$(fake "bad-${why// /-}" "$pkgver" "$version" "$build" "$said")"; then fail "check accepted $why"; fi
done

echo "core-version-test: ok"
