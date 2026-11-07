---
title: "ADR 0048: Configuration ownership"
type: decision
status: accepted
adr: 48
created: 2026-11-06
updated: 2026-11-06
tags: [decision, adr, delivery]
aliases: [ADR 0048, R1, Config model]
---

# ADR 0048: Configuration ownership

Decision map item R1. Accepted 2026-11-06.

## Decision

**Layered defaults** for every component Subcarchy configures:

1. Defaults live in the package under the system path
   (`/usr/share/<name>/default/`) and are replaced on update.
2. Each program loads the defaults first, then a user file in `~/.config`
   that holds only the user's overrides.
3. Updates never write to `~/.config`. A change users must adopt (a renamed
   setting, a moved file) ships as a **migration**
   ([[0026-update-model|ADR 0026]]) that edits the user file once, with a
   backup.
4. Where a program cannot layer files, a template renders the user file from
   defaults plus a small override file.

## Options considered

| Option | Why not chosen |
|---|---|
| Copy full configs to `~/.config` | Updates fight user edits. |
| Declarative user config through chezmoi | Adds a tool between the user and their files; the owner's Estate Config can still manage overrides on top. |

## Borrowed from Omarchy

The Hyprland arrangement: `config/hypr/hyprland.lua` runs
`default/hypr/bootstrap.lua`, loads Omarchy defaults, then `hypr.monitors`,
`hypr.input` and the other user files, "so package updates can improve the
defaults without rewriting your ~/.config/hypr files".

## Consequences

- Each themed or configured program needs a load order check: Hyprland
  (`require`), kitty (`include`), zsh (`source`), starship, Neovim, SDDM.
- `/etc` files Subcarchy owns are package files or drop-ins (`*.conf.d/`),
  never rewritten on upgrade the way `omarchy-settings` resets
  `/etc/os-release`.
- A `refresh` command can still reset a user file to the empty override, with
  a backup.

Related: [[decision-map|Decision map]] · [[0026-update-model|ADR 0026]] · [[0037-theming|ADR 0037]]
