#!/usr/bin/env bash
# Build/check/stage the pinned Pult recipe without Arch or a host install.
# Downloads only its checksum-pinned source and catalog (about 3 MB).
set -euo pipefail

root=$(git rev-parse --show-toplevel)
work=$(mktemp -d)
trap 'rm -rf -- "$work"' EXIT

# Keep the recipe's build() and check() authoritative, including ldflags,
# catalog embedding, upstream tests and the Subarchy app-target checks.
# Match the documented container builder's repository-relative layout,
# copying only the inputs the package check needs.
context=$work/context
startdir=$context/packaging/pult
mkdir -p "$startdir" "$context/tools/test" "$context/default/theme"
cp "$root/packaging/pult/PKGBUILD" "$startdir/"
cp "$root/tools/test/pult-app-targets-test.py" "$context/tools/test/"
cp "$root/default/theme/subarchy.toml" "$root/default/theme/subcult-minimal.json" "$context/default/theme/"
srcdir=$work/src
pkgdir=$work/pkg
mkdir -p "$srcdir" "$pkgdir"
# shellcheck source-path=SCRIPTDIR/../..
# shellcheck source=packaging/pult/PKGBUILD
source "$startdir/PKGBUILD"
export GOMAXPROCS=${GOMAXPROCS:-2}
export GOFLAGS="${GOFLAGS:+$GOFLAGS }-p=2"

for i in "${!source[@]}"; do
  url=${source[$i]}
  name=${url##*/}
  if [[ $url == *::* ]]; then
    name=${url%%::*}
    url=${url#*::}
  fi
  curl --fail --location --silent --show-error --max-time 120 "$url" -o "$srcdir/$name"
  printf '%s  %s\n' "${sha256sums[$i]}" "$srcdir/$name" | sha256sum --check
done
tar -xzf "$srcdir/pult-${_commit}.tar.gz" -C "$srcdir"
build
check
package
"$pkgdir/usr/bin/pult" version
for path in usr/share/licenses/pult/LICENSE usr/share/licenses/pult/MIT.txt usr/share/licenses/pult/HuJSON-BSD-3-Clause.txt usr/share/doc/pult/README.md; do
  test -s "$pkgdir/$path"
done
cmp "$srcdir/$_srcdir/LICENSES/HuJSON-BSD-3-Clause.txt" "$pkgdir/usr/share/licenses/pult/HuJSON-BSD-3-Clause.txt"
echo 'pult-package-test: ok (recipe build, upstream tests, app targets, staged files)'
