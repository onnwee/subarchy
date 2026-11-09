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
  off; opening the prompt destroys the decoder. Its colours are the shell's tokens
  (ADR 0037): `shell.qml` reads Subarchy's palette under the user's
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
click and Tab; the visible prompt shows its focus and an empty-field label.

Fingerprint unlock remains in #117.
