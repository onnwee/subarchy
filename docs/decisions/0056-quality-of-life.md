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
Omarchy 4.5, plus four added beyond it. Each is a keybinding, menu entry or `subcult` command that runs
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
| Package installer for the official and Subarchy repositories: fuzzy search, multi-select, details preview | menu, launcher | `omarchy pkg install` (`pacman -Slq` into `fzf`, `pacman -Sii` preview) | `fzf` | none |
| AUR package installer with details and PKGBUILD preview | menu, launcher | `omarchy pkg aur install` (`yay -Slqa`, `yay -Siia` preview, PKGBUILD toggle) | `yay` ([[0027-third-party-software\|ADR 0027]]) | none |
| Package remover for installed packages | menu, launcher | `omarchy pkg remove` | `fzf` | none |
| Screensaver: SUBCULT art with text effects, inside the lock screen until any input; still art on battery | idle | `omarchy-screensaver` effects, pre-rendered ([[0036-shell-components\|ADR 0036]]) | `ttfx` (AUR, rebuilt) for re-rendering | none until idle |
| Lock on suspend | — | `omarchy-sleep-lock.service` | | none |
| Microphone-mute LED follows mute; switch audio output keeping mute | mic key, Shift+Mute | `omarchy audio input mute`, `omarchy audio output switch` | | none |
| Kernel picker: which kernel Limine boots by default | menu | `omarchy kernel` ([[0004-kernel\|ADR 0004]]) | | none |
| Show Wi-Fi password; network speed test | menu | `omarchy network password`, `omarchy network speedtest` | | none |
| Convert pictures and videos for sharing | Super+Ctrl+. | `omarchy transcode` | `ffmpeg`, `imagemagick` | none |
| Crash notifications with saved reports, one-click hand-off to the agent, mute per program | — | `omarchy-crash-watch.service`, `omarchy crash mute`, `diagnose-crash` agent skill | | a small watcher service |
| Reset an app's config to the default, keeping a backup | menu, `subcult refresh <app>` | `omarchy refresh …` ([[0048-config-ownership\|ADR 0048]]) | | none |
| External monitor brightness over DDC/CI | brightness keys | `omarchy brightness display ddc` | `ddcutil` | none |
| Text size everywhere: shell, GTK and Qt apps, terminals | settings | `omarchy display text size` | | none |
| Laptop screen comes back when undocked | — | `omarchy-recover-internal-monitor.service`, made event-driven | | none |
| Monospace font switcher | menu | `omarchy font set` ([[0039-fonts-icons\|ADR 0039]]) | | none |
| Captive portal sign-in window; pauses a Tailscale exit node until online | automatic | `omarchy network captive portal` ([[0020-dns\|ADR 0020]]) | | none |
| Setup wizards: git identity and GitHub sign-in, SSH agent with graphical passphrase prompt, SSH server with firewall rule and key | menu | `omarchy setup git`, `setup security ssh agent`, `setup security sshd` | `github-cli`, `gcr-4`, `openssh` | none |
| Factory reset to the freshly installed state | menu | `omarchy setup factory reset` | | none |

## Added beyond Omarchy

Suggested by the agent and accepted by the owner, 2026-11-07.

| Feature | How | Idle cost |
|---|---|---|
| Passwords stay out of clipboard history | Copies marked secret (the `x-kde-passwordManagerHint` MIME type, or from `bw` through a Subarchy wrapper) are not stored in history and are cleared after 30 seconds | none beyond the clipboard watcher |
| Battery charge limit | One toggle that stops charging at a set level (default 80%), using the kernel's `charge_control_end_threshold` where available or the vendor add-on ([[0021-power\|ADR 0021]]); hidden when the hardware has neither | none |
| Picture-in-picture windows float and pin | Hyprland window rules match browser picture-in-picture windows: float, pin across workspaces, fixed corner | none |
| Find files from the launcher | The launcher searches file names with `fd` when asked; no background index | none |

The package tools run as `subcult pkg install`, `subcult pkg aur install` and
`subcult pkg remove` in a floating kitty window, opened from the menu or the
launcher ([[0057-launcher|ADR 0057]]). Changes from Omarchy's versions:

- Omarchy runs `updatedb` after AUR installs; Subarchy has no `plocate` index,
  so that step is dropped.
- They sit beside the curated app installer ([[0044-default-apps|ADR 0044]]):
  the app installer adds integration steps for listed apps, the package tools
  install any package as-is.
- AUR packages are trusted by the user, not vetted by Subarchy; the PKGBUILD
  preview is one key away.
- Flathub search is not included; it could be a third source later.

**Factory reset** works as in Omarchy: the installer keeps an `@factory`
snapshot of the fresh install outside snapper's rotation; a reset swaps it in
as the root on the next boot and returns to first-boot setup. Omarchy's
version removes the user account (for handing a machine on); Subarchy also
offers a mode that keeps `@home` and the user. Needs the installer changes in
[[0049-installer|ADR 0049]].

## Consequences

- Dictation, USB auto-mount and crash notifications are the items with a standing cost. Both
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
