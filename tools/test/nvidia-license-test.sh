#!/usr/bin/env bash
# Run the OpenCL split-package functions against placeholder libraries. Each
# package must carry the vendor's actual notice, without another package.
# makepkg selects one scalar pkgname from the sourced split-package array.
# shellcheck disable=SC1091,SC2128,SC2178
set -euo pipefail

root=$(git rev-parse --show-toplevel)
work=$(mktemp -d)
trap 'rm -rf -- "$work"' EXIT
fail() { echo "nvidia-license-test: $*" >&2; exit 1; }

source "$root/packaging/aur/nvidia-580xx-utils/PKGBUILD"
lib32_rel=$(bash -c 'source "$1"; echo "$pkgrel"' _ "$root/packaging/aur/lib32-nvidia-580xx-utils/PKGBUILD")
[[ $pkgrel != "$lib32_rel" ]] || fail "64-bit and 32-bit registry filenames collide"
mkdir -p "$work/$_pkg"
printf 'Vendor licence fixture\n' >"$work/$_pkg/LICENSE"
printf 'ICD fixture\n' >"$work/$_pkg/nvidia.icd"
: >"$work/$_pkg/libnvidia-opencl.so.$pkgver"
create_links() { :; }
pkgname=opencl-nvidia-580xx
pkgdir=$work/$pkgname
mkdir -p "$pkgdir"
(cd "$work"; package_opencl-nvidia-580xx)
notice=$pkgdir/usr/share/licenses/$pkgname/LICENSE
[[ -f $notice && ! -L $notice ]] || fail "$pkgname has no independent licence file"
cmp "$work/$_pkg/LICENSE" "$notice" || fail "$pkgname changed the vendor notice"

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

echo "nvidia-license-test: all three OpenCL/32-bit split packages carry the vendor notice"
