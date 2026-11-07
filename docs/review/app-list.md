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
| Chromium | browser | yes |  | repo | `chromium` | Preinstalled (owner, 2026-11-06), with extensions set by policy ([[0042-browser\|ADR 0042]]); also a candidate for running web apps |

### Communication

| App | Role | Preinstalled | Default | Source | Package | Notes |
|---|---|---|---|---|---|---|
| Signal | messenger |  |  | repo | `signal-desktop` |  |
| Vesktop | chat |  |  | aur | `vesktop` | Discord client; `vesktop-bin` also exists |
| Halloy | irc |  |  | repo | `halloy` |  |
| Proton Mail Bridge | mail-bridge |  |  | repo | `protonmail-bridge` | Pairs with Thunderbird |

### AI and development

| App | Role | Preinstalled | Default | Source | Package | Notes |
|---|---|---|---|---|---|---|
| Claude Code (TUI) | agent | yes | yes | aur | `claude-code` | Preinstalled as a system package so every user has it; per-user mise installs still work ([[0047-ai-agents\|ADR 0047]]) |
| Codex (TUI) | agent | yes |  | repo | `openai-codex` | Preinstalled from Arch's `extra`; per-user mise installs still work |
| T3 Code Nightly | agent-gui | yes | yes | aur | `t3code-nightly-bin` | AUR (0.1.8 nightly on 2026-11-07); stable is `t3code-bin`. Replaces the hand-installed AppImage on `sputnik` |
| VS Code | editor | yes |  | aur | `visual-studio-code-bin` | Microsoft build, as on `sputnik`; Code-OSS is `code` in `extra` |
| Neovim | editor | yes | yes | repo | `neovim` | With Subarchy's LazyVim config package ([[0045-editor\|ADR 0045]]) |

### Office and writing

| App | Role | Preinstalled | Default | Source | Package | Notes |
|---|---|---|---|---|---|---|
| Obsidian | notes | yes | yes | repo | `obsidian` |  |

### Utilities and system

| App | Role | Preinstalled | Default | Source | Package | Notes |
|---|---|---|---|---|---|---|
| Bitwarden CLI | password-manager | yes | yes | repo | `bitwarden-cli` | `bw` command |
| Bitwarden | password-manager |  |  | repo | `bitwarden` | Desktop app, offered |
| PipeWire Control Center | audio-routing | yes | yes | aur | `pipewire-control-center` |  |
| Ark | archive | yes | yes | repo | `ark` | KDE; pairs with Dolphin |
| Popsicle | usb-flasher |  |  | aur | `popsicle` |  |
| Solaar | device-manager |  |  | repo | `solaar` | Logitech devices; could install on detection ([[0050-hardware-support\|ADR 0050]]) |
| OpenPods (LibrePods) | device-manager |  |  | aur | `librepods` | AirPods; the `sputnik` launcher is named OpenPods and runs `librepods` |
| Print Settings | printer-setup | yes |  | repo | `system-config-printer` | CUPS is on every install ([[0022-printing\|ADR 0022]]) |
| Voxtype configuration | dictation |  | yes | aur | `voxtype-bin` | Dictation; `voxtype` (source build) also exists |

### Music and video

| App | Role | Preinstalled | Default | Source | Package | Notes |
|---|---|---|---|---|---|---|
| VLC | media-player | yes | yes | repo | `vlc`, `vlc-plugin-ffmpeg`, `vlc-plugin-freetype`, `vlc-plugin-ass` | `vlc` pulls `vlc-gui-qt`, which brings `vlc-plugins-base` (Ogg, Matroska, FLAC, Opus, Vorbis, MP3, AAC, VP8/9, AV1) and `vlc-plugins-video-output`. Added: FFmpeg (H.264, H.265 and most other codecs, VA-API decoding), FreeType (subtitle and on-screen text), ASS (styled subtitles). `vlc-plugins-extra` and `vlc-plugins-all` stay off. VLC 3 uses Qt 5, so it adds the Qt 5 libraries |
| cliamp | music-player |  |  | aur | `cliamp` | Terminal music player |
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

### Core viewers and tools (gaps filled 2026-11-07)

