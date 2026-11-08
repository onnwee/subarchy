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

- **The lock screen is its own small Quickshell program**, running as a
  separate process from the main shell, so a shell crash cannot unlock the
  session or take the lock down. It uses the Wayland session-lock protocol.
- **The screensaver plays inside the lock screen.** On idle the session
  locks and the lock screen shows the SUBCULT screensaver until any input,
  then the password or fingerprint prompt. The session stays locked the whole
  time. On battery the lock screen shows still art instead
  ([[0054-lightweight-battery-first|ADR 0054]]).
- The screensaver is **pre-rendered loops**: `ttfx` text effects on the
  SUBCULT art rendered to short video files when the art or theme changes,
  then played by the lock screen.
- **Motion follows one setting.** `~/.config/subcult/motion.json` (`auto`,
  `on`, `off`; `auto` is on on AC and off on battery) is read by the shell,
  by the Hyprland defaults and by the lock screen, so the screensaver and
  the lock's own transitions stop on battery too (2026-11-08).
- **hypridle** for idle handling: lock with screensaver, display off,
  suspend.

Revised 2026-11-07: the lock was first hyprlock. The owner asked for the idle
lock to stay on while the screensaver runs until input; under Wayland's lock
protocol only lock surfaces are visible once locked, so the screensaver has to
be drawn by the lock screen, which hyprlock cannot do.

## Options considered

| Option | Why not chosen |
|---|---|
| Everything inside the shell (Omarchy 4.x) | A shell crash would also take down the lock screen. |
| hyprlock | Cannot play the screensaver animation (first choice, revised 2026-11-07). |
| Screensaver before the lock only (Omarchy) | Omarchy's idle service skips the screensaver once locked; the owner wants both. |
| Live QML text effects | More work and more GPU while running than playing pre-rendered loops. |

## Borrowed

- `sputnik` already runs hypridle (`~/.config/hypr/hypridle.conf`):
  display off at seven minutes, suspend at fifteen, lock before display off,
  with AC docking exceptions.
- Omarchy's notification, OSD and clipboard plugins as references for the
  ported shell components.
- Omarchy's QML lock (`shell/plugins/lock`: `LockView.qml`, `Service.qml`,
  `FingerprintModel.js`, separate password and fingerprint PAM flows) as the
  base for the standalone lock program.
- Omarchy's screensaver (`omarchy-screensaver`: random `ttfx` effects on the
  branding text) as the source of the effects to pre-render.

## Consequences

- The lock program needs its own theme entry in Theme Tender
  ([[0037-theming|ADR 0037]]); fingerprint unlock uses its PAM flow
  ([[0023-authentication|ADR 0023]]).
- Rendering the loops needs `ttfx` and a way to capture terminal output to
  video; SUBCULT loops ship prebuilt, and re-rendering runs only when the art
  or theme changes.
- The owner's `lock-explorer` lock designs do not carry over directly.
- Idle settings live in hypridle config, edited through a settings panel.

Related: [[decision-map|Decision map]] · [[0034-shell-toolkit|ADR 0034]] · [[0035-plugin-api|ADR 0035]]
