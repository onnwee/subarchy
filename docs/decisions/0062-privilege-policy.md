---
title: "ADR 0062: sudo and polkit policy"
type: decision
status: accepted
adr: 62
created: 2026-11-07
updated: 2026-11-13
tags: [decision, adr, security]
aliases: [ADR 0062, sudo, polkit]
---

# ADR 0062: sudo and polkit policy

Accepted 2026-11-07.

## Decision

- `sudo` and polkit ask for the password by default (fingerprint or FIDO2
  where enrolled; [[0023-authentication|ADR 0023]]).
- **Some actions skip the prompt** through narrow sudoers rules and polkit
  rules that name exact commands, never a wildcard:
  - the system update command and its steps (`subcult update`);
  - setting the time zone (`tzupdate`, as Omarchy does);
  - reboot, shutdown, suspend and hibernate (already allowed for the active
    session by logind);
  - mounting removable drives (udisks), network changes (NetworkManager) and
    power profiles (already allowed for the active session).
- **"Skip sudo for X minutes"** in the menu and launcher: pick 5, 15, 30 or 60
  minutes, confirm with the password once, and `sudo` stops asking for that
  long. Implemented as a sudoers drop-in with a per-user timestamp timeout,
  removed by a systemd timer when the time runs out, on lock, and on logout.
  The bar shows a countdown while it is active.

The owner asked for "some actions" to skip the prompt and left the starting
list to the agent (2026-11-07); the list above is that starting list.

## Actions added since

- `tv.subcult.theme.system-apply` (issue #103): the privileged half of
  `subcult theme apply-system`, through pkexec; the action names the exact
  program (`/usr/bin/subcult-theme`), which takes only colours as arguments.
  It asks for an administrator's password (`auth_admin_keep`), as the
  default above says; it is not on the password-free list.
- `tv.subcult.docker.tui` (2026-11-13, [[0055-containers|ADR 0055]]):
  lazydocker as root through pkexec while the user is not in the `docker`
  group; the action names `/usr/lib/subcult/lazydocker-root`, which takes
  only the terminal type. `auth_admin_keep`, not password-free: driving
  Docker is root access.
- `tv.subcult.tailscale` (2026-11-13, [[0058-tailscale|ADR 0058]]): the
  bar's Tailscale panel and `subcult tailscale send` reach tailscaled
  through pkexec and `/usr/lib/subcult/tailscale-helper`, a root script
  that runs only `tailscale up`, the sign-in (`tailscale up`, printing the
  link), `tailscale down`, the exit node (`tailscale set --exit-node=<a
  Tailscale address> --exit-node-allow-lan-access=true`, or both back to
  their defaults) and a Taildrop send (`tailscale file cp --name=<name> -`
  from standard input). It takes only Tailscale addresses and plain file
  names, and never opens a path the caller names. These are network
  changes, so the active local session may run it without a password
  (`allow_active` `yes`), as it may NetworkManager's; other sessions need
  an administrator's password. So any program the user runs can connect,
  disconnect, pick an exit node or send the user's files to a machine on
  the tailnet. It can also sign the machine in to any tailnet whenever
  tailscaled is signed out (before the first sign-in, after a sign-out or
  when the sign-in has expired), including a tailnet someone else owns.
  NetworkManager likewise lets the session join any Wi-Fi network. The
  helper cannot change other settings, with one exception: before the
  first sign-in, `tailscale up` puts every setting back to its default
  without checking, so a sign-in then undoes settings an administrator
  made beforehand (shields-up, for example). It cannot turn anything on
  that is off by default, Tailscale SSH included, and the installer sets
  none. After the first sign-in, `tailscale up` refuses to undo a setting,
  so the helper repeats only its own two (the exit node and the local
  network) and an administrator's settings stay; checked with tailscale
  1.104.7. Sending is in the helper because
  tailscaled 1.104.7 refuses `file cp` to a user who is neither root nor
  its operator (HTTP 403, "file access denied"). The Taildrop receiver is a root system unit,
  `subcult-taildrop@<user>.service`, which hands each file to the user.
  **No account is tailscaled's operator.** An operator could change every
  tailscaled setting without a password, including turning on Tailscale
  SSH (a root SSH server that Tailscale's default policy opens to the
  owner's own devices) and advertising routes or an exit node; checked
  with tailscale 1.104.7, which has no system policy that turns Tailscale
  SSH off. Decided 2026-11-13 by the lead under the owner's delegated
  authority, after review of PR #157, which had proposed the operator
  grant: no operator grant; a root helper under polkit instead.

## Borrowed from Omarchy

`omarchy sudo passwordless` (permanent toggle) and `omarchy-sudo-keepalive`,
and Omarchy's sudoers rule for `tzupdate`. Subarchy's timed version replaces
the permanent toggle.

## Consequences

- During a skip window any process the user runs can use `sudo`; the
  countdown makes that visible.
- Each passwordless rule is reviewed when the command it names changes.

## Progress

- 2026-11-07: `subcult update` needs no password for its root steps. They
  are `subcult-update privileged snapshot|upgrade [--noconfirm]|prune`,
  each running a fixed command, and `/etc/sudoers.d/50-subarchy-update`
  allows exactly those four command lines for `wheel`. Removing orphaned
  packages still asks. The VM test runs the update after `sudo -k` with no
  input. The other rules (time zone, the "skip sudo for X minutes" menu) are
  still to do.

Related: [[decision-map|Decision map]] · [[0023-authentication|ADR 0023]] · [[0063-security-hardening|ADR 0063]]
