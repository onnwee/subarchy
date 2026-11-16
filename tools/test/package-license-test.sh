#!/usr/bin/env bash
# Exercise the real package functions with build-output fixtures: no compiler,
# container, host install or network. Then check bytes in the resulting archives.
# The sourced recipes consume startdir, set pkgname/pkgver and call cargo.
# Package functions use local root/srcdir/pkgdir values in separate staging
# subshells; none of those assignments must escape to another stage.
# shellcheck disable=SC1091,SC2030,SC2031,SC2034,SC2154,SC2329
set -euo pipefail
root=$(git rev-parse --show-toplevel)
work=$(mktemp -d)
trap 'rm -rf -- "$work"' EXIT
fail() { echo "package-license-test: $*" >&2; exit 1; }

check_notice() {
  tar -xOf "$1" "$2" | cmp -s - "$3"
}

(
  source "$root/packaging/subarchy/PKGBUILD"
  startdir=$root/packaging/subarchy
  srcdir=$work/core-src
  pkgdir=$work/core-pkg
  mkdir -p "$srcdir"/{bin,subcult-cursor,screens/subcult,screens/subarchy,plymouth,screensaver} "$pkgdir"
  printf '#!/bin/sh\n' >"$srcdir/bin/subcult"
  for set in subcult subarchy; do
    for file in boot.png login.png lock.png title.txt; do
      printf 'Build output fixture\n' >"$srcdir/screens/$set/$file"
    done
  done
  printf 'Build output fixture\n' >"$srcdir/plymouth/logo.png"
  cp "$srcdir/plymouth/logo.png" "$srcdir/lockup-dark.png"
  cp "$srcdir/plymouth/logo.png" "$srcdir/screensaver/fixture.png"
  package
  tar -cf "$work/core.tar" -C "$pkgdir" .
  for file in Go-BSD-3-Clause.txt TOML-MIT.txt; do
    check_notice "$work/core.tar" "./usr/share/licenses/subarchy/$file" "$root/LICENSES/$file" || fail "core omitted or changed $file"
  done
  # A directory or broken symlink cannot stand in for readable notice bytes.
  notice=$pkgdir/usr/share/licenses/subarchy/TOML-MIT.txt
  rm "$notice"
  ln -s missing "$notice"
  tar -cf "$work/broken.tar" -C "$pkgdir" .
  if check_notice "$work/broken.tar" ./usr/share/licenses/subarchy/TOML-MIT.txt "$root/LICENSES/TOML-MIT.txt" 2>/dev/null; then
    fail 'accepted an unreadable notice'
  fi
)

(
  source "$root/packaging/aur/tzupdate/PKGBUILD"
  srcdir=$work/tz-src
  pkgdir=$work/tz-pkg
  mkdir -p "$srcdir/$pkgname-$pkgver" "$pkgdir"
  # The package must retain its own pinned source notice, without substituting
  # a generic MIT licence or the core package's notice.
  printf 'Copyright fixture\n\nPermission fixture with exact whitespace.\n' >"$srcdir/$pkgname-$pkgver/LICENSE"
  cargo() {
    [[ $* == "install --no-track --locked --root $pkgdir/usr --path ." ]] || fail 'unexpected cargo invocation'
    mkdir -p "$pkgdir/usr/bin"
    printf 'Build output fixture\n' >"$pkgdir/usr/bin/tzupdate"
  }
  package
  tar -cf "$work/tz.tar" -C "$pkgdir" .
  path=./usr/share/licenses/tzupdate/LICENSE
  check_notice "$work/tz.tar" "$path" "$srcdir/$pkgname-$pkgver/LICENSE" || fail 'tzupdate omitted or changed its source notice'
  printf 'Changed notice\n' >"$pkgdir/usr/share/licenses/tzupdate/LICENSE"
  tar -cf "$work/changed.tar" -C "$pkgdir" .
  if check_notice "$work/changed.tar" "$path" "$srcdir/$pkgname-$pkgver/LICENSE" 2>/dev/null; then
    fail 'accepted a changed notice'
  fi
)
echo 'package-license-test: real package functions retain exact notice bytes; unreadable/changed notices rejected'
