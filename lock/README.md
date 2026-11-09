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
  the prompt that opens on the first key.
- `LockModel.js` holds the state and key handling, tested in `tests/`.

`subcult lock` starts the unit by hand; hypridle starts it on idle through
`loginctl lock-session`, from the config `subcult-idle` generates out of
`~/.config/subcult/idle.json` (the settings panel's Idle group). Still to
come: the screensaver loop (#96) and fingerprint unlock (#117).
