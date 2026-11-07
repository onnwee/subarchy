---
title: "ADR 0060: Backups"
type: decision
status: accepted
adr: 60
created: 2026-11-07
updated: 2026-11-07
tags: [decision, adr, storage]
aliases: [ADR 0060, Backups, restic]
---

# ADR 0060: Backups

Accepted 2026-11-07.

## Decision

Revised 2026-11-07: **restic**, because it is what the homelab mostly uses.
(The first version chose borg; the homelab's records showed restic as the
main tool and Almaz's Borgmatic repository as "secondary/untrusted".)

- **restic** backs up `/home` and the list of installed packages to a
  repository on the owner's homelab, on a systemd timer.
- Encrypted at the client by restic; the repository password lives in the
  user's keyring ([[0023-authentication|ADR 0023]]).
- Retention starts at 7 daily, 4 weekly, 6 monthly snapshots
  (`restic forget --prune`); `restic check` runs monthly, and a test restore
  is part of setup.
- The timer runs on AC power only and skips metered networks
  ([[0054-lightweight-battery-first|ADR 0054]]). Btrfs snapshots
  ([[0011-snapshots|ADR 0011]]) protect the system; restic protects user
  files.

## Target

From Machinum's `10-inventory/Backup Matrix.md` (updated 2026-10-10):

- Almaz and the NUC run restic to the router's USB drive on Volga.
- Kvant's encrypted copies go to Dozor.

Proposed by the agent: a restic repository on **Dozor** over SFTP. Dozor
already holds the fleet's independent encrypted recovery copies, while the
Volga router is a limited USB target that the fleet rules say not to
administer without a separately verified SSH identity. Confirm before setup;
it needs a user and storage on Dozor, which is a homelab change.

## Options considered

| Option | Why not chosen |
|---|---|
| Borg with borgmatic (first version) | The homelab mainly uses restic; Almaz's borg repository is marked untrusted. |
| Router USB on Volga | Limited target; administration needs a separately verified identity. |
| Proton Drive as target | Could be a second, offsite copy later. |

## Consequences

- Package: `restic` (Arch `extra`).
- A first-run step creates the SSH key and repository, stores the password,
  and runs the first backup and a restore test.
- There is no offsite copy yet, as in the rest of the homelab.

Related: [[decision-map|Decision map]] · [[0011-snapshots|ADR 0011]] · [[0023-authentication|ADR 0023]]
