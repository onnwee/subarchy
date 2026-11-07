---
title: "Shell and look: design"
type: plan
status: proposed
created: 2026-11-07
updated: 2026-11-07
tags: [plan, shell, theme, design]
aliases: [Shell design, Look and feel design]
---

# Shell and look: design

Goal: a fresh Subarchy install looks and behaves like `sputnik` does on
2026-11-07, bar included, while staying light on battery. Agreed with the
owner in conversation on 2026-11-07; this note records it for review before
the implementation plan.

## What the owner decided

- Start from `sputnik`'s current look: the `subcult-minimal` theme on
  Omarchy 4.5's shell with Patrick's `patrickfanella.monitor-bar`.
- Build the bar now, in Subarchy's own Quickshell shell, not a fork of
  Omarchy's ([[0034-shell-toolkit|ADR 0034]], [[0035-plugin-api|ADR 0035]]).
  Omarchy's MIT-licensed `Commons/`, `Ui/` and services code is copied piece
  by piece where it helps.
- Port only plugins that are active on `sputnik` today, minus Bitwarden, plus
  a few inactive ones that make good defaults. xray, Bitwarden and weather
  radar are not ported.
- Icons are Papirus (the owner's original pick in
  [[0039-fonts-icons|ADR 0039]]), not Yaru.
- Battery comes first when off AC ([[0054-lightweight-battery-first|ADR 0054]]);
  on AC nothing is slowed down.

Assumed by the agent, open to correction: fonts follow `sputnik` (JetBrains
Mono in the shell, Adwaita Sans in GTK) rather than ADR 0039's Space Grotesk;
the Subcult Ink app colours ship as static files until Theme Tender is
packaged.

## Stages

| Stage | Delivers | Done when |
|---|---|---|
| 1 | Look layer; shell with every default bar widget showing live data; notification daemon, OSD, polkit dialog | VM screendump matches `sputnik`'s bar layout and colours; all checks below pass |
| 2 | A click-out panel for each widget that has one on `sputnik` (audio, network, Bluetooth, calendar, weather, Soma, notifications, power) | Each panel opens, shows live data and closes in the VM |
| 3 | Plugins shipped off by default | Each can be enabled from config and loads without errors |

Each stage is one or more PRs; each PR is done when CI is green and it merges.

## Architecture

- **Code** in `shell/`, installed to `/usr/share/subcult/shell/`.
- **Process**: a user unit `subcult-shell.service`, part of the graphical
  session, runs `quickshell -n -p /usr/share/subcult/shell` with
  `Restart=on-failure`, so a crash brings the shell (and the wallpaper,
  [[0038-wallpaper|ADR 0038]]) back.
- **Layout of `shell/`**:

| Path | Holds |
|---|---|
| `shell.qml` | Root: loads config, theme, services, one bar per monitor, background, notification and OSD windows |
| `Commons/` | `Theme` (palette roles to tokens), `Style` (sizes, fonts, spacing), `Power` (on-battery state and interval selection), `Config` (layered config) |
| `Ui/` | Bar slot, icon button, popup panel, tooltip |
| `services/` | Thin wrappers over Quickshell modules where a widget needs shared state |
| `widgets/<id>/` | One folder per widget: `manifest.json`, `Widget.qml`, optional `Panel.qml`, optional `tests/` |
| `tests/` | Shell-level tests |

- **Bar**: one layer-shell window per monitor on the top edge, about 26 px
  at scale 1, opaque `base`. Three sections, left, centre and right. **Full**
  on the primary monitor and the laptop panel, **Minimal** (workspaces and a
  monitor glyph) on the rest, as `monitor-bar` does now.
- **Plugin API v0**: [[0068-shell-plugin-api-v0|ADR 0068]].
- **Config**, layered per [[0048-config-ownership|ADR 0048]]: defaults in
  `/usr/share/subcult/default/shell/bar.json`, user overrides in
  `~/.config/subcult/shell/bar.json`, merged key by key, user wins.
- **Palette**: `Theme` reads `/usr/share/subcult/default/theme/palette.json`,
  overridden by `~/.config/subcult/theme/palette.json`, and watches the file so
  a theme change repaints without a restart. Theme Tender will write the user
  file later ([[0037-theming|ADR 0037]]).

## Look layer

