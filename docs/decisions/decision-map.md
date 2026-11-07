---
title: "Decision map"
type: index
status: active
created: 2026-11-06
updated: 2026-11-06
tags: [index, decision]
aliases: [Decision order, Build decisions]
---

# Decision map

Every choice Subcarchy has to make, from the base system up, in the order they
are taken. Earlier decisions constrain later ones, so the order matters more
inside a layer than across layers.

Each decision becomes an ADR when it is taken. The **Omarchy 4.5 choice**
column is the default to borrow from; it is not a recommendation.

Reference machine: `sputnik`, Dell XPS 15 9520, Intel Iris Xe with NVIDIA RTX
3050 Ti Mobile (hybrid graphics), UEFI with Secure Boot off, LUKS2 and btrfs on
NVMe.

## Foundation

| # | Decision | Omarchy 4.5 choice | Status |
|---|---|---|---|
| F1 | Base distribution and package manager | Arch Linux, pacman | [[0002-base-distribution\|ADR 0002]]: Arch, pacman, rolling |
| F2 | CPU architectures supported | x86_64 plus several aarch64 platforms | [[0003-cpu-architectures\|ADR 0003]]: x86_64 only |
| F3 | Kernel | `linux-omarchy` (BORE CPU scheduler, ADIOS I/O scheduler), no fallback kernel | [[0004-kernel\|ADR 0004]]: `linux-zen`, `linux-lts` fallback |
| F4 | Firmware and microcode | `linux-firmware` split packages, Intel and AMD microcode | [[0005-firmware\|ADR 0005]]: detected vendors, fwupd |
| F5 | GPU driver policy (Intel, AMD, NVIDIA, hybrid) | Per-vendor install scripts, NVIDIA open DKMS | [[0006-gpu-drivers\|ADR 0006]]: open DKMS + 580xx legacy, iGPU with on-demand NVIDIA, 32-bit libraries always |

## Boot and storage

| # | Decision | Omarchy 4.5 choice | Status |
|---|---|---|---|
| B1 | Bootloader | Limine | [[0007-bootloader\|ADR 0007]]: Limine, UEFI |
| B2 | Initramfs generator and UKI | mkinitcpio, Limine hook | [[0008-initramfs\|ADR 0008]]: mkinitcpio, systemd hooks, UKIs |
| B3 | Disk layout and filesystem | btrfs with subvolumes | [[0009-disk-layout\|ADR 0009]]: btrfs subvolumes, 4 GiB ESP |
| B4 | Disk encryption and unlock | LUKS2, passphrase | [[0010-disk-encryption\|ADR 0010]]: LUKS2 always, passphrase; TPM2/FIDO2 opt-in |
| B5 | Snapshots and rollback | snapper with `limine-snapper-sync` boot entries | [[0011-snapshots\|ADR 0011]]: snapshot on system update, keep 5, boot entries |
| B6 | Secure Boot | Not configured | [[0012-secure-boot\|ADR 0012]]: opt-in with sbctl |
| B7 | Boot splash | Plymouth | [[0013-boot-splash\|ADR 0013]]: Plymouth, themed |
| B8 | Swap and hibernation | zram; hibernation optional | [[0014-swap-hibernation\|ADR 0014]]: zram, hibernation opt-in |

## System services

| # | Decision | Omarchy 4.5 choice | Status |
|---|---|---|---|
| S1 | Init and service manager | systemd | [[0015-init-system\|ADR 0015]]: systemd |
| S2 | Networking and Wi-Fi | NetworkManager | [[0016-networking\|ADR 0016]]: NetworkManager, wpa_supplicant |
| S3 | DNS and name resolution | systemd-resolved (stub resolver), Avahi for mDNS | [[0020-dns\|ADR 0020]]: resolved, per-network trust, Quad9 DoT |
| S4 | Audio | PipeWire with WirePlumber | [[0017-audio\|ADR 0017]]: PipeWire, JACK, realtime |
| S5 | Bluetooth | BlueZ | [[0018-bluetooth\|ADR 0018]]: BlueZ |
| S6 | Firewall | ufw with `ufw-docker` | [[0019-firewall\|ADR 0019]]: ufw, ufw-docker |
| S7 | Power and thermal management | `omarchy-power-profiles-daemon`, thermald | [[0021-power\|ADR 0021]]: power-profiles-daemon, auto AC/battery, thermald |
| S8 | Printing and device discovery | CUPS, Avahi | [[0022-printing\|ADR 0022]]: CUPS socket-activated, Avahi |
| S9 | Authentication: PAM, polkit, keyring, fingerprint, FIDO | gnome-keyring, shell polkit agent, optional fprintd | [[0023-authentication\|ADR 0023]]: gnome-keyring, fingerprint/FIDO opt-in |
| S10 | Time, locale and input methods | tzupdate, fcitx5 | [[0024-time-locale-input\|ADR 0024]]: auto time zone, input methods on demand |

