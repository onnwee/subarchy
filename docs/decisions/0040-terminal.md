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

- **kitty** is the default and only preinstalled terminal.
- **WezTerm** is offered in the app installer ([[0044-default-apps|ADR 0044]])
  and keeps a theme template. Revised 2026-11-06 under
  [[0054-lightweight-battery-first|ADR 0054]]; it was first preinstalled.
- `xdg-terminal-exec` lists kitty first, then WezTerm if the user installs
  it. On 2026-11-06 WezTerm was not installed on `sputnik`; only a leftover
  launcher remained ([[sputnik-apps|Apps on sputnik]]).

## Options considered

| Option | Why not chosen |
|---|---|
| Ghostty | Not in the owner's current set. |
| Foot (Omarchy) | Minimal; no tabs or image protocol. |

## Borrowed from Omarchy

`config/kitty/`, the kitty theme template, and the `xdg-terminal-exec`
preference list mechanism (`default/xdg-terminal-exec/`).

## Consequences

- Both terminals keep theme templates ([[0037-theming|ADR 0037]]) and live
  reload: kitty through remote control, WezTerm through its config watcher.
- Omarchy has no WezTerm template; that one is new.

Related: [[decision-map|Decision map]] · [[0041-shell-prompt|ADR 0041]]
