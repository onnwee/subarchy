---
title: "Shell and look: design"
type: plan
status: accepted
created: 2026-11-07
updated: 2026-11-12
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
- Rebuild only plugins that are active on `sputnik` today, minus Bitwarden, plus
  a few inactive ones that make good defaults. xray, Bitwarden and weather
  radar are left out. HT3 and n8n are kept.
- A choice of fonts, as Omarchy offers, from the owner's own list, with any
  Nerd Font downloadable and owned fonts importable ([[#Fonts]]).
- Every widget is written fresh and is Subarchy's own; no plugin or Omarchy
  shell code is copied ([[#Ownership]]).
- Icons are Papirus (the owner's original pick in
  [[0039-fonts-icons|ADR 0039]]), not Yaru.
- The cursor is Subarchy's own, coloured from a palette role the user picks
  ([[#Cursor]]).
- Battery comes first when off AC ([[0054-lightweight-battery-first|ADR 0054]]);
  on AC nothing is slowed down.
- Interface text follows the monospace font by default; GTK and Qt follow
  the system fonts. Owned fonts such as Dank Mono get icons from a fallback,
  with an opt-in patcher.

Assumed by the agent, open to correction: the Subcult Ink app colours ship as
static files until Theme Tender is packaged; GTK colours follow the system
palette once Theme Tender's GTK template exists.

## Stages

| Stage | Delivers | Done when |
|---|---|---|
| 1 | Look layer; shell with every default bar widget showing live data; notification daemon, OSD, polkit dialog | VM screendump matches `sputnik`'s bar layout and colours; all checks below pass |
| 2 | A click-out panel for each widget that has one on `sputnik` (audio, network, Bluetooth, calendar, weather, Soma, notifications, power, HT3, n8n) | Each panel opens, shows live data and closes in the VM |
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
| Fonts | Three switchable roles through fontconfig aliases, JetBrains Mono by default for monospace and interface, Libertinus Mono for serif ([[#Fonts]]) |
| GTK | adw-gtk3-dark (`adw-gtk-theme`; Adwaita-dark until 2026-11-12, whose GTK 3 colours Pult cannot change), `prefer-dark`, through a GSettings schema override in the package plus `/etc/xdg/gtk-3.0/settings.ini` and `gtk-4.0/settings.ini` |
| Icons | Papirus-Dark (`papirus-icon-theme`, `extra`) |
| Cursor | Subarchy's own flat cursor set, coloured from a palette role, default `lavender`, size 24 ([[#Cursor]]) |
| kitty | System default config: JetBrainsMono Nerd Font 9 pt, no padding, decorations hidden, block cursor, Subcult Ink colours |
| Neovim | Subcult Ink colour scheme |
| Background | Drawn by the shell. Plain `base` until `subarchy-wallpapers` exists; then image 01, `acid-negative-space` |

Subcult Ink colours for other apps arrive when those apps join the package
list.

## Cursor

Hyprland draws the pointer, so the shell cannot paint it; Subarchy instead
generates its own cursor theme from the palette and the shell regenerates it
when the theme changes.

- **Shapes**: about 15 flat SVG shapes drawn for Subarchy in the 1 px look
  (arrow, text beam, hand, busy, crosshair, the resize arrows, move,
  not-allowed, grab), mapped to the standard cursor names. No third-party
  cursor set.
- **Colour**: the fill is a palette role the user picks, default
  `lavender` (`#A78BFA`, owner 2026-11-07); the outline is `crust`, or `text`
  when the fill is dark. Because it is a role, a theme change recolours it.
- **Build**: `subcult cursor apply` renders the SVGs with `rsvg-convert`
  (`librsvg`), builds a hyprcursor theme with `hyprcursor-util` and an
  Xcursor theme with `xcursorgen` (`xorg-xcursorgen`) at 24, 32 and 48 px,
  into `~/.local/share/icons/subcult-cursor/`, then applies it with
  `hyprctl setcursor` and GSettings.
- **Default**: the package ships a prebuilt `subcult-cursor` in `lavender` at
  `/usr/share/icons/subcult-cursor/`, so the greeter and first login have it;
  the user's copy has the same name and wins.
- **Trigger**: the shell already watches the palette; it runs
  `subcult cursor apply` when the palette or the chosen role changes. No idle
  cost.
- **Settings**: `~/.config/subcult/cursor.json` holds `role` and `size`;
  `subcult cursor set --role <role> --size <px>` changes them. Pickers come
  with the settings panel and launcher.

## Fonts

### Roles

Three fontconfig aliases are the single source of truth. GTK, Qt, the shell
and kitty all point at the alias, never at a family name, so changing a font
changes it everywhere.

| Role | Alias | Default | Used by |
|---|---|---|---|
| Monospace | `monospace` | JetBrainsMono Nerd Font | Terminal, shell, editors |
| Interface | `sans-serif` | Follows monospace (JetBrainsMono Nerd Font Propo) | GTK and Qt interface text |
| Serif | `serif` | Libertinus Mono, then Noto Serif | Documents and reading |

The Propo build is the same family with proportional-width icons, which suits
interface text. GTK's `font-name` and `monospace-font-name` GSettings are set
to the aliases (`Sans 11`, `Monospace 11`), so GTK follows the system. Noto
covers CJK and emoji behind every role.

### Preinstalled

| Font | Package | Role | Size |
|---|---|---|---|
| JetBrains Mono (default) | `ttf-jetbrains-mono-nerd` | Monospace, interface | 232 MB |
| 3270 | `ttf-3270-nerd` | Monospace | 24 MB |
| Adwaita Mono | `ttf-adwaitamono-nerd` | Monospace | 47 MB |
| Space Mono | `ttf-space-mono-nerd` | Monospace | 28 MB |
| Share Tech Mono | `ttf-sharetech-mono-nerd` | Monospace | 7 MB |
| Atkinson Hyperlegible Mono | `otf-atkinsonhyperlegiblemono-nerd` | Monospace | 52 MB |
| Libertinus Mono | `otf-libertinus` (also brings Libertinus Serif, Sans and Math) | Serif | 4.5 MB |
| Liberation | `ttf-liberation` | Times, Arial and Courier metrics, so documents keep their layout | 4 MB |
| Symbols Nerd Font | `ttf-nerd-fonts-symbols`, `ttf-nerd-fonts-symbols-mono` | Icon fallback for every font | 5 MB |
| Noto | `noto-fonts`, `noto-fonts-cjk`, `noto-fonts-emoji` | Fallback | already in the base set |

### Choices, installed when picked

| Font (family name) | Package | Size |
|---|---|---|
| ComicShannsMono | `otf-comicshanns-nerd` | 14 MB |
| Agave | `ttf-agave-nerd` | 15 MB |
| UbuntuMono | `ttf-ubuntu-mono-nerd` | 28 MB |
| CaskaydiaCove | `ttf-cascadia-code-nerd` | 99 MB |
| BlexMono | `ttf-ibmplex-mono-nerd` | 113 MB |
| Victor Mono | `ttf-victor-mono-nerd` | 154 MB |
| Monaspace | `otf-monaspace-nerd` | 393 MB |
| Iosevka Term | `ttf-iosevkaterm-nerd` | 1.1 GB |
| OpenDyslexic Mono | `otf-opendyslexic-nerd` | 41 MB |
| Monofur | `ttf-monofur-nerd` | 23 MB |
| ProFont | `ttf-profont-nerd` | 14 MB |
| ProggyClean | `ttf-proggyclean-nerd` | 22 MB |
| Terminess | `ttf-terminus-nerd` | 32 MB |

Interface and serif choices, installed when picked:

| Font | Package | Role | Size |
|---|---|---|---|
| Alegreya Sans | `otf-alegreya-sans` (AUR rebuild in the Subarchy repository, [[0025-package-repository\|ADR 0025]]) | Interface | small |
| Ubuntu | `ttf-ubuntu-nerd` | Interface | 44 MB |
| Alegreya | `otf-alegreya` (AUR rebuild, as above) | Serif | small |
| Source Serif 4 | `adobe-source-serif-fonts` | Serif | 18 MB |
| Crimson Pro | `otf-crimson-pro` | Serif | 1.5 MB |

Libertinus Mono has one weight, Regular; bold and italic in documents are
synthesised. Libertinus Serif, in the same package, has every weight.

Sizes are pacman's installed sizes on 2026-11-07.

### Commands

| Command | Does |
|---|---|
| `subcult font list [--all]` | The curated list, marking installed and current; `--all` lists every Nerd Fonts family (72 in v3.5.1) |
| `subcult font current` | The family behind each role |
| `subcult font set <family> [--ui \| --serif]` | Checks the font, installs it if needed, points the role's alias at it, sets kitty's `font_family` in the user layer and signals kitty; the shell watches the fontconfig file and repaints live. Without a flag it sets monospace; interface follows unless set separately |
| `subcult font install <name>` | Any Nerd Fonts family: pacman when Arch packages it (through the privilege path, [[0062-privilege-policy\|ADR 0062]]), otherwise the official release archive, checked against the release's SHA-256 list and unpacked into `~/.local/share/fonts/nerd-fonts/` |
| `subcult font import <files>` | Copies fonts the user owns (Dank Mono) into `~/.local/share/fonts/subcult/`, user-only, then runs `check`. It copies nothing when a file is not a font fontconfig reads, two files share a name, or a different file already has that name |
| `subcult font check <family>` | Reports one of: full Nerd Font; works with fallback icons; interface text only (not monospace); breaks TUIs (no box drawing). Reads coverage with fontconfig and fontTools. `set` refuses the last two for the monospace role unless `--force` |
| `subcult font patch <family>` | Opt-in. Runs Nerd Fonts' `font-patcher` (fetched at a pinned version, checksum-verified; needs `fontforge` from `extra`) and writes a separate "<family> Nerd Font" copy; the original is untouched. Warns that commercial licences may forbid modified copies |

Fonts the user owns are never patched or modified automatically: icons come
from the Symbols fallback unless the user runs `patch`. A graphical picker
comes with the launcher ([[0057-launcher|ADR 0057]]).

## Widgets and plugins

Every widget below is written fresh for Subarchy. "Reference" names the
`sputnik` plugin whose features it reproduces; its code is not copied.

### On by default

| Widget | Reference | Data source | Idle cost on battery |
|---|---|---|---|
| Menu | None (SUBCULT mark) | None | None |
| Workspaces, active window | `omarchy.workspaces`, `monitor-bar` | `Quickshell.Hyprland` events | None |
| Indicators | `omarchy.indicators` | Do-not-disturb from the notification server, keep-awake as a logind idle inhibitor (`systemd-inhibit`, state in a file), screen recording from a PipeWire capture node | None |
| Microphone, audio | `omarchy.microphone`, `omarchy.audio` | `Quickshell.Services.Pipewire` | None |
| Keyboard layout, display | `omarchy.keyboard-layout`, `omarchy.monitor` | Hyprland events | None |
| Network | `omarchy.network` | `Quickshell.Networking` | None |
| Bluetooth | `omarchy.bluetooth` | `Quickshell.Bluetooth` | None |
| Battery and power profile | `omarchy.battery` | `Quickshell.Services.UPower`, power-profiles-daemon | None |
| Tray | `omarchy.tray` | `Quickshell.Services.SystemTray` | None |
| Update count | `omarchy.system-update` | File watch on the `subcult-update check` state file | None |
| Clock, world clock | `omarchy.clock`, `omarchy.elsewhen` | One timer aligned to the minute | One wake a minute |
| Notifications and centre | `foamy.notification-center` | `Quickshell.Services.Notifications`; history in memory plus a small JSON file | None |
| OSD | `omarchy.osd` | PipeWire volume events; brightness keys as Hyprland global shortcuts; caps lock over IPC | None |
| Polkit dialog | `omarchy.polkit` | `Quickshell.Services.Polkit` | None |
| Soma.fm | `io.github.joshuaswarren.somafm` | SomaFM API when the panel opens; now-playing polled only while playing; playback through mpv | None unless playing |
| Weather | `ashuttl.linecast` | Current conditions from Open-Meteo; forecast, sun, moon and tides from the `linecast` program ([[#Ownership]]) | Current every 15 min on AC, 30 min on battery; the rest every 2 h on AC, 6 h on battery, and on panel open when older than the AC interval |
| Calendar | `tmn73.calendar` | A user timer syncs Google (Workspace CLI), CalDAV and iCal into a cache the widget watches | Sync every 15 min on AC, 60 min on battery |
| AltSwitch | `io.github.pablo-merino.altswitch` | Hyprland client list, read only while open | None |
| HT3 headphones | `patrickfanella.ht3` (Patrick's) | BlueZ and PipeWire; the device helper runs only while the panel is open | None; shows only while an HT3 is connected |
| n8n | `legendik.n8n` | n8n REST API; API key in the keyring through `secret-tool` | Every 60 s on AC, 5 min on battery; shows only once a server is set up |

### Shipped, off by default (stage 3)

Dell power (reference `stappmus.dell-power-profiles`, enabled automatically
on Dell hardware through `subcult hw`), downloads (`ussego.otoru`),
auto-wallpaper (`dizziee.auto-wallpaper`), agents usage (`omarchy.agents`).

### Not built

| Plugin | Why |
|---|---|
| Bitwarden, xray, weather radar | Owner's call, 2026-11-07 |
| omaplug | v0 loads no third-party plugins, so a plugin manager has nothing to manage |
| Switchyard | Homelab runtime; belongs in the owner's profile |
| lock-explorer | Replaced by the standalone lock program ([[0036-shell-components\|ADR 0036]]) |
| `shell.settings` | A settings panel is its own later piece |
| Installed but inactive plugins not listed above | Not active on `sputnik`, or poll in the background |

### Ownership

- Widgets are written from a feature list taken from using the reference
  plugin and reading its README, not by translating its source. That keeps
  them Subarchy's own under Subarchy's licence
  ([[0053-licence|ADR 0053]]) with no third-party notice. The same applies to
  Omarchy's shell: nothing from `/usr/share/omarchy/shell` is copied.
- Data formats and protocols the references document (the HT3 protocol in
  `PROTOCOL.md`, n8n's REST API, SomaFM's API) are used as specifications.
- One outside program stays outside: the weather widget calls
  [`linecast`](https://github.com/ashuttl/linecast) (v1.15.2 on `sputnik`)
  for forecast, sun, moon and tides. It ships as its own package with its own
  licence, built from a pinned tag in `packaging/`; its licence is checked
  before packaging.
- Names are Subarchy's: widget ids `subcult.<name>`, commands
  `subcult-<group>-<action>`, config under `~/.config/subcult/`.
- Behaviour that polled on `sputnik` is redesigned: Soma's 1 s wait-for-service
  timer becomes an event, Linecast's 30 s and 60 s view timers run only while
  its panel is open, n8n's 30 s poll becomes 60 s on AC and 5 min on battery.
- Only weather, calendar sync, Soma and n8n use the network, and each starts
  only after the user sets it up: a location, an account, pressing play, a
  server.

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
  config merging, Full/Minimal layout, palette-to-token mapping, and each
  widget's own model logic.
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

- [[0039-fonts-icons|ADR 0039]]: revision note for fonts (three switchable
  roles, the owner's list) and icons (Papirus restored).
- [[0068-shell-plugin-api-v0|ADR 0068]] accepted.
- [[triage|Triage]]: placements updated to match this note.
- [[roadmap|Roadmap]] Phase 3: shell item split into the three stages.

## Out of scope here

Launcher ([[0057-launcher|ADR 0057]]), lock screen and screensaver
([[0036-shell-components|ADR 0036]]), SDDM, Plymouth and Limine themes,
the wallpaper package, Theme Tender templates, clipboard and emoji pickers,
settings panel, dock.

Related: [[0034-shell-toolkit|ADR 0034]] · [[0035-plugin-api|ADR 0035]] · [[0036-shell-components|ADR 0036]] · [[0037-theming|ADR 0037]] · [[0061-default-bar-calendar|ADR 0061]] · [[0054-lightweight-battery-first|ADR 0054]] · [[triage|Triage]]
