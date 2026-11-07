---
title: "ADR 0039: Fonts and icons"
type: decision
status: accepted
adr: 39
created: 2026-11-06
updated: 2026-11-06
tags: [decision, adr, shell, brand]
aliases: [ADR 0039, D7, Fonts, Icons]
---

# ADR 0039: Fonts and icons

Decision map item D7. Accepted 2026-11-06.

## Decision

| Use | Font |
|---|---|
| Terminals, code, monospace UI | **JetBrains Mono**, Nerd Font build for icons |
| Interface text | **Space Grotesk** |
| Display headings, splash, login | **Oswald** |
| Fallback, CJK, emoji | **Noto** (Sans, CJK, Color Emoji) |

Icons: **Yaru purple-dark** (`Yaru-purple-dark`), as the default
`subcult-minimal` theme sets (revised 2026-11-07; Papirus was the first
choice). Other themes may name another icon theme.

## Options considered

| Option | Why not chosen |
|---|---|
| Papirus, recoloured per theme (first choice) | Replaced by the default theme's own icon set on 2026-11-07. |
| Custom SUBCULT icon set | Most design work; can come later for the shell's own icons. |

## Evidence

The rice's brand kit (`subcult-omarchy-rice/theme/brand/fonts/`) holds
JetBrains Mono, Oswald and Space Grotesk with their SIL Open Font Licence
files, so they can be redistributed. SUBCULT's `dash` project already uses
the same three fonts.

## Consequences

- fontconfig defaults set Space Grotesk as sans-serif and JetBrains Mono as
  monospace.
- The icon theme follows the active theme's `icons.theme`; `subcult-minimal`
  names `Yaru-purple-dark`, so `yaru-icon-theme` is preinstalled.

Related: [[decision-map|Decision map]] · [[0037-theming|ADR 0037]] · [[brand-identity|Brand identity]]
