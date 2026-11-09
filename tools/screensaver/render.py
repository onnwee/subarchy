#!/usr/bin/env python3
"""Replays a `script` capture of a terminal effect through a terminal
emulator (pyte) and draws one PNG per frame with Pillow (ADR 0036, spike
#47). ffmpeg then makes the loop:

  ffmpeg -framerate 30 -i frames/f%05d.png -c:v libvpx-vp9 -b:v 0 -crf 34 -pix_fmt yuv420p loop.webm

Usage: render.py <capture.log> <timing.tm> <frames-dir> <fps> [cols] [rows] [cell-width] [cell-height]
Needs python-pyte and python-pillow.
"""
import os
import sys

import pyte
from PIL import Image, ImageDraw, ImageFont

INK, PAPER = "#100B19", "#F0ECE4"
NAMED = {"black": "#06040A", "red": "#D52032", "green": "#00FF88", "yellow": "#F6D447", "blue": "#7799FF",
         "magenta": "#8B5CF6", "cyan": "#4FD6C8", "white": PAPER, "brightblack": "#5E5570", "brightwhite": PAPER}
FONTS = ["/usr/share/fonts/TTF/JetBrainsMonoNerdFont-Regular.ttf", "/usr/share/fonts/TTF/JetBrainsMono-Regular.ttf",
         "/usr/share/fonts/TTF/DejaVuSansMono.ttf"]


def main() -> int:
    if len(sys.argv) < 5:
        print(__doc__, file=sys.stderr)
        return 2
    capture, timing, outdir, fps = sys.argv[1], sys.argv[2], sys.argv[3], float(sys.argv[4])
    cols = int(sys.argv[5]) if len(sys.argv) > 5 else 80
    rows = int(sys.argv[6]) if len(sys.argv) > 6 else 24
    cell_w = int(sys.argv[7]) if len(sys.argv) > 7 else 10
    cell_h = int(sys.argv[8]) if len(sys.argv) > 8 else 20
    font = None
    for path in FONTS:
        if os.path.exists(path):
            font = ImageFont.truetype(path, int(cell_h * 0.85))
            break
    if font is None:
        font = ImageFont.load_default()
    data = open(capture, "rb").read()
    data = data[data.index(b"\n") + 1:]  # script's header line
    chunks = [(float(a), int(b)) for a, b in (line.split() for line in open(timing) if line.strip())]
    screen = pyte.Screen(cols, rows)
    stream = pyte.ByteStream(screen)
    os.makedirs(outdir, exist_ok=True)

    def colour(c: str) -> str:
        if c == "default":
            return PAPER
        if len(c) == 6:
            return "#" + c
        return NAMED.get(c, PAPER)

    def draw(n: int) -> None:
        img = Image.new("RGB", (cols * cell_w, rows * cell_h), INK)
        d = ImageDraw.Draw(img)
        for y in range(rows):
            line = screen.buffer[y]
            for x in range(cols):
                ch = line[x]
                if ch.data.strip():
                    d.text((x * cell_w, y * cell_h), ch.data, fill=colour(ch.fg), font=font)
        img.save(f"{outdir}/f{n:05d}.png")

    pos, t, frame, next_t = 0, 0.0, 0, 0.0
    for delay, size in chunks:
        t += delay
        while next_t <= t:
            draw(frame)
            frame += 1
            next_t += 1 / fps
        stream.feed(data[pos:pos + size])
        pos += size
    draw(frame)
    print(f"{frame + 1} frames, {t:.2f} s, {cols * cell_w}x{rows * cell_h}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
