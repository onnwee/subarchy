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

Every choice Subarchy has to make, from the base system up, in the order they
are taken. Earlier decisions constrain later ones, so the order matters more
inside a layer than across layers.

Each decision becomes an ADR when it is taken. The **Omarchy 4.5 choice**
column is the default to borrow from; it is not a recommendation.

Cross-cutting principle: [[0054-lightweight-battery-first|ADR 0054]],
lightweight and battery-first defaults with no loss as a desktop.

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
| F5 | GPU driver policy (Intel, AMD, NVIDIA, hybrid) | Per-vendor install scripts, NVIDIA open DKMS | [[0006-gpu-drivers\|ADR 0006]]: open DKMS + 580xx legacy, Intel mode by default; NVIDIA desktop mode offered when docked on AC, never automatic; 32-bit libraries on demand |

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
| B9 | Backups of user files | Not covered | [[0060-backups\|ADR 0060]]: restic to the homelab (Dozor proposed) |

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
| S11 | Containers | Docker, socket-activated; user not in `docker` group | [[0055-containers\|ADR 0055]]: same as Omarchy |
| S12 | VPN and mesh networking | Tailscale panel, Taildrop receive service (optional install) | [[0058-tailscale\|ADR 0058]]: Tailscale preinstalled, panel, Taildrop |
| S13 | sudo and polkit policy | Password; optional permanent passwordless toggle | [[0062-privilege-policy\|ADR 0062]]: listed actions skip it; "skip sudo for X minutes". [[0069-update-authentication\|ADR 0069]]: updates authenticate |
| S14 | Security hardening | ufw, faillock lockout settings | [[0063-security-hardening\|ADR 0063]]: AppArmor, sysctl, lockdown with Secure Boot, security fast path |
| S15 | Privacy and telemetry | — | [[0065-privacy-telemetry\|ADR 0065]]: nothing leaves unless the user acts |

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
| L1 | Display server protocol | Wayland only, Xwayland for legacy apps | [[0029-display-protocol\|ADR 0029]]: Wayland, Xwayland |
| L2 | Login manager | SDDM with an Omarchy theme | [[0030-login-manager\|ADR 0030]]: SDDM, themed |
| L3 | Session manager | uwsm | [[0031-session-manager\|ADR 0031]]: uwsm |
| L4 | Compositor | Hyprland, configured in Lua | [[0032-compositor\|ADR 0032]]: Hyprland, Lua |
| L5 | XDG portals, screen sharing | `xdg-desktop-portal-hyprland`, GTK portal | [[0033-portals\|ADR 0033]]: Hyprland and GTK portals |

## Desktop shell

| # | Decision | Omarchy 4.5 choice | Status |
|---|---|---|---|
| D1 | Shell toolkit | Quickshell (QML) | [[0034-shell-toolkit\|ADR 0034]]: Quickshell, QML |
| D2 | Plugin API and Omarchy plugin compatibility | Omarchy shell manifest API | [[0035-plugin-api\|ADR 0035]]: own API, port what we keep |
| D3 | Bar, launcher and menus | Shell plugins | [[0036-shell-components\|ADR 0036]]: in the shell; launcher in [[0057-launcher\|ADR 0057]] (Raycast-style) |
| D4 | Notifications, OSD, lock screen, idle | Shell plugins | [[0036-shell-components\|ADR 0036]]: notifications and OSD in shell; separate QML lock with screensaver until input; hypridle |
| D5 | Theming system | `colors.toml` per theme rendered into per-app templates | [[0037-theming\|ADR 0037]]: Theme Tender; `subcult-minimal` as base and default |
| D6 | Wallpaper engine | `owe` | [[0038-wallpaper\|ADR 0038]]: shell-drawn, still by default, video opt-in |
| D7 | Fonts and icon theme | JetBrains Mono Nerd, Yaru icons | [[0039-fonts-icons\|ADR 0039]]: JetBrains Mono, Space Grotesk, Oswald, Yaru purple-dark icons |
| D8 | Quality-of-life conveniences and keybindings | Omarchy's bindings, toggles, capture tools | [[0056-quality-of-life\|ADR 0056]]: Omarchy's set, 16 extras, 4 additions |
| D9 | Default bar and calendar | Stock bar | [[0061-default-bar-calendar\|ADR 0061]]: the owner's current bar; Google and CalDAV calendar |

## Applications and tooling

| # | Decision | Omarchy 4.5 choice | Status |
|---|---|---|---|
| A1 | Terminal emulator | Foot default; Alacritty, Ghostty, Kitty supported | [[0040-terminal\|ADR 0040]]: kitty; WezTerm in installer |
| A2 | Login shell and prompt | bash, starship | [[0041-shell-prompt\|ADR 0041]]: zsh login shell, starship + atuin; session env independent of shell |
| A3 | Editor | Neovim with LazyVim | [[0045-editor\|ADR 0045]]: stock LazyVim, forked starter + branding layer, prebuilt |
| A4 | Browser | Chromium | [[0042-browser\|ADR 0042]]: Zen default; Chromium for web apps and agent browser control |
| A5 | File manager | Nautilus | [[0043-file-manager\|ADR 0043]]: Dolphin, yazi |
| A6 | Default app set and web apps | `omarchy-base.packages` apps, 11 web apps | [[0044-default-apps\|ADR 0044]]: lean core, installer and default picker; owner writes the list |
| A7 | Command-line interface for the distribution | `omarchy <group> <action>` over 556 commands | [[0046-distribution-cli\|ADR 0046]]: one dispatcher; Bash glue, Go for complex parts |
| A8 | AI agent integration | `omarchy agent`, agents bar widget | [[0047-ai-agents\|ADR 0047]]: default agent, usage widget, skills; no account manager. Desktop control: [[0059-agent-desktop-control\|ADR 0059]] |
| A9 | Virtual machines | A Windows VM that runs through Docker | [[0064-virtual-machines\|ADR 0064]]: QEMU/KVM, libvirt, virt-manager, no images |

## Delivery and identity

| # | Decision | Omarchy 4.5 choice | Status |
|---|---|---|---|
| R1 | Configuration ownership: system defaults versus user files | `/usr/share/omarchy/default` sourced, `config/` copied to `~/.config` | [[0048-config-ownership\|ADR 0048]]: layered defaults, overrides only in `~/.config` |
| R2 | Installer and install image | Omarchy ISO and installer | [[0049-installer\|ADR 0049]]: own ISO, TUI installer, offline cache |
| R3 | Hardware support policy | Per-vendor fix scripts | [[0050-hardware-support\|ADR 0050]]: port all Omarchy x86 fixes |
| R4 | Name, `os-release` and brand | Omarchy | [[0052-name-identity\|ADR 0052]]: Subarchy; screens SUBCULT; command `subcult`, alias `sub` |
| R5 | Licence | MIT | [[0053-licence\|ADR 0053]]: GPL-3.0-or-later |
| R6 | Source hosting and CI | GitHub | [[0051-hosting-ci\|ADR 0051]]: Gitea primary, GitHub mirror |
| R7 | Versioning | Semantic versions (4.5.0) | [[0066-versioning\|ADR 0066]]: semver from 0.0.0 |
| R8 | User manual | Online manual and agent skill | [[0067-user-manual\|ADR 0067]]: repository source, offline on device, agent skill |

Related: [[0001-fork-strategy|ADR 0001]] · [[decisions-index|Decisions]] · [[omarchy-overview|Omarchy component map]]
