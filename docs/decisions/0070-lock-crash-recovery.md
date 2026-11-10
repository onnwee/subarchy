---
title: "ADR 0070: Lock crash recovery"
type: decision
status: accepted
adr: 70
created: 2026-11-10
updated: 2026-11-10
tags: [decision, adr, security, lock]
aliases: [ADR 0070, Lock crash recovery]
---

# ADR 0070: Lock crash recovery

Accepted 2026-11-10 for issue #230. Adds to
[[0036-shell-components|ADR 0036]], which made the lock its own program
that systemd restarts if it dies.

## Context

On Sputnik on November 9, 2026 the lock program stalled and was replaced by
hand. Hyprland 0.57.1 refused every replacement: its
`misc:allow_session_lock_restore` setting defaults to off, and a new lock
client then gets a fatal protocol error. `subcult-lock.service` used up its
restart limit and the session stayed locked with no prompt. Turning the
setting on for that session let a replacement report `locked` and `secure`,
and the owner unlocked with the password.

The unit promised a recovery the compositor's default did not allow.

## Decision

Subarchy's Hyprland defaults set `misc.allow_session_lock_restore = true`.

- If the lock program dies, Hyprland keeps the session locked and draws its
  own notice in place of the desktop.
- `subcult-lock.service` (`Restart=on-failure`, one second apart) starts a
  replacement, which takes the lock over and asks for the password as usual.
- Nothing unlocks without PAM. There is no IPC unlock, and nothing clears a
  dead lock automatically.

What the setting gives up: any Wayland client of the session may take over a
lock whose owner died, and could then release it. Such a client already
runs as the user and can read the user's files, so this adds nothing for it.
Someone at the keyboard of a locked machine cannot start a client.

## Recovery when the replacement keeps failing

After five failed starts within ten seconds systemd stops trying. The
session is still locked. From a text console (Ctrl+Alt+F3), signed in as the
same user:

```bash
journalctl --user -b -u subcult-lock.service   # why it failed
systemctl --user reset-failed subcult-lock.service
systemctl --user start subcult-lock.service
```

Back on the graphical console (Ctrl+Alt+F1, or the number the session
uses), the prompt takes the password.

While no lock program holds the lock, Hyprland draws a notice with its own
way out: `hyprctl --instance 0 eval 'hl.clear_crashed_lockscreen()'` from a
text console. That unlocks without the lock's prompt, after a console login
as the same user. Subarchy does not call it anywhere.

A user who overrides the setting to `false` gets Hyprland's default: no
replacement is accepted (in the VM test, on an image without the setting,
the notice stayed up while five replacements died one after another), and
that command or ending the session is the way out.

## Verification

`tools/iso/install-test.py` kills the lock program with SIGKILL in the
installed VM, apart from its shell-death check. It requires a new process
holding a lock the compositor confirms (`secure`), a restart counted by
systemd, a marker window hidden in captures taken while locked, right after
the kill and under the replacement, and a password unlock that ends the
unit. The captures are samples, not a continuous record.

Related: [[0036-shell-components|ADR 0036]] · [[decisions-index|Decisions]]
