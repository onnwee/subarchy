---
title: "ADR 0040: Terminal emulator"
type: decision
status: accepted
adr: 40
created: 2026-11-06
updated: 2026-11-06
tags: [decision, adr, apps]
aliases: [ADR 0040, A1, Terminal]
---

# ADR 0040: Terminal emulator

Decision map item A1. Accepted 2026-11-06.

## Decision

- **kitty** is the default terminal.
- **WezTerm** is also installed and themed.
- `xdg-terminal-exec` prefers kitty, then WezTerm. `sputnik`'s preference
  list has the same order, but on 2026-11-06 WezTerm was not installed there:
  only a leftover launcher remained ([[sputnik-apps|Apps on sputnik]]).

The owner answered "kitty and wezterm"; kitty is the default because it heads
the owner's current preference list. Swap the order here if WezTerm should
lead.

## Options considered

| Option | Why not chosen |
|---|---|
| Ghostty | Not in the owner's current set. |
| Foot (Omarchy) | Minimal; no tabs or image protocol. |

## Borrowed from Omarchy

`config/kitty/`, the kitty theme template, and the `xdg-terminal-exec`
preference list mechanism (`default/xdg-terminal-exec/`).

## Consequences

- Two terminals need theme templates ([[0037-theming|ADR 0037]]) and live
  reload: kitty through remote control, WezTerm through its config watcher.
- Omarchy has no WezTerm template; that one is new.

Related: [[decision-map|Decision map]] · [[0041-shell-prompt|ADR 0041]]