| Item | Setting |
|---|---|
| Palette file | Theme Tender's role names. `base` `#100B19`, `mantle` `#0B0812`, `crust` `#06040A`, `surface0` `#1F1830`, `text` `#F0ECE4`, `subtext1` `#DDD6E8`, `subtext0` `#9A92A8`, `overlay0` `#5E5570`, `green` `#00FF88`, `mauve` `#8F4BC8`, `lavender` `#A78BFA`, `selection_bg` `#3B2470`, and ANSI 0–15 from `subcult-minimal`'s `colors.toml` |
| Theme tokens | `accent` = `green`, `border` = `mauve`, `borderInactive` = `surface0`, `selection` = `selection_bg`, `muted` = `overlay0`, `warning` = `yellow`, `error` = `red` |
| Compositor | `default/hypr/looknfeel.lua`: gaps 0, border 1 px, rounding 0, opacity 1, no blur, shadow, dimming or animations. Border colours in a separate include that Theme Tender will own |
| Fonts | JetBrainsMono Nerd Font (`ttf-jetbrains-mono-nerd`) for the shell and terminal; Adwaita Sans (`adwaita-fonts`) for GTK; Noto for fallback, CJK and emoji. fontconfig defaults set system-wide |
| GTK | Adwaita-dark, `prefer-dark`, through a GSettings schema override in the package plus `/etc/xdg/gtk-3.0/settings.ini` and `gtk-4.0/settings.ini` |
| Icons | Papirus-Dark (`papirus-icon-theme`, `extra`) |
| Cursor | Catppuccin Latte Mauve, size 24 (`catppuccin-cursors-latte`, AUR, vendored in `packaging/aur/`) |
| kitty | System default config: JetBrainsMono Nerd Font 9 pt, no padding, decorations hidden, block cursor, Subcult Ink colours |
| Neovim | Subcult Ink colour scheme |
| Background | Drawn by the shell. Plain `base` until `subarchy-wallpapers` exists; then image 01, `acid-negative-space` |

Subcult Ink colours for other apps arrive when those apps join the package
list.

## Widgets and plugins

### On by default

| Widget | Origin | Data source | Idle cost on battery |
|---|---|---|---|
| Menu | New (SUBCULT mark) | None | None |
| Workspaces, active window | Rebuilt from Omarchy and `monitor-bar` | `Quickshell.Hyprland` events | None |
| Indicators | Rebuilt | Do-not-disturb from the notification server, idle inhibit (`IdleInhibitor`), screen recording from a PipeWire capture node | None |
| Microphone, audio | Rebuilt | `Quickshell.Services.Pipewire` | None |
| Keyboard layout, display | Rebuilt | Hyprland events | None |
| Network | Rebuilt | `Quickshell.Networking` | None |
| Bluetooth | Rebuilt | `Quickshell.Bluetooth` | None |
| Battery and power profile | Rebuilt | `Quickshell.Services.UPower`, power-profiles-daemon | None |
| Tray | Rebuilt | `Quickshell.Services.SystemTray` | None |
| Update count | New | File watch on the `subcult-update check` state file | None |
| Clock, world clock (Elsewhen) | Rebuilt | One timer aligned to the minute | One wake a minute |
| Notifications and centre | Port of `foamy.notification-center` | `Quickshell.Services.Notifications`; history in memory plus a small JSON file | None |
| OSD | Rebuilt from `omarchy.osd` | PipeWire volume events; brightness and caps-lock bindings call the shell over IPC | None |
| Polkit dialog | Rebuilt from Omarchy's | `Quickshell.Services.Polkit` | None |
| Soma.fm | Port of `io.github.joshuaswarren.somafm` | SomaFM API when the panel opens; now-playing polled only while playing; playback through mpv | None unless playing |
| Weather | Port of `ashuttl.linecast` | Open-Meteo through Linecast's vendored Python | Current conditions every 15 min on AC, 30 min on battery; forecast, sun, moon and tides every 2 h on AC, 6 h on battery, and on panel open when older than the AC interval |
| Calendar | Port of `tmn73.calendar` | Its sync as a user timer (Google through the Workspace CLI, CalDAV, iCal) writing a cache the widget watches | Sync every 15 min on AC, 60 min on battery |
| AltSwitch | Port of `io.github.pablo-merino.altswitch` | Hyprland client list, read only while open | None |

