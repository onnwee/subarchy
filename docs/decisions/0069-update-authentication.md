---
title: "ADR 0069: Authenticate system updates"
type: decision
status: accepted
adr: 69
created: 2026-11-09
updated: 2026-11-09
tags: [decision, adr, security, updates]
aliases: [ADR 0069, Update authentication]
---

# ADR 0069: Authenticate system updates

Accepted 2026-11-09 from the owner's Sputnik update feedback. Supersedes
only the password-free update exception in [[0062-privilege-policy|ADR 0062]].

## Decision

`subcult update` authenticates through `sudo true` before snapshots or any
other privileged work. `--yes` answers update questions; it does not bypass
authentication. The normal sudo cache and an explicitly configured
passwordless policy still apply. Dry runs and update checks do not prompt.

Remove the package-owned `50-subarchy-update` sudoers exception. The
installer's normal wheel policy remains; pacman removes the old package
file when upgrading. No other sudo or polkit policy changes.

Keep the authenticated sudo timestamp fresh with noninteractive
`sudo -n true` once per minute until the update exits. Stop on cancellation
or failed refresh; never start a background password prompt or recreate a
revoked grant. This follows Omarchy's one-authorization update flow.

## Hyprland transaction handling

In the caller's Hyprland session, pause automatic configuration reloads
before package replacement. After packages, migrations and cleanup finish,
reload the complete configuration. Restore the previous watcher setting on
success, failure or a handled termination signal. An already disabled
watcher stays disabled. Updates from SSH or a text console do not choose
another session. This applies to `subcult update`; direct pacman use does
not receive this guard.

The guard prevents reads of a temporarily missing Lua file; it does not
hide configuration errors. A failed transaction restores the watcher
without explicitly reloading an incomplete tree. SIGKILL and power loss
cannot run cleanup; a session restart resets the transient watcher setting.

## Transition and verification

An older updater remains the running process when it installs this change.
Its existing final reload can still clear a transient warning, but prevention
and the initial authentication step begin when the new updater is invoked.

Regressions cover authorization refusal, dry runs, noninteractive credential
refresh and cleanup, watcher pause ordering, migration/package failure,
cancellation, preserved disabled state and the final reload. The install VM
checks refusal without authorization followed by an authenticated update
using only its disposable password.

Related: [[0026-update-model|Update model]] · [[0062-privilege-policy|Privilege policy]]