| App | Role | Preinstalled | Default | Source | Package | Notes |
|---|---|---|---|---|---|---|
| Okular | pdf-viewer | yes | yes | repo | `okular` | Annotations, forms, signatures; reuses the KDE libraries Dolphin installs |
| swayimg | image-viewer | yes | yes | repo | `swayimg` | Wayland-native, gallery mode |
| grim + slurp + satty | screenshot | yes | yes | repo | `grim`, `slurp`, `satty` | Capture, region pick, annotate; run from a keybinding, nothing in the background |
| Thunderbird | mail |  | yes | repo | `thunderbird` | Offered; works with Proton Mail Bridge over IMAP/SMTP |
| Launcher calculator | calculator | yes | yes | repo | `libqalculate` | Sums typed in the shell launcher |
| Qalculate! | calculator | yes |  | repo | `qalculate-qt` | Same engine: units, history, graphs |
| btop | system-monitor | yes | yes | repo | `btop` | Opens in kitty; themed from the palette |
| gpu-screen-recorder | screen-recorder | yes | yes | repo | `gpu-screen-recorder` | Hardware-encoded; started and stopped from a keybinding or the shell |

### Command-line and terminal apps (2026-11-07)

All preinstalled, all from Arch's repositories. They are system packages so
every user and Subarchy's own scripts can rely on them; per-user mise versions
still work ([[0028-developer-toolchains|ADR 0028]]).

| Group | Packages |
|---|---|
| Basics (included without asking) | `curl`, `wget`, `rsync`, `unzip`, `7zip`, `less`, `man-db`, `man-pages`, `wl-clipboard`, `git`, `openssh` |
| Modern shell tools | `bat`, `eza`, `fd`, `ripgrep`, `fzf`, `zoxide`, `jq`, `go-yq` |
| Terminal apps | `lazygit`, `tmux`, `fastfetch`, `lazydocker` |
| Git and forges | `github-cli`, `tea`, `git-delta` |
| Media | `yt-dlp`, `ffmpeg`, `imagemagick` |
| Disk usage | `dust`, `duf` |
| Containers | `docker`, `docker-compose`, `docker-buildx` ([[0055-containers\|ADR 0055]]) |

Already decided elsewhere: zsh, starship and atuin
([[0041-shell-prompt|ADR 0041]]), btop, yazi, Neovim. Not preinstalled:
`tealdeer`, `plocate` (needs a daily index timer), `zellij`, `direnv`,
`just`, `hyperfine`, `tokei`.

### Chromium extensions

Installed automatically with Chromium ([[0042-browser|ADR 0042]]).

| Extension | Web Store ID | Notes |
|---|---|---|
| Claude | `fcoeoabgfenejglbffodgkkbkcdhcgfn` | Anthropic; paid Claude plan |
| ChatGPT (Codex browser control) | `hehggadaopoacecdllhhajmbjkdcmajg` | OpenAI; browser control needs the ChatGPT/Codex desktop app. On `sputnik` that is `openai-codex-desktop`, which only `[omarchy]` carries; the AUR has `chatgpt-desktop`. Not on the app list yet |

## Web apps

None are preinstalled and the catalogue is empty (owner, 2026-11-07). The
"install web app" command, borrowed from Omarchy's `omarchy-webapp-install`,
stays available: it opens any site in its own Chromium app window with a
launcher entry.

## Gaps

All core roles have an app as of 2026-11-07. Gaps and better picks get added
here as they come up.

Apps on `sputnik` that this draft leaves out (from
[[sputnik-apps|Apps on sputnik]]), in case any were missed: 1Password,
Proton Mail app, Typora, Xournal++, Kdenlive, Ardour, Guitarix, TuxGuitar,
qpwgraph, Feishin, Streamlink Twitch GUI, Chatterino, Vivaldi, Helix, Podman
Desktop, Unity Hub, GeForce NOW, Moonlight, ProtonUp-Qt, JDownloader, TigerVNC,
scrcpy, LocalSend, Raspberry Pi Imager, Filelight, File Roller, Tailscale tray,
BlueFerry, LibreOffice.

Related: [[0044-default-apps|ADR 0044]] · [[sputnik-apps|Apps on sputnik]] · [[0054-lightweight-battery-first|ADR 0054]]
