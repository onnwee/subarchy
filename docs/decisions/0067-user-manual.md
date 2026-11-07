---
title: "ADR 0067: User manual"
type: decision
status: accepted
adr: 67
created: 2026-11-07
updated: 2026-11-07
tags: [decision, adr, delivery, docs]
aliases: [ADR 0067, Manual]
---

# ADR 0067: User manual

Accepted 2026-11-07: "do the same as Omarchy, on the device and in the
repository".

## How Omarchy does it (4.5, read on `sputnik`)

- The menu's **Learn** section opens the online manual
  (`https://omarchy.org/manual/`) as a web app, plus the keybinding cheat
  sheet and links to the Hyprland wiki, Arch wiki, LazyVim keymaps and a bash
  cheat sheet.
- An agent skill ships on the device (`default/agents/skills/omarchy/`:
  `SKILL.md` with guides for Hyprland, plugins, theming, hooks, capture and
  contributing).

## Decision

- **Source in this repository**, as Markdown under `docs/manual/`, written
  for users rather than for the build.
- **On the device**:
  - an offline copy rendered to HTML in the Subarchy package, opened by a
    **Learn** menu entry and `subcult help`, so it works without a network;
  - the same Learn section as Omarchy: keybindings cheat sheet, Hyprland wiki,
    Arch wiki, LazyVim keymaps;
  - an agent skill generated from the same manual and the CLI's
    `subcult commands --json` ([[0047-ai-agents|ADR 0047]]).
- **Online** when the repository has a public home; until then the offline
  copy is the manual.

## Consequences

The manual and the agent skill come from one source, so a CI check fails when
a command in `subcult commands --json` has no manual entry.

Related: [[decision-map|Decision map]] · [[0046-distribution-cli|ADR 0046]] · [[0047-ai-agents|ADR 0047]]
