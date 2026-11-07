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
| Editor | Neovim with Subcarchy's LazyVim config ([[0045-editor\|ADR 0045]]) |
| Browser | Zen ([[0042-browser\|ADR 0042]]) |
| Files | Dolphin, yazi ([[0043-file-manager\|ADR 0043]]) |

**The owner writes the app list** in [[app-list|App list]]. It says which apps
are preinstalled, which are offered for install, and which is the default for
each role.

**App installer and default picker.** Like Omarchy, Subcarchy has:

- an **installer** that installs an app from the list with its integration
  steps (theme template, keybinding, firewall rule, config), from a shell menu
  or the CLI;
- a **default picker** that sets the default app per role from the apps the
  list allows for that role, updating XDG MIME handlers, `xdg-terminal-exec`
  and Subcarchy's own launchers;
- a matching **remove** for each install.

The list file is the single source both tools read; adding an app to the
installer means adding a row and, when needed, an integration script.

## Options considered

| Option | Why not chosen |
|---|---|
| Lean core with an app catalogue | The owner wants installs ready for everything. |
| The owner's whole `sputnik` set | Too heavy and personal for every install. |

## Borrowed from Omarchy

- `omarchy install app <display-name> <packages>`, which shows the install in
  a floating terminal, and the per-app installers (`omarchy install browser`,
  `editor`, `terminal`, `gaming`, `service`, `ai` and others: 46 commands).
- `omarchy default browser|terminal|editor|agent|dictation`, which set the
  default per role and update XDG handlers.
- The matching `omarchy remove` commands and the shell's menu entries.

Omarchy hard-codes its choices in each command (for example
`omarchy default terminal` accepts only alacritty, foot, ghostty, kitty).
Subcarchy reads them from the list instead.

## Open

- The final list (owner), including which overlaps to resolve: browsers,
  password managers, PDF viewers, archive tools.
- Web apps: which ones ship, and how they run without Chromium
  ([[0042-browser|ADR 0042]]).
- How apps from outside pacman (AppImages, custom builds) are handled.
- The list file's machine-readable format, once the owner's list exists.

## Consequences

Install size and update volume grow with the list; every preinstalled app
needs theming and must survive staged updates.

Related: [[decision-map|Decision map]] · [[app-list|App list]] · [[sputnik-apps|Apps on sputnik]] · [[0042-browser|ADR 0042]]
