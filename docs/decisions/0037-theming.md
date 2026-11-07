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
- **Default theme**: a **SUBCULT** palette in Theme Tender's format, built
  from the brand colours (Ink `#100B19`, Paper `#F0ECE4`, Violet `#8B5CF6`,
  Acid `#00FF88`; [[brand-identity|Brand identity]]). The SUBCULT rice's
  themes are not ported.
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
| Papirus folder colours | user command | [[0039-fonts-icons\|ADR 0039]] |
| SDDM, Plymouth, Limine | **system**, root-owned | Theme Tender runs as the user. Subarchy's CLI applies these through polkit from a palette Theme Tender exports |

Open items to raise in Theme Tender:

1. A way to export the resolved palette (all roles) or render a template
   without applying it, for the root-owned targets above.
2. Recognising Subarchy's layered defaults so ownership detection treats the
   shipped include lines as Subarchy-owned and leaves them alone.
3. Its ADR 0002 still says "Subcarchy"; the distribution is now Subarchy
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

- Subarchy's theming depends on Theme Tender's progress. On 2026-11-07 it is
  at the planning stage: an M1 plan and draft contracts in an open PR, no code.
- Subarchy's Phase 4 theming work becomes registry entries and templates in
  Theme Tender, plus the system-level apply for SDDM, Plymouth and Limine.
- The palette contract is Theme Tender's, versioned there (`schema: 1`).

Related: [[decision-map|Decision map]] · [[0048-config-ownership|ADR 0048]] · [[brand-identity|Brand identity]] · [[0038-wallpaper|ADR 0038]] · [[0039-fonts-icons|ADR 0039]]
