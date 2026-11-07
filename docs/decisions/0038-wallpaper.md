---
title: "ADR 0038: Wallpaper"
type: decision
status: accepted
adr: 38
created: 2026-11-06
updated: 2026-11-06
tags: [decision, adr, shell, theme]
aliases: [ADR 0038, D6, Wallpaper]
---

# ADR 0038: Wallpaper

Decision map item D6. Accepted 2026-11-06.

## Decision

The **shell draws the background**: still images with transitions, and video
or animated images through Qt Multimedia. No separate wallpaper daemon.

## Options considered

| Option | Why not chosen |
|---|---|
| swww | A separate daemon, no video. |
| hyprpaper | Static only. |
| owe (Omarchy's engine) | An Omarchy project to rebuild and track. |

## Borrowed from Omarchy

The `omarchy.background` shell plugin (renderer with click handling and
transitions) and `BackgroundMedia.qml` as references for the port. The SUBCULT
rice's wallpaper-to-affinity-palette link ([[0037-theming|ADR 0037]]) hooks
in here.

## Consequences

- A shell crash also drops the wallpaper until the shell restarts; the
  session should restart the shell automatically ([[0031-session-manager|ADR 0031]]).
- Video wallpapers cost GPU and battery; on battery the shell should pause
  them or show a still frame ([[0021-power|ADR 0021]]).
- hyprlock draws its own background ([[0036-shell-components|ADR 0036]]).

Related: [[decision-map|Decision map]] · [[0037-theming|ADR 0037]]
