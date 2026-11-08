#!/usr/bin/env bash
# Records one ttfx effect on a text to a terminal capture with timings
# (ADR 0036, spike #47): `script` gives the effect a pseudo-terminal of the
# given size and logs its output and the delay before each chunk.
# Usage: tools/screensaver/capture.sh <effect> <text-file> <out-prefix> [cols] [rows] [ttfx options...]
# Then: tools/screensaver/render.py <out-prefix>.log <out-prefix>.tm frames/ 30 [cols] [rows]
set -euo pipefail
effect=${1:?effect}; text=${2:?text file}; out=${3:?out prefix}
cols=${4:-80}; rows=${5:-24}
shift 5 2>/dev/null || shift $#
script -q --log-out "$out.log" --log-timing "$out.tm" \
  -c "stty cols $cols rows $rows; ttfx $effect $* <'$text'" >/dev/null
echo "captured $out.log ($(wc -l <"$out.tm") chunks)"
