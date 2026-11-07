---
title: "ADR 0036: Shell components, lock and idle"
type: decision
status: accepted
adr: 36
created: 2026-11-06
updated: 2026-11-06
tags: [decision, adr, shell, security]
aliases: [ADR 0036, D3, D4, Lock screen, Idle]
---

# ADR 0036: Shell components, lock and idle

Decision map items D3 and D4. Accepted 2026-11-06.

## Decision

Inside the Quickshell shell:

- bar (per-monitor layouts, from `omarchy-monitor-bar`)
- launcher and menus (Raycast-style, see [[0057-launcher|ADR 0057]])
- notifications daemon and history
- on-screen display (volume, brightness, status)
- polkit authentication dialog ([[0023-authentication|ADR 0023]])
- clipboard history, emoji picker and similar overlays

Separate programs:

- **hyprlock** for the lock screen
- **hypridle** for idle handling: dim, lock, display off, suspend

## Options considered

| Option | Why not chosen |
|---|---|
| Everything inside the shell (Omarchy 4.x) | A shell crash would also take down the lock screen. |

## Borrowed

- `sputnik` already runs hypridle (`~/.config/hypr/hypridle.conf`):
  display off at seven minutes, suspend at fifteen, lock before display off,
  with AC docking exceptions.
- Omarchy's notification, OSD and clipboard plugins as references for the
  ported shell components.

## Consequences

- hyprlock needs its own theme matching the shell; fingerprint unlock goes
  through hyprlock's PAM support ([[0023-authentication|ADR 0023]]).
- The owner's `lock-explorer` lock designs do not carry over directly.
- Idle settings live in hypridle config, edited through a settings panel.

Related: [[decision-map|Decision map]] · [[0034-shell-toolkit|ADR 0034]] · [[0035-plugin-api|ADR 0035]]
