# screensaver

The pipeline that turns a `ttfx` text effect into a video loop for the lock
screen (ADR 0036; spike #47, 2026-11-08). The effect never runs on the
locked machine: the loop is rendered when the art or theme changes and the
lock program plays it.

1. `capture.sh <effect> <text> <prefix> [cols] [rows] [ttfx options]` runs the
   effect in a pseudo-terminal of that size under `script`, which logs the
   output and the delay before each chunk.
2. `render.py <prefix>.log <prefix>.tm frames/ 30 [cols] [rows] [cell px]`
   replays the capture through pyte, a terminal emulator in Python, and draws
   a PNG per frame with Pillow in the palette (needs `python-pyte`,
   `python-pillow`).
3. `ffmpeg -framerate 30 -i frames/f%05d.png -c:v libvpx-vp9 -b:v 0 -crf 34 -pix_fmt yuv420p loop.webm`

Measured on `sputnik` with `ttfx matrix --rain-time 8` on three lines, 80×24
cells, 9.8 s at 30 fps:

| Output | Size | Decode (ffmpeg, software) |
|---|---|---|
| VP9 800×480 | 54 KB | 0.09 s CPU for 9.8 s: under 1 % of a core |
| VP9 1920×1152 | 107 KB | 0.49 s CPU for 9.8 s: about 5 % of a core |
| H.264 1920×1152 | 128 KB | 0.92 s CPU for 9.8 s: about 9 % of a core, or hardware decode where VA-API has it |

Decision: VP9 in WebM at the output's size, 30 fps, loops of about ten
seconds; the lock program plays it with Qt Multimedia. On battery the lock
shows still art instead (ADR 0036), so the decode cost is an AC cost.
