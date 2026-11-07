---
title: "ADR 0030: Login manager"
type: decision
status: accepted
adr: 30
created: 2026-11-06
updated: 2026-11-06
tags: [decision, adr, session, brand]
aliases: [ADR 0030, L2, Login manager, SDDM]
---

# ADR 0030: Login manager

Decision map item L2. Accepted 2026-11-06.

## Decision

**SDDM** with a Subarchy **QML theme**. After the LUKS passphrase at boot,
the user logs in with their password, which also unlocks gnome-keyring
([[0023-authentication|ADR 0023]]).

## Options considered

| Option | Why not chosen |
|---|---|
| greetd with ReGreet or tuigreet | Lighter, but less theming reach. |
| Auto-login after disk unlock | One password per boot, but requires the login password to equal the disk passphrase and more PAM setup. Can be revisited as an opt-in. |

## Borrowed from Omarchy

`default/sddm/omarchy/` (`Main.qml`, `theme.conf`, images) as the structure
for the theme, and `default/sddm/hyprland.lua`, which runs the greeter under
Hyprland. Artwork and text are replaced (R4).

## Consequences

- The SDDM theme is QML, so it can share components and colours with the
  desktop shell if the shell is also QML (D1).
- Two password prompts per boot: disk, then login.
- SDDM must start the session through uwsm ([[0031-session-manager|ADR 0031]]).

Related: [[decision-map|Decision map]] · [[0031-session-manager|ADR 0031]] · [[0013-boot-splash|ADR 0013]]
