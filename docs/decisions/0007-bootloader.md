---
title: "ADR 0007: Bootloader"
type: decision
status: accepted
adr: 7
created: 2026-11-06
updated: 2026-11-06
tags: [decision, adr, boot]
aliases: [ADR 0007, B1, Bootloader]
---

# ADR 0007: Bootloader

Decision map item B1. Accepted 2026-11-06.

## Decision

Subcarchy boots with **Limine** on UEFI. The menu lists `linux-zen` first and
as default, `linux-lts` as the fallback, then snapshot entries (B5).

## Options considered

| Option | Why not chosen |
|---|---|
| systemd-boot with UKIs | Simplest Secure Boot, but no native snapshot entries. |
| GRUB with grub-btrfs | Mature snapshot menu, but large, slow and complex; LUKS unlock in GRUB is slow. |

## Borrowed from Omarchy

- `default/limine/limine.conf` and `default.conf`: menu layout, `timeout: 1`,
  terminal palette and branding keys (`interface_branding`,
  `interface_branding_color`), which take Subcarchy's name and colours (R4).
- `limine-mkinitcpio-hook` and `limine-snapper-sync` packaging, pending B2
  and B5.

## Consequences

- Secure Boot (B6) with Limine means signing the Limine EFI binary and
  enrolling a hash of its config, so the config cannot be edited without
  re-enrolling. Verify the procedure against the Limine version shipped.
- The EFI system partition holds kernels or UKIs for two kernels plus
  snapshot history. On `sputnik` each Omarchy UKI is about 256 MB and
  `limine-snapper-sync` keeps extra copies; a 2 GB partition already has 784 MB
  used with one kernel. B3 must size the partition for two kernels.
- Limine needs UEFI or BIOS firmware it supports; Subcarchy targets UEFI only
  unless R3 says otherwise.

Related: [[decision-map|Decision map]] · [[0004-kernel|ADR 0004]] · [[0006-gpu-drivers|ADR 0006]]
