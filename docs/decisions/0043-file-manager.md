---
title: "ADR 0043: File manager"
type: decision
status: accepted
adr: 43
created: 2026-11-06
updated: 2026-11-06
tags: [decision, adr, apps]
aliases: [ADR 0043, A5, File manager, Dolphin]
---

# ADR 0043: File manager

Decision map item A5. Accepted 2026-11-06.

## Decision

- **Dolphin** is the graphical file manager.
- **yazi** is the terminal file manager.

## Options considered

| Option | Why not chosen |
|---|---|
| Nautilus (Omarchy, current default on `sputnik`) | Not chosen; GTK4. |
| Thunar | Older GTK3 look. |

## Consequences

- Dolphin is Qt, like the shell ([[0034-shell-toolkit|ADR 0034]]), but pulls
  in KDE Frameworks and KIO. Thumbnails need `ffmpegthumbs`,
  `kdegraphics-thumbnailers` and `kio-extras`; `sputnik` already has
  `kio-extras`, Ark and Filelight.
- **Portal file chooser**: [[0033-portals|ADR 0033]] routes file dialogs to the
  GTK portal. With Dolphin as the file manager, `xdg-desktop-portal-kde` would
  give KDE-style dialogs instead. Revisit ADR 0033 when theming Qt apps.
- Qt and KDE apps need theming through templates (Kvantum or a `kdeglobals`
  colour scheme) under [[0037-theming|ADR 0037]].
- Omarchy's Nautilus extensions (`nautilus-python`, sushi previews,
  "open terminal here") are not borrowed; Dolphin has its own terminal panel
  and service menus.

Related: [[decision-map|Decision map]] · [[0033-portals|ADR 0033]]
