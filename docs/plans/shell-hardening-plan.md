---
title: "Shell hardening plan"
type: plan
status: proposed
created: 2026-11-07
updated: 2026-11-07
tags: [plan, shell]
aliases: [Shell hardening]
---

# Shell hardening — implementation plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix the defects and weak spots in the stage 1 shell that a
comparison with Omarchy's shell and dux-shell turned up, before plan 2 builds
on it.

**Architecture:** Changes stay inside the existing shell, its unit, the
Hyprland bindings and `subcult update`. Keys reach the shell through
Hyprland global shortcuts (`hl.dsp.global` → Quickshell `GlobalShortcut`)
instead of a `quickshell ipc` process per key. Keep-awake moves from a
Wayland idle inhibitor on the bar to a logind idle inhibitor. Everything is
written fresh; Omarchy and dux-shell are references only (owner, 2026-11-07).

**Tech Stack:** Quickshell 0.3.2, Qt 6.12, Hyprland 0.56 (Lua config), Go
1.27, Python 3 for the VM test.

**Spec:** this plan's Findings section, agreed with the owner on 2026-11-07,
on top of [[shell-and-look-design|Shell and look design]] and
[[0068-shell-plugin-api-v0|ADR 0068]].

## Findings (the spec for this plan)

| # | Finding | Source of the idea |
|---|---|---|
| F1 | `Commons/Clock.qml` uses `SystemClock`, which re-arms at 1 ms for the repeated hour when daylight saving ends | Omarchy `plugins/panels/clock/WallClock.qml` |
| F2 | Quickshell watches its own files: a package upgrade replacing `/usr/share/subcult/shell` reloads a half-written tree; nothing restarts the shell after an update; Quickshell's crash handler competes with `Restart=on-failure` | Omarchy `bin/omarchy-launch-shell`, dux `assets/systemd/dms.service` |
| F3 | Alt-Tab and brightness keys start a `quickshell ipc` process per key press; Alt-Tab needs a race guard | Omarchy `default/hypr/helpers.lua` (`hl.dsp.global`), `shell.qml` (`GlobalShortcut`) |
| F4 | Keep-awake holds a Wayland idle inhibitor on the first bar's window, which goes inactive when a fullscreen window covers the bar; the state is lost on shell restart | dux `Services/IdleService.qml` |
| F5 | Notification popups ignore the app's timeout, do not pause on hover, miss replaced notifications (`replaces_id`), and store bodies of any length with markup tags in them | dux `NotificationService.qml`, Omarchy `plugins/notifications/Service.qml`, `Security.js` |
| F6 | The polkit field is disabled while PAM checks, which drops its focus; Escape only works with the field focused; the failure signal is unused; no warning when another agent holds the session; the identity is not chosen when several admins exist | Omarchy `PolkitAgent.qml`, dux `PolkitService.qml` |
| F7 | OSD, popups, polkit and Alt-Tab follow the focused output live, so moving the pointer recreates them; the OSD takes clicks | Omarchy `Ui/OverlayWindow.qml`, `plugins/osd/Osd.qml` |
| F8 | The Full bar is chosen by connector name only, though connectors move between monitors on `sputnik`; Hyprland's `FALLBACK` output gets a bar | dux `Common/ShellLayout.qml`, `LayoutResolver.js` |
| F9 | The wallpaper decodes at logical size, blurry at scale 1.6 | Omarchy `plugins/background/Background.qml` |
| F10 | The recording indicator tracks every PipeWire stream node | Omarchy and Quickshell `PwNodeType` flags |
| F11 | The keyboard layout trusts the `main` flag, which power and lid buttons can hold, and ignores config reloads | Omarchy `KeyboardLayoutModel.js` |

Not in this plan: counted service references (with plan 2's network
widgets), a `subcult shell call` wrapper (keys no longer need it), a Go
daemon (not needed; see the owner thread of 2026-11-07).

## Global Constraints

- Battery rules of ADR 0054 and 0068 hold: no new polling; windows and
  helpers exist only while needed.
- Nothing copied from Omarchy or dux-shell; reimplement from the behaviour.
- `make verify`, `make shell-test shell-lint shell-index-check`,
  `tools/test/shell-headless.sh shell` and the CI `shell` job stay green; the
  VM test (`make install-test`) passes at the end.
