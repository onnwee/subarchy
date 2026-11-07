---
title: "ADR 0004: Kernel"
type: decision
status: accepted
adr: 4
created: 2026-11-06
updated: 2026-11-06
tags: [decision, adr, foundation]
aliases: [ADR 0004, F3, Kernel]
---

# ADR 0004: Kernel

Decision map item F3. Accepted 2026-11-06.

## Decision

- Default kernel: **`linux-zen`** from Arch's official repository (7.2.11 on
  2026-11-06).
- Fallback kernel: **`linux-lts`** (6.18.57 on 2026-11-06), installed alongside
  as a second boot entry.
- Subarchy does not build its own kernel.

## Options considered

| Option | Why not chosen |
|---|---|
| Own kernel from `linux-omarchy`'s BORE and ADIOS config | Full control, but a rebuild and signing on every kernel release, and every kernel regression becomes ours. |
| `linux` (Arch stock) | Most tested and has a prebuilt `nvidia-open` module, but no desktop tuning. |
| `linux-cachyos` | Adds a third-party repository to trust and track. |
| No fallback (Omarchy's choice) | `sputnik` has run without one since 2026-11-02; a bad kernel then needs a snapshot entry or a live USB. |

## Consequences

- No kernel maintenance: both kernels come from Arch.
- Out-of-tree modules (NVIDIA, DisplayLink `evdi`, `v4l2loopback`) must be
  DKMS packages, built for both kernels on every kernel update. Prebuilt
  modules such as `nvidia-open` only target stock `linux`, so they cannot be
  used. F5 picks the NVIDIA package on that basis.
- Both kernels need headers installed (`linux-zen-headers`,
  `linux-lts-headers`) for DKMS.
- The boot partition holds two kernels and their initramfs images. B1 to B3
  must size the EFI system partition for that, plus any snapshot entries.
- The bootloader (B1) must default to `linux-zen` and list `linux-lts` as the
  fallback.

Related: [[decision-map|Decision map]] · [[0002-base-distribution|ADR 0002]] · [[0005-firmware|ADR 0005]]
