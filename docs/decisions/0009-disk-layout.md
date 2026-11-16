---
title: "ADR 0009: Disk layout and filesystem"
type: decision
status: accepted
adr: 9
created: 2026-11-06
updated: 2026-11-16
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

## Progress

- 2026-11-16: #124's guided-installer scope is reconciled under roadmap
  #230, using the owner's delegated authority to settle first-release
  choices. Keep the whole-disk layout above; installing into free space
  beside another OS on the same disk is deferred beyond the first release.
  It would need a superseding or extending layout decision covering ESP
  reuse versus a separate ESP, required free space and any resizing policy,
  encrypted-root placement, boot entries and recovery. The current installer
  wipes the selected disk, so exposing an alongside option without that
  design would risk the existing system. Reopening it also needs tests on a
  disk already containing another OS that check the other partitions and
  boot path survive. See [[guided-installer-scope|scope and follow-up]].

Related: [[decision-map|Decision map]] · [[0007-bootloader|ADR 0007]] · [[0008-initramfs|ADR 0008]]