### Shipped, off by default (stage 3)

Dell power (`stappmus.dell-power-profiles`, enabled automatically on Dell
hardware through `subcult hw`), downloads (`ussego.otoru`), auto-wallpaper
(`dizziee.auto-wallpaper`), agents usage (rebuilt from `omarchy.agents`).
Licences of `foamy`, `otoru` and the Dell plugin are checked before porting;
the Dell plugin's notice names David Heinemeier Hansson.

### Not ported

| Plugin | Why |
|---|---|
| Bitwarden, xray, weather radar | Owner's call, 2026-11-07 |
| omaplug | v0 loads no third-party plugins, so a plugin manager has nothing to manage |
| Switchyard, n8n, HT3 | Homelab or one device; belong in the owner's profile |
| lock-explorer | Replaced by the standalone lock program ([[0036-shell-components\|ADR 0036]]) |
| `shell.settings` | A settings panel is its own later piece |
| Installed but inactive plugins not listed above | Not active on `sputnik`, or poll in the background |

### Porting rules

- Rename out of Omarchy's namespace: ids become `subcult.<name>`,
  `omarchy-calendar-sync` becomes `subcult-calendar-sync`, config moves under
  `~/.config/subcult/`.
- Record upstream URL, commit and MIT notice in `shell/THIRD_PARTY_NOTICES.md`.
- Fix polling found on read: Soma's 1 s timer that waits for a service
  becomes an event; Linecast's 30 s and 60 s view timers run only while the
  panel is open.
- Keep each plugin's tests, renamed.
- Only weather, calendar sync and Soma use the network, and each starts only
  after the user sets it up: a location, an account, pressing play.

## Battery policy

- `Power` exposes `onBattery` from UPower.
- Every manifest declares its timers and network calls (`cost`, see
  [[0068-shell-plugin-api-v0|ADR 0068]]). Widgets ask `Power` for an interval
  instead of hard-coding one, giving their AC and battery values.
- A panel's content loads only while the panel is open.
- Minimal bars do not start data services they do not show.
- No animations in the default theme; the compositor's are off too.
- On AC every interval returns to its AC value at once.

## Testing

- **Unit tests** (`qmltestrunner`) for the pure logic: interval selection,
  config merging, Full/Minimal layout, palette-to-token mapping, plus the
  ported plugins' own tests.
- **Static**: `qmllint` on every QML file; a `make verify` target loads the
  shell headless (`QT_QPA_PLATFORM=offscreen`) and fails on any QML error.
- **VM**: `tools/iso/install-test.py` gains a desktop stage after autologin:
  `subcult-shell.service` active; no QML warnings in the journal; a QMP
  screendump of the bar contains `#100B19`, `#F0ECE4` and `#8F4BC8`;
  `hyprctl layers` shows one bar per monitor. The screendump is kept for a
  side-by-side look with `sputnik`.
- **Battery**: a test-only UPower mock (`python-dbusmock` `upower` template)
  flips AC and battery; the test reads the intervals the shell reports over
  IPC.
- **Idle budget**: the shell's context switches over 60 idle seconds in the
  VM. The first build sets the budget; CI fails a change that exceeds it by
  more than 20 %.
- **Owner on `sputnik`** after stage 1: scale 1.6, the real tray apps, real
  battery.

## Doc changes that come with stage 1

- [[0039-fonts-icons|ADR 0039]]: revision note for fonts (follow `sputnik`)
  and icons (Papirus restored).
- [[0068-shell-plugin-api-v0|ADR 0068]] accepted.
- [[triage|Triage]]: placements updated to match this note.
- [[roadmap|Roadmap]] Phase 3: shell item split into the three stages.

## Out of scope here

Launcher ([[0057-launcher|ADR 0057]]), lock screen and screensaver
([[0036-shell-components|ADR 0036]]), SDDM, Plymouth and Limine themes,
the wallpaper package, Theme Tender templates, clipboard and emoji pickers,
settings panel, dock.

Related: [[0034-shell-toolkit|ADR 0034]] · [[0035-plugin-api|ADR 0035]] · [[0036-shell-components|ADR 0036]] · [[0037-theming|ADR 0037]] · [[0061-default-bar-calendar|ADR 0061]] · [[0054-lightweight-battery-first|ADR 0054]] · [[triage|Triage]]
