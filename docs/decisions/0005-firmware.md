---
title: "ADR 0005: Firmware and microcode"
type: decision
status: accepted
adr: 5
created: 2026-11-06
updated: 2026-11-06
tags: [decision, adr, foundation]
aliases: [ADR 0005, F4, Firmware]
---

# ADR 0005: Firmware and microcode

Decision map item F4. Accepted 2026-11-06.

## Decision

- The installer detects the hardware and installs only the matching
  `linux-firmware-*` packages (Arch splits firmware by vendor: `intel`,
  `nvidia`, `amdgpu`, `realtek`, `mediatek`, `broadcom`, `atheros` and others).
- CPU microcode is chosen the same way: `intel-ucode` or `amd-ucode`.
- **fwupd** is installed for system, dock and peripheral firmware updates
  through LVFS.

## Options considered

| Option | Why not chosen |
|---|---|
| Full firmware set | All `linux-firmware-*` packages total about 813 MB installed (2026-11-06); `sputnik` needs about 413 MB of them. Docks and swapped hardware would work without action, but the smaller install was preferred. |

## Consequences

- Detection needs a reliable map from PCI and USB IDs to firmware packages.
  Omarchy's hardware scripts and the kernel's `modinfo` firmware lists are the
  sources to borrow from.
- New hardware after install can lack firmware: a new Wi-Fi card, a dock, a
  USB network adapter. Subcarchy needs a command that re-runs detection and
  installs what is missing, and a notification when the kernel logs a missing
  firmware file. Both belong to R3 (hardware support policy).
- `linux-firmware-whence` and the licence files always install.
- Microcode loads early through the initramfs or bootloader; B2 must keep that.

Related: [[decision-map|Decision map]] · [[0004-kernel|ADR 0004]]
