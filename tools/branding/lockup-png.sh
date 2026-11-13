#!/usr/bin/env bash
# Renders the unchanged SUBCULT master lockup (ADR 0052) to a PNG for the
# greeter and the lock, with its ink centred on the canvas. The master's
# 1000x260 canvas leaves its right part empty, and both screens centre the
# image, so the mark sat left of the "Subarchy" caption and of the clock.
# librsvg renders it: Qt SVG omits the master's nested SVG image.
# Usage: tools/branding/lockup-png.sh <width> <out.png>
set -euo pipefail
root=$(cd "$(dirname "$0")/../.." && pwd)
width=${1:?width}
out=${2:?out.png}
height=$((width * 26 / 100))
tmp=$(mktemp --suffix=.png)
trap 'rm -f -- "$tmp"' EXIT
FONTCONFIG_FILE=${FONTCONFIG_FILE:-$root/branding/fontconfig.xml} \
  rsvg-convert -w "$width" -o "$tmp" "$root/branding/studio/logos/lockup-dark.svg"
magick "$tmp" -trim +repage -background none -gravity center -extent "${width}x${height}" "$out"
