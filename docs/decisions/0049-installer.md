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

- A **Subarchy live ISO**, built with **archiso** in CI.
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
- The installer asks which disk to use and leaves every other disk untouched.
  On a machine with another OS on a second disk it creates its own EFI
  partition on the target disk, adds its own firmware boot entry, and can
  add a Limine entry that chainloads the other disk's bootloader.
  The first install is `sputnik`'s empty second drive: `nvme0n1`, a 931.5 GB
  SPCC SSD with a blank GPT and no partitions (2026-11-07). Omarchy stays on
  `nvme1n1` (Crucial P5) as the fallback; its Limine firmware entry is
  `Boot0002`.
- The installer takes an `@factory` btrfs snapshot of the finished install,
  kept outside snapper's rotation, and supports a first-boot owner setup, so
  factory reset works ([[0056-quality-of-life|ADR 0056]]). Borrowed from
  Omarchy's `omarchy-system-factory-reset` and
  `install/provisioning/` (owner setup, LUKS re-key).
- ISO size grows with the full default app set
  ([[0044-default-apps|ADR 0044]]).

## Progress

- 2026-11-07: the live ISO builds with archiso (`make iso`) and boots in QEMU
  (`make iso-test`). The scripted installer `install/subarchy-install`
  installs the base system into a VM disk: LUKS2, btrfs subvolumes, UKIs for
  both kernels, Limine, snapper, zram and NetworkManager. The disk boots,
  takes the passphrase on the serial console and reaches `running`
  (`make install-test`). Still to come: the TUI, snapshot boot entries,
  Plymouth, the desktop and the offline package cache.
- 2026-11-07, later: snapshot entries, Plymouth and the desktop session
  landed. `subarchy-setup` asks the questions with plain line prompts instead
  of a full-screen TUI, so it works on any console including serial; the VM
  test drives it end to end with `--guided`. The image carries Subarchy's own
  packages in `/opt/subarchy/repo`; Arch packages still come from the
  network, so the offline cache is still open.

Related: [[decision-map|Decision map]] · [[0050-hardware-support|ADR 0050]]