- Commits as `SUBCULT Agent <info@subcult.tv>`, unsigned, with the
  Co-Authored-By line. One PR per task, tracked as Epic A of the
  [roadmap issue #29](https://git.subcult.tv/subculture-collective/subarchy/issues/29);
  the fresh review covers all of them in the final qualification issue.
  (Revised 2026-11-07; first written as one PR for the whole plan.)

## Review Focus

1. **A fullscreen video with keep-awake on:** the screen must not blank.
   Tested in Task 4 by checking the logind inhibitor, not the bar window.
2. **Alt-Tab tapped quickly:** commit right after next must switch, and no
   overlay may stay open. Tested in Task 3 through the global dispatcher in
   the VM.
3. **A notification replaced while shown** (e.g. a download's progress):
   popup text and history follow, the timer restarts. Tested in Task 5.
4. **A wrong polkit password:** typing again works without clicking.
   Partly testable (model); the owner checks on `sputnik`.
5. **A monitor moved to another connector:** the Full bar follows the
   monitor. Tested in Task 7 by matching description.

---

### Task 1: An epoch-aligned clock

**Files:** Modify `shell/Commons/Clock.qml`; Create
`shell/Commons/ClockModel.js`; Test `shell/tests/tst_clock.qml`.

**Interfaces:**
- `ClockModel.nextDelayMs(nowMs) -> number`: milliseconds to the next whole
  minute of epoch time, plus 50 ms slack; always between 50 and 60 050.
- `Clock` keeps `readonly property date now`; a single-shot `Timer` re-armed
  from `nextDelayMs(Date.now())` after each tick replaces `SystemClock`.

- [ ] Write `tst_clock.qml`: `test_nextDelay` (at `...:59.990` → 60 ms;
  at a whole minute → 60 050), `test_neverNegative` (any `nowMs`, including
  a value 1 h in the past relative to a previous tick, gives ≥ 50).
- [ ] `make shell-test` → FAIL (model missing).
- [ ] Implement the model and replace `SystemClock` in `Clock.qml`.
- [ ] `make shell-test shell-lint` → PASS; headless harness still ok.
- [ ] Commit `fix(shell): clock aligned to epoch minutes, not SystemClock`.

### Task 2: Supervision and restart after updates

**Files:** Modify `default/system/subcult-shell.service`,
`internal/update/update.go`, `internal/update/update_test.go`.

**Interfaces:**
- Unit: `Environment=QS_DISABLE_FILE_WATCHER=1`,
  `Environment=QS_DISABLE_CRASH_HANDLER=1`,
  `Before=xdg-desktop-autostart.target` (tray apps start after the shell's
  tray watcher), keep `Restart=on-failure`.
- `Updater.Run` records `pacman -Q subarchy` before and after the upgrade;
  when the version changed it runs `systemctl --user try-restart
  subcult-shell.service` (unprivileged) and sets `Report.ShellRestarted`.
  `Report.Summary()` says "The desktop shell was restarted."

- [ ] Write `TestRunRestartsShellWhenSubarchyChanged` and
  `TestRunLeavesShellWhenSubarchyUnchanged` with the existing fake runner.
- [ ] `go test ./internal/update/` → FAIL.
- [ ] Implement; add the three unit lines.
- [ ] `go test -race ./internal/update/ && systemd-analyze --user verify
  default/system/subcult-shell.service` → PASS.
- [ ] Commit `fix: shell survives upgrades and restarts after one`.

### Task 3: Keys through global shortcuts

**Files:** Modify `default/hypr/bindings.lua`, `shell/AltSwitch.qml`,
`shell/AltSwitchModel.js`, `shell/Osd.qml`, `shell/tests/tst_dispatch.qml`,
`tools/iso/install-test.py`.

**Interfaces:**
- Bindings: `ALT + TAB` → `hl.dsp.global("subcult:altswitch-next")`,
  `ALT + SHIFT + TAB` → `…:altswitch-prev`, the Alt release bind (same flags
  as now) → `…:altswitch-commit`; brightness keys →
  `…:brightness-up` / `…:brightness-down`. Volume keys stay `wpctl`.
- `AltSwitch.qml`: three `GlobalShortcut { appid: "subcult"; name: … }`
  acting on `onPressed`. Each name's action does not depend on whether
  Hyprland reports press or release. Remove `autoCommit` and its test. The
  IPC handler stays for tests.
- `Osd.qml`: two `GlobalShortcut`s run `brightnessctl -q set 5%+|5%-` in a
  `Process` and read the level from `/sys/class/backlight/*/brightness` and
  `max_brightness` (`FileView`, path found once at start); no
  `brightnessctl -m` and no `quickshell ipc`.
- VM test: Alt-Tab drives `hyprctl dispatch
  'hl.dsp.global("subcult:altswitch-next")'` then `…commit` (the path real
  keys take), keeps the IPC variant as a second check.

- [x] Change the VM Alt-Tab check to the global dispatcher; remove
  `test_altSwitchAutoCommit`.
- [x] `make hypr-check` and `make shell-test shell-lint` → PASS after the
  change; the VM check is run in Task 9.
- [x] Commit `fix(shell): Alt-Tab and brightness through global shortcuts`.

### Task 4: Keep-awake through logind

**Files:** Modify `shell/Commons/KeepAwake.qml`, `shell/shell.qml`,
`tools/iso/install-test.py`.

**Interfaces:**
- `KeepAwake.enabled` drives a `Process` running `systemd-inhibit
  --what=idle --who=SUBCULT --why="Keep awake" --mode=block sleep infinity`
  while true; stopping the process releases it. hypridle honours logind idle
  inhibitors unless `ignore_systemd_inhibit` is set (it is not).
- The state persists in `~/.local/state/subcult/keep-awake` (`WatchedFile`,
  `1` or absent) so a shell restart keeps it.
- Remove the `IdleInhibitor` from `shell.qml`.
- `IpcHandler subcult.shell`: add `keepAwake(on: bool): void` for tests.
- VM check: `keepAwake true` → `systemd-inhibit --list` shows `SUBCULT`;
  restart the shell → still listed; `keepAwake false` → gone.

- [ ] Add the VM check.
- [ ] Implement; harness: `keepAwake true` then `pgrep -f 'systemd-inhibit
  --what=idle --who=SUBCULT'` finds it, `false` → gone (add to
  `shell-headless.sh`).
- [ ] Harness and lint → PASS.
- [ ] Commit `fix(shell): keep-awake as a logind inhibitor that survives restarts`.

### Task 5: Notification lifetime and text

**Files:** Modify `shell/services/Notifications.qml`,
`shell/services/NotificationsModel.js`, `shell/NotificationPopups.qml`,
`shell/tests/tst_notifications.qml`, `tools/test/shell-headless.sh`.

**Interfaces:**
- `NotificationsModel.timeoutMs(expireTimeout, urgency) -> number`: critical
  → 0 (stays); `expireTimeout` ≤ 0 → 5000; otherwise clamped to 2000–30000.
- `NotificationsModel.plain(text, cap) -> string`: decode `&amp; &lt; &gt;
  &quot; &#39;` and numeric entities, strip tags, collapse whitespace, cut to
  `cap` (summary 200, body 2000, app name 64).
- The popup's timer lives on a per-popup entry in the service (not the
  delegate); hovering a card pauses it, leaving restarts it with the
  remaining time.
- A replaced notification (`summaryChanged`/`bodyChanged` on the live object)
  updates its history record and restarts its timer.

- [ ] Tests: `test_timeoutMs` (critical 0, -1 → 5000, 500 → 2000, 600000 →
  30000), `test_plain` (`"a &amp; <b>b</b>"` → `"a & b"`, caps). Harness:
  replace a notification via `Notify` with the returned id and check
  `status()` history summary follows.
- [ ] Implement.
- [ ] Tests and harness → PASS.
- [ ] Commit `fix(shell): notifications honour app timeouts, hover and replacement`.

### Task 6: Polkit dialog

**Files:** Modify `shell/PolkitDialog.qml`; Create
`shell/PolkitModel.js`; Test `shell/tests/tst_polkit.qml`.

**Interfaces:**
- `PolkitModel.pickIdentity(identities, userName) -> index`: the identity
  whose name equals the current user, else 0.
- The field is `readOnly` while PAM checks, never disabled; a top-level
  `FocusScope` with `Keys.priority: Keys.BeforeItem` handles Escape and Enter
  wherever focus is.
- On `authenticationFailed`: show "Wrong password, try again." for 2 s and
  refocus the field (`Qt.callLater`).
- When `PolkitAgent.isRegistered` stays false, log one warning naming the
  likely cause (another agent holds the session).
- Selecting the identity uses `flow.selectedIdentity` before the first
  response.

- [ ] Test `test_pickIdentity` (current user second → 1; absent → 0; empty → 0).
- [ ] Implement.
- [ ] Tests and lint → PASS.
- [ ] Commit `fix(shell): polkit dialog keeps focus and picks the right identity`.

### Task 7: Overlays and the Full bar

**Files:** Modify `shell/Osd.qml`, `shell/NotificationPopups.qml`,
`shell/PolkitDialog.qml`, `shell/AltSwitch.qml`, `shell/Commons/LayoutModel.js`,
`shell/Bar.qml`, `shell/shell.qml`, `shell/tests/tst_models.qml`.

**Interfaces:**
- `LayoutModel.pickScreen(names, focused, current) -> string`: keep
  `current` while it exists; else the focused output; else the first.
  Overlays bind `screen` to the result, evaluated when they open and when
  outputs change, not on focus moves.
- `Osd.qml`: `mask: Region {}` so it takes no clicks.
- `LayoutModel.modeFor(output, cfg, outputs)` also matches `cfg.primary`
  and `cfg.full` against the output's description (monitor make and model);
  outputs are passed as `{name, description}`.
- `shell.qml` and overlays skip outputs named `FALLBACK` or with no name.

- [ ] Tests: `test_pickScreenKeepsCurrent`, `test_pickScreenFallsBack`,
  `test_modeForDescription`, `test_fallbackIgnored`.
- [ ] Implement.
- [ ] Tests, lint, harness → PASS.
- [ ] Commit `fix(shell): overlays stay on their output; Full bar by monitor`.

### Task 8: Wallpaper, recording indicator, keyboard layout

**Files:** Modify `shell/Background.qml`,
`shell/widgets/indicators/Widget.qml`, `shell/widgets/indicators/Model.js`,
`shell/widgets/keyboard-layout/Model.js`,
`shell/widgets/keyboard-layout/Widget.qml`, their tests.

**Interfaces:**
- Background: `sourceSize` × the screen's `devicePixelRatio`, `cache: false`.
- Indicators: `Model.recording(nodes)` takes `{type}` flags: a node with
  `Video` and `Stream` set whose `VideoSink` bit marks a consumer; drop the
  `PwObjectTracker`. Confirm the flag combination for a screen recorder in
  the VM (Task 9) before relying on it.
- Keyboard layout: `Model.fromDevices(json, eventKeyboard)` prefers the
  keyboard named in the last `activelayout` event, skips names matching
  `power|lid|video-bus|sleep|button|hid-events|virtual`, then the first left;
  refresh also on `configreloaded`.

- [ ] Tests for each model change (event keyboard wins; power button
  skipped; recording flags).
- [ ] Implement.
- [ ] Tests, lint, harness → PASS.
- [ ] Commit `fix(shell): sharp wallpaper, cheaper recording mark, sturdier layout`.

### Task 9: VM run, review, docs

- [ ] Rebuild the package; `make install-test` from a fresh disk → all
  checks pass, including the global-dispatch Alt-Tab and the logind
  keep-awake checks; read the recording-flag probe output.
- [ ] Fresh reviewer on the branch; one fix pass for Critical and Important.
- [ ] Update `shell/README.md` (keys via global shortcuts; keep-awake via
  logind), ADR 0068 "As built" if the contract changed, roadmap.
- [ ] Open the PR; merge when CI is green.

Related: [[shell-stage-1-core-plan|Shell stage 1 core plan]] · [[shell-and-look-design|Shell and look design]] · [[0068-shell-plugin-api-v0|ADR 0068]]
