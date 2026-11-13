---
title: "ADR 0039: Fonts and icons"
type: decision
status: accepted
adr: 39
created: 2026-11-06
updated: 2026-11-13
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

## Revision, 2026-11-07

Superseded in part by the owner's choices in
[[shell-and-look-design|Shell and look design]]:

- **Fonts are three switchable roles**, fontconfig's `monospace`,
  `sans-serif` and `serif`, which GTK, Qt, the shell and kitty all follow.
  Defaults: JetBrainsMono Nerd Font for monospace, its Propo build for
  interface text (interface follows monospace until set on its own), and
  Libertinus Mono for serif. Space Grotesk and Oswald are no longer
  defaults. `subcult font` lists the owner's preinstalled and on-pick fonts,
  installs any Nerd Font, imports owned fonts (icons from Symbols Nerd Font,
  or an opt-in patched copy) and checks fonts. Implemented in
  `default/fontconfig/44-subarchy-roles.conf` and `cmd/subcult-font`.
- **Icons are Papirus-Dark** again (`papirus-icon-theme`), the owner's
  original pick; Yaru is not used.
- **The cursor is Subarchy's own** (`subcult-cursor`), coloured from a
  palette role (default `lavender`); `subcult cursor` builds and applies it.

## Progress

- 2026-11-13: what ships matches the revision. `papirus-icon-theme` is in
  `install/packages/desktop.txt`; `default/gtk/settings.ini` sets
  `gtk-icon-theme-name=Papirus-Dark` and
  `default/gtk/90-subarchy.gschema.override` sets
  `icon-theme='Papirus-Dark'`. `tools/test/package-test.sh` checks the
  override in the package and the VM install test checks `gsettings` on
  the installed system. The icon theme is fixed: themes carry no
  `icons.theme`, so the Consequences line above about following the active
  theme no longer applies, and `yaru-icon-theme` is not installed. The
  `Yaru-purple-dark` in [[0037-theming|ADR 0037]] describes `sputnik`'s
  theme as read on 2026-11-07; Subarchy's copy of `subcult-minimal` names
  no icon theme.

Related: [[decision-map|Decision map]] · [[0037-theming|ADR 0037]] · [[brand-identity|Brand identity]]
