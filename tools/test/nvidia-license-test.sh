#!/usr/bin/env bash
# Run both split-package functions against placeholder libraries. Each
# package must carry the vendor's actual notice, without another package.
# shellcheck disable=SC1091
set -euo pipefail

root=$(git rev-parse --show-toplevel)
work=$(mktemp -d)
trap 'rm -rf -- "$work"' EXIT
fail() { echo "nvidia-license-test: $*" >&2; exit 1; }

source "$root/packaging/aur/lib32-nvidia-580xx-utils/PKGBUILD"
mkdir -p "$work/$_pkg/32"
printf 'Vendor licence fixture\n' >"$work/$_pkg/LICENSE"
for lib in libnvidia-opencl libGLX_nvidia libEGL_nvidia libGLESv1_CM_nvidia \
  libGLESv2_nvidia libnvidia-glcore libnvidia-eglcore libnvidia-glsi \
  libnvidia-fbc libnvidia-encode libnvidia-ml libnvidia-glvkspirv \
  libnvidia-allocator libnvidia-gpucomp libvdpau_nvidia libnvidia-tls \
  libcuda libnvcuvid libnvidia-ptxjitcompiler libnvidia-opticalflow; do
  : >"$work/$_pkg/32/$lib.so.$pkgver"
done
# SONAMEs are unrelated to the notice. The fixture libraries have no ELF.
create_links() { :; }

for pkgname in lib32-opencl-nvidia-580xx lib32-nvidia-580xx-utils; do
  pkgdir=$work/$pkgname
  mkdir -p "$pkgdir"
  (cd "$work"; "package_$pkgname")
  notice=$pkgdir/usr/share/licenses/$pkgname/LICENSE
  [[ -f $notice && ! -L $notice ]] || fail "$pkgname has no independent licence file"
  cmp "$work/$_pkg/LICENSE" "$notice" || fail "$pkgname changed the vendor notice"
done

echo "nvidia-license-test: both split packages carry the vendor notice"
