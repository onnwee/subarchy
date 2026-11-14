#!/usr/bin/env bash
# Builds the shipped art sets for the system screens (ADR 0052) into
# <out>/<set>/: boot.png (the boot splash), login.png and lock.png (the
# greeter and lock logos, ink centred on the master lockup's 2000x520
# canvas) and title.txt (the boot menu's branding and the alt text).
#   subcult   the SUBCULT mark at boot, the master lockup after it
#   subarchy  the Subarchy wordmark everywhere
# The defaults use subarchy at boot and subcult after it
# (internal/systheme.DefaultScreens).
# Usage: tools/branding/screens.sh <out>
set -euo pipefail
root=$(cd "$(dirname "$0")/../.." && pwd)
out=${1:?out}
tmp=$(mktemp --suffix=.png)
trap 'rm -f -- "$tmp"' EXIT
mkdir -p "$out/subcult" "$out/subarchy"

rsvg-convert -w 240 -o "$out/subcult/boot.png" "$root/branding/marks/mark-dark.svg"
"$root/tools/branding/lockup-png.sh" 2000 "$out/subcult/login.png"
cp "$out/subcult/login.png" "$out/subcult/lock.png"
printf 'SUBCULT // Subarchy\n' >"$out/subcult/title.txt"

# The wordmark's cells are 10 units: 468 and 1560 pixels wide keep them on
# whole pixels (6 and 20).
rsvg-convert -w 468 -o "$out/subarchy/boot.png" "$root/branding/marks/subarchy-wordmark-dark.svg"
rsvg-convert -w 1560 -o "$tmp" "$root/branding/marks/subarchy-wordmark-dark.svg"
magick "$tmp" -background none -gravity center -extent 2000x520 "PNG32:$out/subarchy/login.png"
cp "$out/subarchy/login.png" "$out/subarchy/lock.png"
printf 'SUBARCHY\n' >"$out/subarchy/title.txt"
