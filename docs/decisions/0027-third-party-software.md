---
title: "ADR 0027: Third-party software"
type: decision
status: accepted
adr: 27
created: 2026-11-06
updated: 2026-11-06
tags: [decision, adr, packages]
aliases: [ADR 0027, P2, AUR, Flatpak]
---

# ADR 0027: Third-party software

Decision map item P2. Accepted 2026-11-06.

## Decision

- **yay** is preinstalled for the AUR, as in Omarchy. AUR packages the user
  installs are trusted by the user, not vetted by Subarchy.
- **Flatpak** is installed with the **Flathub** remote enabled, for sandboxed
  desktop apps.
- AppImages run if the user downloads them; Subarchy does not manage them.

## Options considered

| Option | Why not chosen |
|---|---|
| Flatpak only | The owner's workflow uses many AUR packages. |
| AUR helper only (Omarchy) | No sandboxed apps. |

## Consequences

- `yay` itself is an AUR package, so Subarchy rebuilds it
  ([[0025-package-repository|ADR 0025]]). `paru` would work as well; `yay` was
  kept to match Omarchy's scripts.
- AUR builds use the same Arch snapshot as the system; on the stable channel
  a fresh AUR package can need newer libraries than the snapshot has.
- The app installer (A6) must decide per app whether it comes from the repo,
  the AUR or Flathub.
- Flatpak apps need the theme bridge (D5) to match the desktop.

Related: [[decision-map|Decision map]] · [[0025-package-repository|ADR 0025]] · [[0026-update-model|ADR 0026]]
