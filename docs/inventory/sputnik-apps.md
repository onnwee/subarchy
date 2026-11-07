---
title: "Apps on sputnik"
type: inventory
status: active
host: sputnik
observed: 2026-11-06
created: 2026-11-06
updated: 2026-11-06
tags: [inventory, local, apps]
aliases: [App list, sputnik apps]
---

# Apps on sputnik

Grouped from the 113 visible desktop launchers in [[local-apps]] (generated).
**(O)** marks apps Omarchy installs. Input for the default app set
([[0044-default-apps|ADR 0044]]).

| Category | Apps |
|---|---|
| Browsers | Zen (default), Chromium (O), Vivaldi |
| Communication | Signal, Vesktop (Discord), Halloy (IRC), Chatterino (Twitch chat), Proton Mail, Proton Mail Bridge, LocalSend (O) |
| AI and development | Claude desktop, ChatGPT/Codex desktop, T3 Code (AppImage), VS Code, Neovim, Helix, Micro, Podman Desktop, Unity Hub with two Unity editors, Docker TUI (O) |
| Office and writing | LibreOffice suite (O), Obsidian (O), Omawrite (O), Hype (O), Signed (O), Typora, Xournal++ |
| Productivity | Super Productivity (custom build), Tadooer Dev and Test |
| Passwords | 1Password, Bitwarden |
| Music and audio | Ardour, Guitarix, TuxGuitar, qpwgraph, PipeWire Control Center, Feishin (Navidrome client), cliamp (O), OpenPods/LibrePods (AirPods) |
| Video and streaming | mpv (O), VLC, Kdenlive, OBS Studio, Omacut (O), Monologue (O), Streamlink Twitch GUI |
| Graphics and 3D | GIMP, Inkscape, Glaxnimate, Pinta (O), FreeCAD, PrusaSlicer, Wayscriber (with configurator), Omasnap (O) |
| Documents and images | Evince (O), Papers, imv (O) |
| Games | Steam, Lutris, ProtonUp-Qt, NVIDIA GeForce NOW, Moonlight (O) |
| Files and disks | Nautilus (O), Yazi, Ark, File Roller, Filelight, disktree (O), GNOME Disks (O), Popsicle, Raspberry Pi Imager |
| Network and remote | Gliff (O), TigerVNC, Tailscale tray, scrcpy, BlueFerry (iPhone Bluetooth), qBittorrent, JDownloader |
| System and settings | kitty, htop, lshw, KWalletManager, Solaar (Logitech), Aether theme builder (O), Print Settings (O), Voxtype configuration, Omacalc (O) |
| Web apps | X (O); own: Flux, RSS Reader, System Operations Dashboard |

## Notes for the default set

- **Overlaps** to settle: three browsers, two password managers, two PDF
  viewers (Evince, Papers), two archive tools (Ark, File Roller), three
  editors plus VS Code.
- **Not installed**: launchers remain for Alacritty, Foot and WezTerm, but none
  of the three is installed. kitty is the only terminal present.
- **Came with libraries**, not chosen: Qt Assistant, Qt Designer, Qt Linguist,
  Qt D-Bus Viewer (`qt6-tools`), FLUID (`fltk1.3`), hwloc's `lstopo`.
- **Outside pacman**: T3 Code (AppImage), Super Productivity custom build,
  Tadooer dev builds, Unity editors, GeForce NOW. The app catalogue needs a
  rule for these.
- No Flatpak apps were installed.

Related: [[local-apps|Desktop applications (generated)]] · [[local-additions|Local additions]] · [[0044-default-apps|ADR 0044]]
