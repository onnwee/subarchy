# lock

Subarchy's lock screen (ADR 0036): a Quickshell program of its own,
installed to `/usr/share/subcult/lock` and run by `subcult-lock.service`,
apart from the desktop shell, so a shell crash cannot unlock the session.

- `shell.qml` locks the session as it starts (`WlSessionLock`), checks the
  password through PAM (`/etc/pam.d/subcult-lock`; `SUBCULT_LOCK_PAM` and
  `SUBCULT_LOCK_PAM_DIR` point the tests at a permit stack) and quits once
  unlocked. `subcult.lock status` over IPC reports the state; nothing
  unlocks over IPC.
- `LockView.qml` is one output's surface: the SUBCULT lockup, the clock, and
  the prompt that opens on keyboard or pointer input. Until then it plays
  a pre-rendered SUBCULT loop, or shows its still on battery or with motion
  off (and when the loop cannot play); opening the prompt destroys the
  decoder. The pointer is hidden over the lock, which has nothing to
  click. Its colours are the shell's tokens (ADR 0037): `shell.qml` reads Subarchy's palette under the user's
  `~/.config/subcult/theme/palette.json`, the file Pult writes, through the
  shell's `ThemeModel.js` (a copy here, since Quickshell refuses imports
  outside the program; `make shell-index-check` keeps the two equal), once
  at start.
- `LockModel.js` holds the state and key handling, tested in `tests/`.

`subcult lock` starts the unit by hand; hypridle starts it on idle through
`loginctl lock-session`, from the config `subcult-idle` generates out of
`~/.config/subcult/idle.json` (the settings panel's Idle group). The package
ships the screensaver loops and their captures; the shell starts a background
render when Pult writes the palette. The next lock prefers the user's completed render in
`~/.cache/subcult/screensaver`. See [the render pipeline](../tools/screensaver/README.md).
The idle configuration sets `inhibit_sleep = 3`: sleep waits for the Wayland
lock notification because Hypridle's automatic detection recognizes Hyprlock
by name. DPMS commands explicitly use `action`, so repeated wake requests keep
the display on. The password handler reclaims keyboard focus on activation,
click and Tab.

If the lock program dies while locked, Hyprland keeps the session locked and
the unit starts a replacement that takes the lock over; the Hyprland
defaults set `misc.allow_session_lock_restore` for that
([ADR 0070](../docs/decisions/0070-lock-crash-recovery.md), which also has
the recovery from a text console when the replacement keeps failing).

## Fingerprint

Fingerprint unlock (#93, [ADR 0023](../docs/decisions/0023-authentication.md))
is a second PAM check beside the password's, never part of it:
`/etc/pam.d/subcult-lock` stays the password stack, and
`/etc/pam.d/subcult-lock-fingerprint` holds `pam_fprintd` between two
`pam_faillock` lines. At start the
lock asks `fprintd-list` (fprintd's D-Bus `GetDevices` and
`ListEnrolledFingers`) whether a reader has a finger enrolled for the user.
Only then does it run the fingerprint check and show "Or touch the
fingerprint reader" under the field; with no reader, no finger, no fprintd
or no PAM file there is no fingerprint line and `pam_fprintd` never runs.
An unknown answer (fprintd still starting) is asked again, from 2 s up to a
minute apart.

Both checks run at once, and the first to succeed unlocks. A touch works
while the screensaver plays. A check that ends without a match (three
touches, or 30 seconds) starts again at once; checks that fail straight
away back off up to 40 s, and after three the line says the reader is not
answering. The password works throughout. `FingerprintModel.js` holds the
probe parsing, the pacing and the text, tested in `tests/`;
`SUBCULT_LOCK_FINGERPRINT_PAM` points the headless test at a stand-in stack.

Faillock ([ADR 0063](../docs/decisions/0063-security-hardening.md)): while
password failures have the account locked, the fingerprint check is refused
too, and backs off like a reader that fails. A fingerprint unlock clears the
failure count, as a password unlock does. Wrong fingers are not counted, so
they cannot lock the password out; as with hyprlock, there is no limit on
touches beyond pam_fprintd's three per check.

The "not recognised" line and the reader's recovery from "not answering"
match pam_fprintd's English messages. In another language the line keeps
saying "Or touch the fingerprint reader" after a wrong finger, and the
password and the fingerprint still unlock.

The check runs for as long as the lock is up, through the screensaver and
display-off, so fprintd keeps the reader claimed. Whether that stops USB
autosuspend or upsets readers after suspend is not tested yet.

`subcult setup fingerprint` installs fprintd where `subcult hw fingerprint`
finds a reader, enrolls a finger with `fprintd-enroll` and checks it with
`fprintd-verify`; `subcult setup fingerprint remove` deletes the enrolled
fingers. It edits no PAM file, so sudo and polkit still ask for the
password.
