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

## Progress

- 2026-11-08: the lock program and idle (issue #46). `lock/` is its own
  Quickshell program: a session-lock surface per output with the SUBCULT
  lockup and the clock, a prompt that appears on the first key, PAM through
  `/etc/pam.d/subcult-lock`, and a status IPC. It runs in
  `subcult-lock.service`, apart from the shell and restarted if it dies, so
  a shell crash leaves the session locked. `subcult-idle.service` runs
  hypridle with a config generated from `~/.config/subcult/idle.json` (lock
  7 min, display off 10, suspend 15 by default; the settings panel's Idle
  group writes the file and `subcult idle apply` restarts the service).
  `subcult lock` locks by hand. The VM test locks, kills the shell, finds
  the session still locked, types the password and sees the unlock; the
  headless test does the same under sway with a permit PAM stack. Not yet:
  the screensaver loop (#96) and fingerprint (#117).
- 2026-11-08: spike #47, how a `ttfx` effect becomes a video loop:
  `tools/screensaver/capture.sh` records the effect under `script` with
  timings, `render.py` replays it through pyte and draws the frames with
  Pillow in the palette, ffmpeg encodes VP9 WebM. A 9.8 s matrix loop at
  1920×1152 is 107 KB and costs about 5 % of one core to decode in software
  (under 1 % at 800×480; H.264 about 9 %, or hardware decode). The lock
  plays VP9 WebM loops of about ten seconds with Qt Multimedia; on battery
  it shows still art, as decided above.

Related: [[decision-map|Decision map]] · [[0034-shell-toolkit|ADR 0034]] · [[0035-plugin-api|ADR 0035]]
