---
title: "ADR 0036: Shell components, lock and idle"
type: decision
status: accepted
adr: 36
created: 2026-11-06
updated: 2026-11-20
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
- 2026-11-12: fingerprint unlock (GitHub #93, Gitea #117). The lock runs a
  second PAM check, `/etc/pam.d/subcult-lock-fingerprint`, beside the
  unchanged password stack, and only when `fprintd-list` reports a finger
  enrolled for the user; otherwise no fingerprint line shows and the
  module never runs. Either check unlocks. The stack is `pam_fprintd`
  between `pam_faillock` preauth and authsucc: a password lockout locks the
  finger out too, a fingerprint unlock clears the count, and wrong fingers
  are not counted. `subcult setup fingerprint` installs fprintd, enrolls
  and verifies a finger, and edits no PAM file. The headless test unlocks
  with a stand-in fingerprint stack beside a refused password and with the
  password while the fingerprint check waits; a stand-in stack that fails
  at once, and one that asks for a password, never unlock. Not yet tested:
  a real reader, and fprintd after suspend.

- 2026-11-15 UTC, Kvant: #211 reproduced with Quickshell 0.3.2 and a
  playing video. A minimal concurrent-PAM probe hung at attempt 309; both
  workers were alive in `futex_wait_queue`, with stacks through
  `__lll_lock_wait_private`, `__syslog_chk` and `pam_syslog`. The UI's
  event loop remained responsive. This matches the process-boundary
  concern in [upstream #964](https://github.com/quickshell-mirror/quickshell/issues/964);
  it does not identify the workers from the earlier CI failures.
  `PamSession.qml` now executes a separate, unprivileged Python/Linux-PAM
  helper for each check, instead of forking PAM inside the renderer.
  Password and fingerprint stacks, pacing and success decisions stay as
  above. The same graphical probe completed 2,000 attempts with the
  helper. Real PAM and QML transport tests cover refusal, malformed
  responses, missing/crashed helpers, cancellation and immediate retry.
  Physical fingerprint acceptance remains pending on #93.

- 2026-11-15 UTC, Kvant: an offline-installed, encrypted Subarchy VM with
  Linux-PAM 1.7.3 and Quickshell 0.3.2 passed 21 assertions against the
  candidate lock. The helper ran as the installed user (uid 1000), without
  setuid, and the password PAM policy matched the shipped file. A wrong
  password kept the session locked and retained text typed during the
  check for a retry without a click. Escape cancelled an active real-PAM
  check; an immediate correct retry unlocked and reaped the old helper.
  Killing a helper kept the session locked, and a correct retry recovered.
  The probe also caught a prompt-ordering regression: responding cleared
  `responseRequired` before the lock classified the PAM message, so
  `Password:` became the retry error. Classifying the message first fixes
  it; the graphical regression test now asks for a response before
  refusing, and checks the retry message.

- 2026-11-20, from the record, nothing retested: #93 closed on 2026-11-15
  on a real-reader pass on `sputnik` (core `0.0.0-616`, Goodix reader
  `27c6:63ac`, `fprintd 1.94.5-2`). The owner enrolled a finger; a touch
  unlocked the real lock without a password; on a second lock a wrong then
  a correct password unlocked. This replaces "Physical fingerprint
  acceptance remains pending on #93" in the 2026-11-15 note above. Still
  untested on a real reader: fprintd after suspend and resume, a wrong
  finger, and Escape while a check waits (checklist K11). The owner
  reinstalled on 2026-11-16, which erased the enrolment, so the pass has
  not been repeated on core `0.0.0-638`. Dated record:
  [[first-install#Fingerprint unlock (#93)]].

Related: [[decision-map|Decision map]] · [[0034-shell-toolkit|ADR 0034]] · [[0035-plugin-api|ADR 0035]]
