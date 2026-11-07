---
title: "ADR 0011: Snapshots and rollback"
type: decision
status: accepted
adr: 11
created: 2026-11-06
updated: 2026-11-06
tags: [decision, adr, storage]
aliases: [ADR 0011, B5, Snapshots]
---

# ADR 0011: Snapshots and rollback

Decision map item B5. Accepted 2026-11-06.

## Decision

- **snapper** manages snapshots of the root subvolume `@` only. `/home`,
  `/var/log` and the package cache are not rolled back.
- The **system update command** (P3) takes one snapshot before it upgrades,
  labelled with the Subarchy version. Ad-hoc `pacman` runs do not take
  snapshots.
- snapper keeps the last **5** numbered snapshots; no timeline snapshots.
- **limine-snapper-sync** adds a boot entry for each snapshot, so a broken
  update is undone by booting the previous snapshot from the Limine menu and
  restoring it.

## Options considered

| Option | Why not chosen |
|---|---|
| Every package transaction (`snap-pac`) | Covers ad-hoc installs too, but takes many more snapshots and boot entries. |
| Transactions plus hourly timeline | More disk churn than wanted. |

## Borrowed from Omarchy

- `omarchy-snapshot create|restore` and `install/config/snapper.sh`: the
  snapper config (`NUMBER_LIMIT="5"`, `TIMELINE_CREATE="no"`) and the warning
  when snapper has no config.
- `limine-snapper-sync` setup.

## Consequences

- A package installed outside the update command is covered only by the next
  update's snapshot. The update command should be the normal way to change the
  system; P3 decides whether to warn about direct `pacman` use.
- Snapshot boot entries keep copies of older UKIs on the 4 GiB EFI partition
  ([[0009-disk-layout|ADR 0009]]); five snapshots of two kernels must fit.
- A DKMS failure after an update is recoverable by snapshot as well as by the
  `linux-lts` fallback.

Related: [[decision-map|Decision map]] · [[0009-disk-layout|ADR 0009]] · [[0007-bootloader|ADR 0007]]
