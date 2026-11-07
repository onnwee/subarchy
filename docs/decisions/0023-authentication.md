---
title: "ADR 0023: Secrets and login factors"
type: decision
status: accepted
adr: 23
created: 2026-11-06
updated: 2026-11-06
tags: [decision, adr, system, security]
aliases: [ADR 0023, S9, Authentication, Keyring]
---

# ADR 0023: Secrets and login factors

Decision map item S9. Accepted 2026-11-06.

## Decision

- **gnome-keyring** provides the Secret Service; PAM unlocks it with the login
  password, so apps using `libsecret` work without a second prompt.
- **Fingerprint** (`fprintd`) and **FIDO2 security key** (`pam-u2f`) logins
  are opt-in setup commands per machine. Nothing is enrolled at install.
- The polkit authentication dialog comes from the desktop shell (D4).

## Options considered

| Option | Why not chosen |
|---|---|
| KeePassXC as Secret Service | Needs its database unlocked separately from login. |
| Fingerprint enrolled at install | Adds fingerprint prompts to every sudo and polkit request by default. |

## Borrowed from Omarchy

`install/user/default-keyring.sh`, `install/config/lockscreen-pam.sh`, and
`omarchy setup security fingerprint|fido2` as the model for the setup
commands.

## Consequences

- Auto-login, if ever offered (L2), would leave the keyring locked; the two
  must be decided together.
- Each PAM change for a new factor must be reversible by a matching remove
  command.

Related: [[decision-map|Decision map]] · [[0010-disk-encryption|ADR 0010]]
