---
title: "ADR 0037: Theming system"
type: decision
status: accepted
adr: 37
created: 2026-11-06
updated: 2026-11-07
tags: [decision, adr, shell, theme, brand]
aliases: [ADR 0037, D5, Theming, Themes, Theme Tender]
---

# ADR 0037: Theming system

Decision map item D5. Accepted 2026-11-06; theme format and tool settled
2026-11-07 once the owner shared Theme Tender.

## Decision

**Theme Tender is Subarchy's theming system.** The owner's tool
([`subculture-collective/theme-tender`](https://git.subcult.tv/subculture-collective/theme-tender),
local checkout `~/Work/Subcult/theme-tender`) applies one palette across every
installed app, changes only colours, and can undo every change. Subarchy does
not build its own palette format, template renderer or theme switcher.

- **Palette format**: Theme Tender's colour model. 26 roles with
  Catppuccin's names (`rosewater` … `crust`), ANSI 0–15, and the terminal
  specials (`background`, `foreground`, `cursor`, `selection_bg`,
  `selection_fg`). Missing roles are derived in OKLCH.
- **Templates**: Theme Tender's Mustache templates, compatible with the
  Base16 builder spec, selected per app by its registry
  (`registry/apps/<id>.yaml`).
- **Applying**: `tender apply`. The installer calls it with a profile, as
  Theme Tender's ADR 0002 already plans. The shell's theme panel calls the
  same CLI; the `tender` TUI is the full browser.
- **Catalog**: Theme Tender's catalog (iTerm2 Color Schemes, Tinted Theming,
  Catppuccin, Dracula, Gogh), with its licence rules. This replaces the
  earlier "SUBCULT plus a few classics" list.
- **Default theme: `subcult-minimal`**, the theme `sputnik` runs today,
  converted to Theme Tender's format and used as the base for Subarchy's look
  (owner, 2026-11-07). Revised from an earlier plan to design a new palette;
  the rest of the SUBCULT rice's theme (the gradient `subcult` variant,
  affinity palettes, scenes) stays out.

  What `subcult-minimal` is (read on `sputnik` 2026-11-07): the SUBCULT
  palette from the rice's `colors.toml` (ink `#100B19`, paper `#F0ECE4`, acid
  accent `#00FF88`, violet selection `#3B2470`) with solid 1 px violet borders
  (`rgb(8F4BC8)` active, `rgb(1F1830)` inactive); a `hyprland.lua` that turns
  off gaps, rounding, blur, shadows, dimming and animations and keeps windows
  opaque, which suits [[0054-lightweight-battery-first|ADR 0054]]; icon theme
  `Yaru-purple-dark`; keyboard RGB `#8B5CF6`; wallpapers in
  [[0038-wallpaper|ADR 0038]].
- No variants mechanism; the owner declined the rice's (2026-11-06).

## How it fits other decisions

- **Configuration ownership** ([[0048-config-ownership|ADR 0048]]): Theme
  Tender's preferred method is `include`: it writes a file it owns and one
  include line in the user's config. Subarchy's layered defaults ship that
  include line already, so Theme Tender only writes its owned file and never
  edits a Subarchy default.
- **Lightweight** ([[0054-lightweight-battery-first|ADR 0054]]): Theme Tender
  runs only when a theme is applied; nothing stays in the background.
- **Licences** ([[0053-licence|ADR 0053]]): Theme Tender's code is
  GPL-3.0-only, its templates and registry MIT. Subarchy ships it as a
  separate package.

## What Subarchy needs from Theme Tender

Theme Tender's M1 covers ghostty, kitty, alacritty, tmux, starship, lazygit,
yazi and btop. Six of those are in Subarchy. Its plan puts "branding
surfaces, GUI apps" after M4. Subarchy needs these sooner, so Subarchy
writes the registry entries and templates (MIT) and contributes them upstream:

