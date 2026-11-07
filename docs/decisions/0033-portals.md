---
title: "ADR 0033: XDG portals"
type: decision
status: accepted
adr: 33
created: 2026-11-06
updated: 2026-11-06
tags: [decision, adr, session]
aliases: [ADR 0033, L5, Portals]
---

# ADR 0033: XDG portals

Decision map item L5. Accepted 2026-11-06 as implied by the compositor
choice; the owner did not object.

## Decision

`xdg-desktop-portal` with **`xdg-desktop-portal-hyprland`** for screen
sharing, screenshots and global shortcuts, and **`xdg-desktop-portal-gtk`**
for file choosers and settings. Screen-share source selection uses
`hyprland-preview-share-picker`.

## Borrowed from Omarchy

`config/xdg-desktop-portal/` (portal routing) and
`config/hyprland-preview-share-picker`.

## Consequences

Flatpak apps ([[0027-third-party-software|ADR 0027]]) reach files and screen
capture through these portals.

Related: [[decision-map|Decision map]] · [[0032-compositor|ADR 0032]]
