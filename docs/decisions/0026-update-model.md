---
title: "ADR 0026: Update model and migrations"
type: decision
status: accepted
adr: 26
created: 2026-11-06
updated: 2026-11-13
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

Subarchy's own repository ([[0025-package-repository|ADR 0025]]) follows the
same channel split.

One **update command** does, in order:

1. Take a snapper snapshot ([[0011-snapshots|ADR 0011]]).
2. Upgrade all packages.
3. Check DKMS modules built for both kernels; if not, say so and keep the
   previous kernel bootable.
4. Run pending **migrations**: timestamped scripts that change user or system
   configuration between Subarchy versions, each run once.
5. Update firmware through fwupd, AUR packages through yay, and mise tools.
6. Offer to remove orphaned packages and prune the package cache
   (`paccache`, from `pacman-contrib`).
7. Report what changed, which services need a restart, and whether a reboot
   is needed.

A daily **update check** (systemd timer) shows an indicator in the bar when
updates are available; nothing installs on its own. Added 2026-11-07,
borrowed from `omarchy update` (`firmware`, `aur pkgs`, `mise`,
`orphan pkgs`, `pkg prune`, `restart`) and `omarchy-update-user-notify`.

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

## How the stable snapshot is served

Decided 2026-11-08 by the owner: the **Arch Linux Archive date pin**. Stable
points `core`, `extra` and `multilib` at
`https://archive.archlinux.org/repos/YYYY/MM/DD/$repo/os/$arch`; the date
is `default/pacman/snapshot`, shipped in the `subarchy` package and advanced
by a commit once CI has installed and booted that day. `subcult channel set
stable|edge` writes `/etc/pacman.d/subcult-mirrorlist` (the archive line, or
an include of Arch's mirrorlist for edge) and `/etc/pacman.d/subcult-repo`
(the Subarchy repository's server for that channel), and `subcult update`
refreshes the stable mirrorlist from the shipped date before upgrading. The
other option, an own mirror as Omarchy runs, needs storage and bandwidth on
Almaz for the same result. The Archive documents this use (a dated
`Server` line) and serves every day's state; it is one host, so an outage
delays stable updates rather than breaking them.

## Consequences

- Stable users run Arch packages about two weeks old. Security fixes may need
  a way to move the snapshot early.
- CI must test a full install and boot per snapshot advance; that test is the
  gate for stable.
- Direct `pacman -Syu` bypasses the snapshot and migrations; the update guard
  should warn.

## Progress

- 2026-11-07: `subcult update` (`cmd/subcult-update`, `internal/update`)
  does steps 1 to 7 above: snapper snapshot, `pacman -Syu`, the DKMS check
  for every installed kernel, per-user migrations from
  `/usr/share/subcult/migrations` (markers in
  `~/.local/state/subcult/migrations`), fwupd/yay/mise when installed,
  orphan removal on confirmation, `paccache -rk2`, and a report of the
  snapshot, DKMS problems and whether a reboot is needed. `--dry-run` prints
  what would change. `subcult update check` counts updates with
  `checkupdates`. The VM install test runs it on a fresh install. Not yet:
  the channels, the daily check timer and bar indicator, and service restart
  detection.
- 2026-11-08: the channels (issue #69): `subcult channel`, `subcult channel
  set stable|edge` (`cmd/subcult-channel`, `internal/channel`), the
  installer puts new systems on stable, and `subcult update` refreshes the
  stable mirrorlist from the shipped snapshot date. The Subarchy repository
  server per channel is written to `/etc/pacman.d/subcult-repo`, which
  `pacman.conf` includes once packages are published there (#67).
- 2026-11-07, later: the daily check is a user timer
  (`subcult-update-check.timer`, enabled for every user by the package) that
  writes the count to `~/.local/state/subcult/update-count` for the bar to
  read. The root steps run through `subcult-update privileged`, which sudo
  allows without a password (ADR 0062). The bar indicator, channels and
  restart detection remain.
- 2026-11-13: only the snapshot and package steps stop `subcult update`.
  A failed DKMS query is a warning. After a failed migration the reload,
  restarts and indicator refresh still run and the report is printed,
  since the packages are already replaced; the command then exits 1. An
  interrupt during the DKMS check or the migrations stops the run there.
  fwupd's "nothing to do" (exit 2) is not reported as a failure, and
  `--yes` passes fwupd `--assume-yes --no-reboot-check`; the report then
  says that staged firmware updates apply at the next reboot.

Related: [[decision-map|Decision map]] · [[0025-package-repository|ADR 0025]] · [[0011-snapshots|ADR 0011]]
