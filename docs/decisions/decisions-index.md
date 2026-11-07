---
title: "Decisions"
type: index
status: active
created: 2026-11-06
updated: 2026-11-06
tags: [index, decision]
aliases: [ADR index]
---

# Decisions

Architecture decision records. One file per decision, numbered in order. A
record starts as **proposed** and moves to **accepted**, **rejected** or
**superseded** after owner review. Do not rewrite an accepted record; add a new
one that supersedes it.

Each record's `status` property holds its state. Create a new record from
`docs/templates/adr-template.md` (Templates: *Insert template*).

![[decisions.base]]

The [[decision-map|decision map]] lists every decision still to take, in
order.

| ADR | Title |
|---|---|
| [[0001-fork-strategy\|0001]] | How Subcarchy relates to Omarchy |
| [[0002-base-distribution\|0002]] | Base distribution |
| [[0003-cpu-architectures\|0003]] | CPU architectures |
| [[0004-kernel\|0004]] | Kernel |
| [[0005-firmware\|0005]] | Firmware and microcode |
| [[0006-gpu-drivers\|0006]] | GPU drivers |
| [[0007-bootloader\|0007]] | Bootloader |
| [[0008-initramfs\|0008]] | Initramfs and kernel images |
| [[0009-disk-layout\|0009]] | Disk layout and filesystem |
| [[0010-disk-encryption\|0010]] | Disk encryption |
| [[0011-snapshots\|0011]] | Snapshots and rollback |
| [[0012-secure-boot\|0012]] | Secure Boot |
| [[0013-boot-splash\|0013]] | Boot splash |
| [[0014-swap-hibernation\|0014]] | Swap and hibernation |
| [[0015-init-system\|0015]] | Init and service manager |
| [[0016-networking\|0016]] | Networking and Wi-Fi |
| [[0017-audio\|0017]] | Audio |
| [[0018-bluetooth\|0018]] | Bluetooth |
| [[0019-firewall\|0019]] | Firewall |
| [[0020-dns\|0020]] | DNS and name resolution |
| [[0021-power\|0021]] | Power and thermal management |
| [[0022-printing\|0022]] | Printing and device discovery |
| [[0023-authentication\|0023]] | Secrets and login factors |
| [[0024-time-locale-input\|0024]] | Time zone, locale and input methods |
| [[0025-package-repository\|0025]] | Package repository and signing |
| [[0026-update-model\|0026]] | Update model and migrations |
| [[0027-third-party-software\|0027]] | Third-party software |
| [[0028-developer-toolchains\|0028]] | Developer toolchains |
| [[0029-display-protocol\|0029]] | Display protocol |
| [[0030-login-manager\|0030]] | Login manager |
| [[0031-session-manager\|0031]] | Session manager |
| [[0032-compositor\|0032]] | Compositor |
| [[0033-portals\|0033]] | XDG portals |
| [[0034-shell-toolkit\|0034]] | Shell toolkit |
| [[0035-plugin-api\|0035]] | Shell plugin API |
| [[0036-shell-components\|0036]] | Shell components, lock and idle |
| [[0037-theming\|0037]] | Theming system |
| [[0038-wallpaper\|0038]] | Wallpaper |
| [[0039-fonts-icons\|0039]] | Fonts and icons |
| [[0040-terminal\|0040]] | Terminal emulator |
| [[0041-shell-prompt\|0041]] | Interactive shell and prompt |
| [[0042-browser\|0042]] | Browser |
| [[0043-file-manager\|0043]] | File manager |
| [[0044-default-apps\|0044]] | Default app set |

Related: [[home|Docs home]]
