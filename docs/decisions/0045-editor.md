---
title: "ADR 0045: Editor"
type: decision
status: accepted
adr: 45
created: 2026-11-06
updated: 2026-11-06
tags: [decision, adr, apps]
aliases: [ADR 0045, A3, Editor, LazyVim]
---

# ADR 0045: Editor

Decision map item A3. Accepted 2026-11-06.

## Decision

- **Neovim** is the default editor, running **stock LazyVim**.
- Subcarchy **forks only LazyVim's starter config** and adds its own plugin
  layer for branding and defaults: dashboard art, colourscheme from the active
  theme ([[0037-theming|ADR 0037]]), keymaps and chosen LazyVim extras.
- It ships **prebuilt**, with plugins pinned by a lockfile and cached in the
  package, so the first launch needs no downloads.

## Options considered

| Option | Why not chosen |
|---|---|
| Light fork of LazyVim core | Allows changing internals, but adds a fork to keep current. |
| Renamed Neovim distribution | Most control; upstream improvements carried by hand. |

## Borrowed

- `omarchy-nvim`: the packaging approach, a starter config plus cached plugins
  copied into new home directories (7,933 files under `/etc/skel` in
  2026.9.21-5).
- Omarchy's `neovim.lua.tpl` theme template.

## Consequences

- LazyVim and its plugins update through Subcarchy's lockfile, on the staged
  channel ([[0026-update-model|ADR 0026]]).
- LazyVim and the starter are Apache-2.0: keep the licence and NOTICE, and
  mark changed files. The LazyVim name is not used as the product name; the
  branding layer carries a Subcarchy name.
- If a wanted change can only be made inside LazyVim, it goes upstream first;
  a core fork needs a new decision.
- Other editors (Helix, VS Code, Zed) are available through the app
  installer ([[0044-default-apps|ADR 0044]]).

Related: [[decision-map|Decision map]] · [[0044-default-apps|ADR 0044]] · [[0037-theming|ADR 0037]]
