---
title: "ADR 0014: Swap and hibernation"
type: decision
status: accepted
adr: 14
created: 2026-11-06
updated: 2026-11-06
tags: [decision, adr, storage, power]
aliases: [ADR 0014, B8, Swap, Hibernation]
---

# ADR 0014: Swap and hibernation

Decision map item B8. Accepted 2026-11-06.

## Decision

- **zram** swap on every install, through `zram-generator`.
- **Hibernation is opt-in**: one command creates a `@swap` btrfs subvolume
  with a RAM-sized swapfile, configures resume, and rebuilds the UKIs. A
  matching command removes it.

## Options considered

| Option | Why not chosen |
|---|---|
| Hibernation on every install | Costs disk space equal to RAM (31 GB on `sputnik`) on machines that never hibernate. |
| No hibernation | Laptops drain the battery over long suspends. |

## Borrowed from Omarchy

`omarchy hibernation available|setup|remove` and its swapfile and resume
handling. `sputnik` already runs this way: a 31 GB `/swap/swapfile` next to
31 GB of zram.

## Consequences

- The swapfile sits on the encrypted root, so hibernation images are
  encrypted.
- Resume uses the systemd initramfs ([[0008-initramfs|ADR 0008]]), not the
  busybox `resume` hook Omarchy adds.
- The `@swap` subvolume must stay out of snapshots
  ([[0011-snapshots|ADR 0011]]).
- Hibernation with Secure Boot on needs the kernel lockdown rules checked when
  implementing.

Related: [[decision-map|Decision map]] · [[0009-disk-layout|ADR 0009]] · [[0008-initramfs|ADR 0008]]
