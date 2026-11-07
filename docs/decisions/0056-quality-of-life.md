---
title: "ADR 0056: Quality-of-life features"
type: decision
status: accepted
adr: 56
created: 2026-11-07
updated: 2026-11-07
tags: [decision, adr, shell, apps]
aliases: [ADR 0056, Quality of life, QoL, Keybindings]
---

# ADR 0056: Quality-of-life features

Accepted 2026-11-07. Small everyday conveniences, most borrowed from
Omarchy 4.5. Each is a keybinding, menu entry or `subcult` command that runs
only when used, unless the idle-cost column says otherwise
([[0054-lightweight-battery-first|ADR 0054]]).

Keybindings follow Omarchy's where it has one, so the layout is familiar; the
full keymap is designed with the shell (D3).

## Included

| Feature | Omarchy binding | Borrowed from Omarchy | Packages | Idle cost |
|---|---|---|---|---|
| Universal copy, paste, cut, select-all in terminals and GUI apps | Super+C / V / X / A | `default/hypr/bindings/clipboard.lua` (`universal_clipboard_shortcut`) | `wtype` | none |
| Clipboard history | Super+Ctrl+V | `omarchy.clipboard` plugin | `wl-clipboard` | a clipboard watcher |
| Emoji picker | Super+Ctrl+E | `omarchy.emojis` | | none |
| Theme picker with previews | Super+Ctrl+T | `omarchy-theme-switcher`, `omarchy.image-picker`; applies through Theme Tender ([[0037-theming\|ADR 0037]]) | | none |
| Wallpaper picker | Super+Ctrl+Space | `omarchy-theme-bg-switcher` ([[0038-wallpaper\|ADR 0038]]) | | none |
| One searchable menu for everything | Super+Space | `omarchy.menu` | | none |
| Keybinding cheat sheet | Super+K | `omarchy menu keybindings` | | none |
| Screenshot to clipboard with annotation; screen recording toggle | Print, Alt+Print | `omarchy capture` | see [[app-list\|App list]] | none |
| Do not disturb | bar, menu | `omarchy toggle notification silencing` | | none |
| Launch-or-focus: an app's key focuses its open window | per app | `omarchy launch or focus`, `… tui`, `… webapp` | | none |
| Scratchpad and drop-down terminal | Super+S, Super+` | `default/hypr/bindings/tiling.lua` | | none |
| Pop out and pin a window on top | Super+O | `tiling.lua` ("Pop window out") | | none |
| New terminal or file manager opens in the current terminal's folder | Super+Return, Super+Alt+Shift+F | `omarchy launch terminal`, `omarchy launch nautilus cwd` (adapted for Dolphin) | | none |
| Copy text from the screen (OCR) | Super+Ctrl+Print | `omarchy capture text` | `tesseract`, `tesseract-data-eng` | none |
| Colour picker | Super+Print | `hyprpicker` binding | `hyprpicker` | none |
| QR codes: decode from screen, share Wi-Fi as QR | menu | `omarchy capture qr`, `omarchy.wifiqr` | `zbar`, `qrencode` | none |
| Quick share to nearby devices | Super+Ctrl+S | `omarchy` share menu | `localsend` (AUR, rebuilt) | none until opened; firewall port 53317 ([[0019-firewall\|ADR 0019]]) |
| Keep awake | bar, menu | `omarchy toggle idle` | | none |
| Night light, manual or scheduled | bar, menu | `omarchy toggle nightlight`, `omarchy.nightlight` | `hyprsunset` | small daemon while on |
| Laptop screen off or mirrored when docked | Super+Ctrl+Delete, Super+Ctrl+Alt+Delete | `tiling.lua` / `utilities.lua` display toggles | | none |
| Screen zoom around the cursor | Super+Ctrl+Z | `utilities.lua` zoom | | none |
| Compose-key shortcuts for emoji and personal snippets | Compose key | `default/xcompose` | | none |
| Reminders | Super+Ctrl+R | `omarchy reminder` | | a systemd timer per reminder |
| Dictation, push to talk | Alt+Space | `default/hypr/bindings/dictation.lua`, voxtype setup | `voxtype-bin` (AUR, rebuilt) | the speech model's memory while the daemon runs |
| USB drives mount automatically | — | `udiskie` in Omarchy's base list | `udiskie` | a small always-running daemon |

## Consequences

- Dictation and USB auto-mount are the two items with a standing cost. Both
  get an off switch in settings; dictation's daemon should start on first use
  rather than at login if voxtype allows it.
- Compose-key snippets with personal data (email, address) live in the
  user's own `~/.XCompose` override, never in the shipped default
  ([[0048-config-ownership|ADR 0048]]).
- Omarchy's `default/hypr/bindings/` and `default/xcompose` are borrowed
  under MIT; app-specific bindings (Omarchy's web apps, Basecamp, HEY) are
  not.
- The packages above join the preinstalled set in [[app-list|App list]].

Related: [[decision-map|Decision map]] · [[0036-shell-components|ADR 0036]] · [[0054-lightweight-battery-first|ADR 0054]] · [[app-list|App list]]
