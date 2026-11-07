---
title: "ADR 0038: Wallpaper"
type: decision
status: accepted
adr: 38
created: 2026-11-06
updated: 2026-11-07
tags: [decision, adr, shell, theme]
aliases: [ADR 0038, D6, Wallpaper]
---

# ADR 0038: Wallpaper

Decision map item D6. Accepted 2026-11-06.

## Decision

The **shell draws the background**. The default is a **still image**. Video
and animated wallpapers are **opt-in** through Qt Multimedia and **pause on
battery**, showing a still frame. No separate wallpaper daemon.

Revised 2026-11-06 under [[0054-lightweight-battery-first|ADR 0054]].

## Wallpapers that ship

The owner's own wallpapers (the owner holds the rights), starting with the 109
images in the `subcult-minimal` theme on `sputnik`
(`~/.config/omarchy/themes/subcult-minimal/backgrounds/`, 254 MB, read
2026-11-07):

- 102 illustrations at 1586×992 or 1585×992 (series such as acid, ghost tape,
  riso, midnight, botanical, noir, cosmic, y2k, punk, broadcast, gouache);
- the seven SUBCULT poster wallpapers from the rice at 2560×1440.

The 1586×992 images look soft on `sputnik`'s 3456×2160 panel and the
2560×1440 monitor, so they are upscaled before shipping. They ship as a
separate `subarchy-wallpapers` package built from an assets store (Git LFS
or release files), not from this Git repository.

### First set: 25 at 4K (2026-11-07)

On the owner's request, 25 images were picked across the series and upscaled
on `sputnik`; the other 84 wait:
Real-ESRGAN `realesrgan-x4plus` (ncnn-vulkan, Intel Iris Xe) at 4×, then
ImageMagick Lanczos to exactly 3840×2400 (16:10, the illustrations' own
ratio), 8-bit PNG, metadata stripped. Output: 262 MB in
`~/Pictures/subcult-wallpapers-4k/`, numbered in rotation order:

| # | Image | # | Image |
|---|---|---|---|
| 01 | acid-negative-space | 14 | noir-platform-terminal |
| 02 | acid-hinge-cut | 15 | cosmic-orrery-ferry |
| 03 | ghost-tape-tidal-current | 16 | cosmic-desert-eclipse-station |
| 04 | riso-spool-rainy-listening | 17 | ova-window-shift |
| 05 | midnight-tide-archive | 18 | ova-dockside-dawn |
| 06 | midnight-bench-stencil | 19 | citypop-beach-broadcast |
| 07 | lunar-stitched-mark | 20 | citypop-first-light-balcony |
| 08 | moth-botanical-sigil | 21 | y2k-last-connection |
| 09 | cel-arkhiv-last-train | 22 | ink-listening-carriage |
| 10 | cel-arkhiv-harbor-crossing | 23 | punk-bookmobile-gig |
| 11 | watercolor-after-the-rain | 24 | broadcast-rooftop-transmitter |
| 12 | watercolor-winter-print-night | 25 | gouache-window-practice |
| 13 | noir-phosphor-monogram | | |

01 is the default. The owner has not yet looked at the upscaled results for
artefacts; review them before packaging.

## Options considered

| Option | Why not chosen |
|---|---|
| swww | A separate daemon, no video. |
| hyprpaper | Static only. |
| owe (Omarchy's engine) | An Omarchy project to rebuild and track. |

## Borrowed from Omarchy

The `omarchy.background` shell plugin (renderer with click handling and
transitions) and `BackgroundMedia.qml` as references for the port. Theme Tender
themes carry colours only ([[0037-theming|ADR 0037]]), so wallpapers are
chosen separately; SUBCULT wallpapers ship with the default theme.

## Consequences

- A shell crash also drops the wallpaper until the shell restarts; the
  session should restart the shell automatically ([[0031-session-manager|ADR 0031]]).
- Video wallpapers cost GPU and battery; on battery the shell should pause
  them or show a still frame ([[0021-power|ADR 0021]]).
- The lock screen draws its own background and screensaver ([[0036-shell-components|ADR 0036]]).

Related: [[decision-map|Decision map]] · [[0037-theming|ADR 0037]]