| Target | Kind | Notes |
|---|---|---|
| Hyprland borders and groups | user config | Include into `~/.config/hypr` |
| Lock screen and screensaver | user config | Subarchy's standalone QML lock ([[0036-shell-components\|ADR 0036]]) reads a palette file; the screensaver loops re-render on theme change |
| Quickshell shell | user config | Subarchy's own shell reads a palette file |
| Qt and KDE colour scheme | user config | Dolphin, Okular, Ark, VLC (Qt 5) through `kdeglobals` or a Kvantum theme |
| GTK 3 and 4 | user config | Thunderbird, satty and other GTK apps |
| Neovim, VS Code, Obsidian | user config | Editor and notes |
| Chromium | policy | Chromium theme colour is a managed policy (Omarchy's `color.json`) |
| fzf, bat, git-delta, eza, fastfetch, swayimg | user config | CLI set from [[app-list\|App list]] |
| SDDM, Plymouth, Limine | **system**, root-owned | Theme Tender runs as the user. Subarchy's CLI applies these through polkit from a palette Theme Tender exports |

Raised in Theme Tender on 2026-11-07 (owner's request), unlabelled so the
owner decides pickup:

1. [theme-tender#19](https://git.subcult.tv/subculture-collective/theme-tender/issues/19):
   export the resolved palette or render a template without applying, for the
   root-owned targets above.
2. [theme-tender#20](https://git.subcult.tv/subculture-collective/theme-tender/issues/20):
   recognise Subarchy's layered defaults in ownership detection.
3. [theme-tender#21](https://git.subcult.tv/subculture-collective/theme-tender/issues/21):
   rename "Subcarchy" to "Subarchy" in its ADR 0002
   ([[0052-name-identity|ADR 0052]]).

## Options considered

| Option | Why not chosen |
|---|---|
| Subarchy's own palette file and templates (first version of this ADR) | Duplicates Theme Tender. |
| Palette generated from the wallpaper | Brand colours not guaranteed. |
| One fixed SUBCULT look | No re-skinning. |
| Port all 24 Omarchy themes | Theme Tender's catalog covers far more. |

## Borrowed from Omarchy

Omarchy's `default/themed/*.tpl` templates (Alacritty, Foot, Ghostty, Kitty,
btop, Chromium, Hyprland, Neovim, Helix, VS Code, Obsidian, fcitx5, keyboard
RGB, shell) are references when writing Theme Tender registry entries for the
same apps. Theme Tender's own ADR 0002 lists Omarchy as a supported backend,
which Subarchy does not use.

## Consequences

- Subarchy's theming depends on Theme Tender's progress. By 2026-11-07 its M1
  work had merged (PRs #1–#18 on 2026-11-06: colour core, catalog builder,
  registry, renderer, config editors, change record, ownership detection,
  Omarchy backend, CLI, terminal UI, signed bundle, packaging). Its README
  says "M1 in progress": `tender` works with a catalog the user builds; the
  signed data bundle and packages come later. Commands on `main`: `search`,
  `apply`, `uninstall`, `list`, `tui`, `doctor`, `version`.
- Subarchy's Phase 4 theming work becomes registry entries and templates in
  Theme Tender, plus the system-level apply for SDDM, Plymouth and Limine.
- The palette contract is Theme Tender's, versioned there (`schema: 1`).

## Progress

- 2026-11-07: `default/theme/subcult-minimal.json` holds the default theme
  in Theme Tender's palette-file format (`schema: 1`, a `theme` envelope,
  the 26 roles, ANSI 0–15 and the terminal specials); `tender palette`
  reads it as `subcult-minimal`. The shell's `palette.json` is generated
  from it by `tools/theme/gen-palette.py` and `make verify` fails when the
  two differ (issue #80).
- 2026-11-07: Theme Tender ships from `packaging/theme-tender/` (its v0.1.0
  release PKGBUILD, vendored) and is in the desktop package set; the
  installer runs `tender apply -profile default/theme/subarchy.toml` for
  the new user, and the VM test checks `tender doctor` (issue #72).

Related: [[decision-map|Decision map]] · [[0048-config-ownership|ADR 0048]] · [[brand-identity|Brand identity]] · [[0038-wallpaper|ADR 0038]] · [[0039-fonts-icons|ADR 0039]]
