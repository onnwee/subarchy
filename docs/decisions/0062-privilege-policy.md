---
title: "ADR 0062: sudo and polkit policy"
type: decision
status: accepted
adr: 62
created: 2026-11-07
updated: 2026-11-07
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

The owner asked for "some actions" to skip the prompt; the list above is the
agent's proposal. Adjust it here.

## Borrowed from Omarchy

`omarchy sudo passwordless` (permanent toggle) and `omarchy-sudo-keepalive`,
and Omarchy's sudoers rule for `tzupdate`. Subarchy's timed version replaces
the permanent toggle.

## Consequences

- During a skip window any process the user runs can use `sudo`; the
  countdown makes that visible.
- Each passwordless rule is reviewed when the command it names changes.

Related: [[decision-map|Decision map]] · [[0023-authentication|ADR 0023]] · [[0063-security-hardening|ADR 0063]]
