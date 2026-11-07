---
title: "ADR 0049: Installer and install image"
type: decision
status: accepted
adr: 49
created: 2026-11-06
updated: 2026-11-06
tags: [decision, adr, delivery]
aliases: [ADR 0049, R2, Installer, ISO]
---

# ADR 0049: Installer and install image

Decision map item R2. Accepted 2026-11-06.

## Decision

- A **Subcarchy live ISO**, built with **archiso** in CI.
- A **terminal (TUI) installer** on the ISO: keyboard, disk, LUKS passphrase,
  user, hostname and time zone, then the scripted install of everything the
  decisions above define.
- The ISO carries a **package cache** for the base and default apps, so an
  install works offline; with network it can fetch newer packages from the
  stable channel.

## Options considered

| Option | Why not chosen |
|---|---|
| Arch ISO plus an install script | First boot looks like Arch, and it needs network. |
| Calamares graphical installer | Heavy to build and theme; the disk, LUKS and btrfs choices must be encoded in its modules. |

## Borrowed from Omarchy

- `omacom/omarchy-iso` (MIT, active on 2026-11-06): the ISO builder and its
  offline mirror built from the package lists.
- `install/provisioning/setup-form.sh`: the questions asked and the rules
  their answers are checked against, shared by the ISO and first-boot setup.
- `install/` scripts for the post-partition steps.

## Consequences

- The installer creates the layout from [[0009-disk-layout|ADR 0009]],
  encryption from [[0010-disk-encryption|ADR 0010]], the systemd UKIs from
  [[0008-initramfs|ADR 0008]], Limine from [[0007-bootloader|ADR 0007]] and
  the snapper config from [[0011-snapshots|ADR 0011]].
- Hardware detection ([[0005-firmware|ADR 0005]],
  [[0006-gpu-drivers|ADR 0006]], [[0050-hardware-support|ADR 0050]]) runs in
  the installer.
- The CI boot test ([[0026-update-model|ADR 0026]]) uses the same ISO in a
  VM.
- ISO size grows with the full default app set
  ([[0044-default-apps|ADR 0044]]).

Related: [[decision-map|Decision map]] · [[0050-hardware-support|ADR 0050]]
