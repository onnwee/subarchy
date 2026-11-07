---
title: "App list"
type: review
status: draft
review: pending
created: 2026-11-06
updated: 2026-11-06
tags: [review, apps]
aliases: [Default apps list, App catalogue]
---

# App list

The owner's list of apps for Subarchy, first draft 2026-11-06. The installer
and the default-app picker read it ([[0044-default-apps|ADR 0044]]). It is not
complete: gaps get filled and better picks replace these as work goes on.

Every app here is **offered** in the installer. A small **preinstalled** core
keeps installs light ([[0054-lightweight-battery-first|ADR 0054]]); the
"Preinstalled" and "Default" values below are proposals for the owner to
change.

## Columns

| Column | Meaning |
|---|---|
| App | Display name |
| Role | Role it can fill; the default picker offers apps by role |
| Preinstalled | `yes` = part of the lean core; blank = offered in the installer only |
| Default | `yes` = the role's default; one per role |
| Source | `repo` (Arch), `aur` (rebuilt in Subarchy's repository, [[0025-package-repository\|ADR 0025]]), `mise` ([[0028-developer-toolchains\|ADR 0028]]), `build` (Subarchy packages it from source), `appimage` |
| Package | Package name or tool ID, checked 2026-11-06 |
| Notes | Integration needs and open points |

## Apps

### Core already decided by ADRs

| App | Role | Preinstalled | Default | Source | Package | Notes |
|---|---|---|---|---|---|---|
| kitty | terminal | yes | yes | repo | `kitty` | [[0040-terminal\|ADR 0040]] |
| Dolphin | file-manager | yes | yes | repo | `dolphin` | [[0043-file-manager\|ADR 0043]] |
| yazi | terminal-file-manager | yes | yes | repo | `yazi` | [[0043-file-manager\|ADR 0043]] |

### Browsers

| App | Role | Preinstalled | Default | Source | Package | Notes |
|---|---|---|---|---|---|---|
| Zen | browser | yes | yes | aur | `zen-browser-bin` | [[0042-browser\|ADR 0042]] |
| Chromium | browser |  |  | repo | `chromium` | Also a candidate for running web apps in app windows ([[0042-browser\|ADR 0042]]) |

### Communication

| App | Role | Preinstalled | Default | Source | Package | Notes |
|---|---|---|---|---|---|---|
| Signal | messenger |  |  | repo | `signal-desktop` |  |
| Vesktop | chat |  |  | aur | `vesktop` | Discord client; `vesktop-bin` also exists |
| Halloy | irc |  |  | repo | `halloy` |  |
| Proton Mail Bridge | mail-bridge |  |  | repo | `protonmail-bridge` | Needs a mail client; none is on the list yet |

### AI and development

| App | Role | Preinstalled | Default | Source | Package | Notes |
|---|---|---|---|---|---|---|
| Claude Code (TUI) | agent |  | yes | mise | `claude` | Default agent proposal ([[0047-ai-agents\|ADR 0047]]); `claude-code` also exists in the AUR |
| Codex (TUI) | agent |  |  | mise | `codex` | `openai-codex` is also in Arch's `extra` |
| T3 Code Nightly | agent-gui |  |  | appimage | T3 Code AppImage | Outside pacman; needs the AppImage rule open in [[0044-default-apps\|ADR 0044]] |
| VS Code | editor |  |  | aur | `visual-studio-code-bin` | Microsoft build, as on `sputnik`; Code-OSS is `code` in `extra` |
| Neovim | editor | yes | yes | repo | `neovim` | With Subarchy's LazyVim config package ([[0045-editor\|ADR 0045]]) |

### Office and writing

| App | Role | Preinstalled | Default | Source | Package | Notes |
|---|---|---|---|---|---|---|
| Obsidian | notes |  |  | repo | `obsidian` |  |

### Utilities and system

| App | Role | Preinstalled | Default | Source | Package | Notes |
|---|---|---|---|---|---|---|
| Bitwarden | password-manager |  | yes | repo | `bitwarden` |  |
| PipeWire Control Center | audio-routing |  |  | aur | `pipewire-control-center` |  |
| Ark | archive | yes | yes | repo | `ark` | KDE; pairs with Dolphin |
| Popsicle | usb-flasher |  |  | aur | `popsicle` |  |
| Solaar | device-manager |  |  | repo | `solaar` | Logitech devices; could install on detection ([[0050-hardware-support\|ADR 0050]]) |
| OpenPods (LibrePods) | device-manager |  |  | aur | `librepods` | AirPods; the `sputnik` launcher is named OpenPods and runs `librepods` |
| Print Settings | printer-setup | yes |  | repo | `system-config-printer` | CUPS is on every install ([[0022-printing\|ADR 0022]]) |
| Voxtype configuration | dictation |  | yes | aur | `voxtype-bin` | Dictation; `voxtype` (source build) also exists |

### Music and video

| App | Role | Preinstalled | Default | Source | Package | Notes |
|---|---|---|---|---|---|---|
| VLC | media-player | yes | yes | repo | `vlc` | Plugins are split packages; pick a minimal set |
| cliamp | music-player |  |  | aur | `cliamp` | Terminal music player |
| ferrosonic | music-client |  |  | build | `ferrosonic` (to package) | Terminal Subsonic/Navidrome client, MIT. No Arch or AUR package. `sputnik` runs 0.7.0 built by hand into `/usr/local/bin`; upstreams are `jaidaken/ferrosonic` and the `ferrosonic-ng` fork; pick one |
| OBS Studio | recorder |  |  | repo | `obs-studio` |  |

### Graphics and 3D

| App | Role | Preinstalled | Default | Source | Package | Notes |
|---|---|---|---|---|---|---|
| GIMP | image-editor |  | yes | repo | `gimp` |  |
| Pinta | image-editor |  |  | repo | `pinta` | Lighter alternative to GIMP |
| Inkscape | vector-editor |  | yes | repo | `inkscape` |  |
| Glaxnimate | animation |  |  | repo | `glaxnimate` |  |
| FreeCAD | cad |  |  | repo | `freecad` |  |
| PrusaSlicer | slicer |  |  | repo | `prusa-slicer` |  |

### Games and downloads

| App | Role | Preinstalled | Default | Source | Package | Notes |
|---|---|---|---|---|---|---|
| Steam | game-store |  |  | repo | `steam` | `multilib`; brings the 32-bit graphics libraries ([[0006-gpu-drivers\|ADR 0006]]) |
| Lutris | game-launcher |  |  | repo | `lutris` | Also brings the 32-bit libraries |
| qBittorrent | torrent |  |  | repo | `qbittorrent` |  |

## Gaps to fill

Roles the lean core needs ([[0044-default-apps|ADR 0044]]) or the list implies,
with no app picked yet:

- **PDF viewer**: `sputnik` has Evince and Papers.
- **Image viewer**: `sputnik` has imv.
- **Calculator**: `sputnik` has Omacalc.
- **Screenshot and annotation**: `sputnik` has Omasnap and Wayscriber.
- **Mail client** for Proton Mail Bridge.
- **System monitor**: `sputnik` has btop and htop.
- **Web apps**: which ones, and whether Chromium runs them.

Apps on `sputnik` that this draft leaves out (from
[[sputnik-apps|Apps on sputnik]]), in case any were missed: 1Password,
Proton Mail app, Typora, Xournal++, Kdenlive, Ardour, Guitarix, TuxGuitar,
qpwgraph, Feishin, Streamlink Twitch GUI, Chatterino, Vivaldi, Helix, Podman
Desktop, Unity Hub, GeForce NOW, Moonlight, ProtonUp-Qt, JDownloader, TigerVNC,
scrcpy, LocalSend, Raspberry Pi Imager, Filelight, File Roller, Tailscale tray,
BlueFerry, LibreOffice.

Related: [[0044-default-apps|ADR 0044]] · [[sputnik-apps|Apps on sputnik]] · [[0054-lightweight-battery-first|ADR 0054]]
