---
title: "ADR 0037: Theming system"
type: decision
status: accepted
adr: 37
created: 2026-11-06
updated: 2026-11-06
tags: [decision, adr, shell, theme, brand]
aliases: [ADR 0037, D5, Theming, Themes]
---

# ADR 0037: Theming system

Decision map item D5. Accepted 2026-11-06.

## Decision

**Mechanism.** A theme is a directory with one **palette file** and its
**backgrounds**. Applying a theme renders **templates** into matching configs
for every themed program: terminals, Hyprland, hyprlock, the shell, SDDM,
Plymouth colours, btop, editors, GTK and Qt, the browser and Flatpak apps.
Themes support the SUBCULT rice's **variants**: Standard, OLED, Daylight and
High Contrast.

**Shipped themes.**

- Defaults: `subcult` and `subcult-minimal`, with the rice's five affinity
  palettes (Press, Acid Block, Paper Stock, Violet Field, Ink Run).
- A short list of popular community palettes rebuilt in Subcarchy's format,
  for example Tokyo Night, Catppuccin, Gruvbox and Nord. Each one's licence is
  checked before it ships.

**Theme switcher.** The owner is building a tool similar to Omarchy's theme
switcher, and Subcarchy integrates it as the theme switcher rather than
writing its own. The palette and template format must be designed together
with that tool.

## Options considered

| Option | Why not chosen |
|---|---|
| Palette generated from the wallpaper | Brand colours not guaranteed. |
| One fixed SUBCULT look | No re-skinning. |
| SUBCULT themes only | The owner wanted a few classics too. |
| All 24 Omarchy themes | Too many to convert and keep working. |

## Borrowed

- Omarchy's `colors.toml` and `default/themed/*.tpl` templates (Alacritty,
  Foot, Ghostty, Kitty, btop, Chromium, Hyprland, Neovim, Helix, VS Code,
  Obsidian, fcitx5, keyboard RGB, shell and others).
- The rice's palette (see [[brand-identity|Brand identity]]), affinity
  palettes and variant rules from `THEME_VARIANTS.md`.

## Open

- Where the owner's theme tool lives and what format it reads and writes.
  The theme format should not be fixed before that is known.

## Consequences

- Every themed program needs a template and a reload step; missing templates
  show up as an unthemed app.
- The palette format is a public contract for the switcher tool and for
  third-party themes, so it needs a version field.

Related: [[decision-map|Decision map]] · [[0034-shell-toolkit|ADR 0034]] · [[brand-identity|Brand identity]] · [[0038-wallpaper|ADR 0038]]
