---
title: "ADR 0026: Update model and migrations"
type: decision
status: accepted
adr: 26
created: 2026-11-06
updated: 2026-11-06
tags: [decision, adr, packages, updates]
aliases: [ADR 0026, P3, Update model, Channels]
---

# ADR 0026: Update model and migrations

Decision map item P3. Accepted 2026-11-06.

## Decision

Two channels:

| Channel | Arch packages come from | For |
|---|---|---|
| **stable** (default) | A tested snapshot of Arch, advanced after CI installs, boots and checks it | Everyone |
| **edge** (opt-in) | Arch mirrors directly | Testers and the owner |

Subcarchy's own repository ([[0025-package-repository|ADR 0025]]) follows the
same channel split.

One **update command** does, in order:

1. Take a snapper snapshot ([[0011-snapshots|ADR 0011]]).
2. Upgrade all packages.
3. Check DKMS modules built for both kernels; if not, say so and keep the
   previous kernel bootable.
4. Run pending **migrations**: timestamped scripts that change user or system
   configuration between Subcarchy versions, each run once.
5. Report what changed and whether a reboot is needed.

## Options considered

| Option | Why not chosen |
|---|---|
| Direct rolling only | Every Arch breakage reaches users the day it lands. |
| Staged only | Leaves testers without an early channel. |

## Borrowed from Omarchy

- The channel design: `default/pacman/mirrorlist-stable`, `mirrorlist-rc`,
  `mirrorlist-edge` and `omarchy channel set`. On 2026-11-06 Omarchy's stable
  mirror served a `core.db` dated 2026-10-22, while Arch's mirror had
  2026-11-05: about two weeks of staging.
- `omarchy-update` and `omarchy migrate`: snapshot first, then upgrade, then
  migrations named by Unix timestamp.
- The pacman hooks that guard updates (`00-omarchy-update-guard.hook`) and
  pause compositor reloads during a transaction.

## Open implementation choice

How the stable snapshot is served:

- **Own mirror**: sync Arch's `core`, `extra` and `multilib` for x86_64 at a
  tested point, as Omarchy does. Needs storage and bandwidth.
- **Arch Linux Archive date pin**: point stable at
  `archive.archlinux.org/repos/YYYY/MM/DD/`. No storage, but check whether
  Arch accepts the archive as a regular mirror before relying on it.

## Consequences

- Stable users run Arch packages about two weeks old. Security fixes may need
  a way to move the snapshot early.
- CI must test a full install and boot per snapshot advance; that test is the
  gate for stable.
- Direct `pacman -Syu` bypasses the snapshot and migrations; the update guard
  should warn.

Related: [[decision-map|Decision map]] · [[0025-package-repository|ADR 0025]] · [[0011-snapshots|ADR 0011]]
