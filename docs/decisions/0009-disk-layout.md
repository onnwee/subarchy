---
title: "ADR 0009: Disk layout and filesystem"
type: decision
status: accepted
adr: 9
created: 2026-11-06
updated: 2026-11-06
tags: [decision, adr, storage]
aliases: [ADR 0009, B3, Disk layout]
---

# ADR 0009: Disk layout and filesystem

Decision map item B3. Accepted 2026-11-06.

## Decision

GPT disk with two partitions:

| Partition | Size | Format | Mount |
|---|---|---|---|
| EFI system partition | **4 GiB** | FAT32 | `/boot` |
| Root | rest of disk | LUKS2 ([[0010-disk-encryption\|ADR 0010]]) containing btrfs | `/` |

btrfs subvolumes, mounted with `compress=zstd:3`:

| Subvolume | Mount | Why separate |
|---|---|---|
| `@` | `/` | Snapshotted and rolled back |
| `@home` | `/home` | User data survives a root rollback |
| `@log` | `/var/log` | Logs survive a rollback, for diagnosing what went wrong |
| `@pkg` | `/var/cache/pacman/pkg` | Package cache stays out of snapshots |
| snapshot subvolumes | per B5 | Created by the snapshot tool |

## Options considered

| Option | Why not chosen |
|---|---|
| 2 GiB EFI partition (Omarchy) | Two kernels' UKIs plus snapshot history copies would fill it. |
| ext4 without snapshots | No btrfs snapshots for rollback (B5). |

## Borrowed from Omarchy

The subvolume names and mount options match Omarchy on `sputnik`.

## Consequences

- 4 GiB on `/boot` is taken from every install; on small disks the installer
  should warn.
- A swap subvolume may be added by B8.

Related: [[decision-map|Decision map]] · [[0007-bootloader|ADR 0007]] · [[0008-initramfs|ADR 0008]]
