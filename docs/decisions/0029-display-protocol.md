---
title: "ADR 0029: Display protocol"
type: decision
status: accepted
adr: 29
created: 2026-11-06
updated: 2026-11-06
tags: [decision, adr, session]
aliases: [ADR 0029, L1, Wayland]
---

# ADR 0029: Display protocol

Decision map item L1. Accepted 2026-11-06 as implied by the compositor
choice; the owner did not object.

## Decision

**Wayland only.** X11 apps run through **Xwayland**. There is no X11
session.

## Consequences

- Screen capture, input injection and global shortcuts go through Wayland
  protocols and XDG portals ([[0033-portals|ADR 0033]]).
- Tools that assume X11 (`xdotool`, `xrandr`) are replaced: `wtype`,
  `hyprctl`, `wlr-randr`.

Related: [[decision-map|Decision map]] · [[0032-compositor|ADR 0032]]