## Packages and updates

| # | Decision | Omarchy 4.5 choice | Status |
|---|---|---|---|
| P1 | Package repository and signing | `[omarchy]` repo with its own keyring | [[0025-package-repository\|ADR 0025]]: own signed repo, CI-built, AUR rebuilds |
| P2 | Third-party software policy (AUR, Flatpak, AppImage) | Rebuilt AUR packages in its repo; `yay` installed | [[0027-third-party-software\|ADR 0027]]: yay + Flathub |
| P3 | Update model and migrations | Staged stable mirror, rc and edge channels; `omarchy update` plus timestamped migrations | [[0026-update-model\|ADR 0026]]: staged stable + edge, one update command |
| P4 | Developer toolchains | mise | [[0028-developer-toolchains\|ADR 0028]]: mise |

## Session

| # | Decision | Omarchy 4.5 choice | Status |
|---|---|---|---|
| L1 | Display server protocol | Wayland only, Xwayland for legacy apps | open |
| L2 | Login manager | SDDM with an Omarchy theme | open |
| L3 | Session manager | uwsm | open |
| L4 | Compositor | Hyprland, configured in Lua | open |
| L5 | XDG portals, screen sharing | `xdg-desktop-portal-hyprland`, GTK portal | open |

## Desktop shell

| # | Decision | Omarchy 4.5 choice | Status |
|---|---|---|---|
| D1 | Shell toolkit | Quickshell (QML) | open |
| D2 | Plugin API and Omarchy plugin compatibility | Omarchy shell manifest API | open |
| D3 | Bar, launcher and menus | Shell plugins | open |
| D4 | Notifications, OSD, lock screen, idle | Shell plugins | open |
| D5 | Theming system | `colors.toml` per theme rendered into per-app templates | open |
| D6 | Wallpaper engine | `owe` | open |
| D7 | Fonts and icon theme | JetBrains Mono Nerd, Yaru icons | open |

## Applications and tooling

| # | Decision | Omarchy 4.5 choice | Status |
|---|---|---|---|
| A1 | Terminal emulator | Foot default; Alacritty, Ghostty, Kitty supported | open |
| A2 | Login shell and prompt | bash, starship | open |
| A3 | Editor | Neovim with LazyVim | open |
| A4 | Browser | Chromium | open |
| A5 | File manager | Nautilus | open |
| A6 | Default app set and web apps | `omarchy-base.packages` apps, 11 web apps | open |
| A7 | Command-line interface for the distribution | `omarchy <group> <action>` over 556 commands | open |
| A8 | AI agent integration | `omarchy agent`, agents bar widget | open |

## Delivery and identity

| # | Decision | Omarchy 4.5 choice | Status |
|---|---|---|---|
| R1 | Configuration ownership: system defaults versus user files | `/usr/share/omarchy/default` sourced, `config/` copied to `~/.config` | open |
| R2 | Installer and install image | Omarchy ISO and installer | open |
| R3 | Hardware support policy | Per-vendor fix scripts | open |
| R4 | Name, `os-release` and brand | Omarchy | open |
| R5 | Licence | MIT | open |
| R6 | Source hosting and CI | GitHub | open |

Related: [[0001-fork-strategy|ADR 0001]] · [[decisions-index|Decisions]] · [[omarchy-overview|Omarchy component map]]
