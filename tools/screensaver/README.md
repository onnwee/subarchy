# screensaver

`capture.sh` records `ttfx` effects under `script`; the package renders the
compressed captures in `branding/screensaver/` into VP9 WebM loops and PNG
stills. The locked session only plays video; it never runs `ttfx`.

The shipped captures use a 96×27 terminal and the SUBCULT text in
`branding/screensaver/subcult.txt`: beams, decrypt and matrix. To replace
one, record at that size, gzip its `.log` and `.tm`, then rebuild. The
captures contain terminal output and timing only.

```bash
python3 bin/subcult-screensaver-render --out build/screensaver \
  --palette default/theme/palette.json --captures branding/screensaver
```

The renderer needs pyte, Pillow, ffmpeg and a monospace font. It prefers
JetBrainsMono Nerd Font, which Subarchy installs and the package build
depends on, so the shipped art and user renders use the same font. It streams
frames to ffmpeg at 960×540, 30 fps by default. ANSI colours use the palette;
recorded truecolour gradients keep their brightness and take its lavender.
ttfx draws at the terminal's top left; the renderer centres the cells any
frame draws on. The last frame becomes still art. Input hashes include the palette, captures,
font file, renderer and output settings; unchanged inputs do nothing. A lock serialises
renders, outputs replace atomically, and the index publishes last. A render
stopped part-way (a restart for a new theme, or the unit's time limit) leaves
its `.render-*` work directory; the next render removes it.

The shell watches the user's palette file, which Pult writes. After a
750 ms debounce it restarts the low-priority `subcult-screensaver.service`
in the background, replacing any render of a previous theme. A session
start also checks for an existing palette.
`subcult screensaver render --user` does the same by hand. Both write into
`~/.cache/subcult/screensaver` (or `$XDG_CACHE_HOME/subcult/screensaver`).
The lock prefers that completed index over `/usr/share/subcult/screensaver`.
When the user's palette gives the same colours as the default one, `--user`
renders nothing and removes its cached loops, so the lock uses the shipped
art. The unit is `Type=exec`, so a render never holds back
`graphical-session.target` or the bar.

The standalone lock chooses one loop per lock, stops its decoder on input,
and shows the password prompt while remaining locked. On battery or with
motion off it uses the still. Keyboard, pointer movement, buttons and scroll
open the prompt. The motion setting is shared with the shell and Hyprland.

The original spike on Sputnik, 2026-11-08, decoded a 9.8 s matrix capture
in software using 0.09 s CPU at 800×480 and 0.49 s at 1920×1152. These are
spike measurements, not a budget claim for the shipped captures.
