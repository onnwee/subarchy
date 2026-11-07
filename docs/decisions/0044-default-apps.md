---
title: "ADR 0044: Default app set"
type: decision
status: accepted
adr: 44
review: pending
created: 2026-11-06
updated: 2026-11-06
tags: [decision, adr, apps]
aliases: [ADR 0044, A6, Default apps]
---

# ADR 0044: Default app set

Decision map item A6. Accepted 2026-11-06; the app list itself is pending
owner review.

## Decision

Subcarchy preinstalls a **full set** of applications, as Omarchy does, rather
than a lean core with a catalogue. The set covers office, writing, notes,
media, graphics, communication and utilities, using the defaults already
decided:

| Role | App |
|---|---|
| Terminal | kitty, WezTerm ([[0040-terminal\|ADR 0040]]) |
| Editor | Neovim with Subcarchy's LazyVim (A3, in discussion) |
| Browser | Zen ([[0042-browser\|ADR 0042]]) |
| Files | Dolphin, yazi ([[0043-file-manager\|ADR 0043]]) |

The rest of the list is drawn up from [[sputnik-apps|Apps on sputnik]] and
Omarchy's `omarchy-base.packages`, then reviewed by the owner.

## Options considered

| Option | Why not chosen |
|---|---|
| Lean core with an app catalogue | The owner wants installs ready for everything. |
| The owner's whole `sputnik` set | Too heavy and personal for every install. |

## Open

- The final list, including which overlaps to resolve: browsers, password
  managers, PDF viewers, archive tools.
- Web apps: which ones ship, and how they run without Chromium
  ([[0042-browser|ADR 0042]]).
- How apps from outside pacman (AppImages, custom builds) are handled.

## Consequences

Install size and update volume grow with the list; every preinstalled app
needs theming and must survive staged updates.

Related: [[decision-map|Decision map]] · [[sputnik-apps|Apps on sputnik]] · [[0042-browser|ADR 0042]]
