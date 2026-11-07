---
title: "ADR 0060: Backups"
type: decision
status: accepted
adr: 60
created: 2026-11-07
updated: 2026-11-07
tags: [decision, adr, storage]
aliases: [ADR 0060, Backups, Borg]
---

# ADR 0060: Backups

Accepted 2026-11-07.

## Decision

- **Borg**, driven by **borgmatic**, backs up `/home` (and the list of
  installed packages) to a borg repository on the owner's homelab over SSH,
  on a systemd timer.
- Encrypted at the client (borg `repokey-blake2`), with the passphrase in the
  user's keyring ([[0023-authentication|ADR 0023]]).
- Retention starts at 7 daily, 4 weekly, 6 monthly archives; `borgmatic check`
  runs monthly, and a test restore is part of setup.
- The timer runs on AC power only and skips metered networks
  ([[0054-lightweight-battery-first|ADR 0054]]). Snapshots
  ([[0011-snapshots|ADR 0011]]) protect the system; borg protects user files.

## Which homelab repository

The owner said borg already runs on the homelab. The homelab's own record
(Machinum `10-inventory/Backup Matrix.md`, updated 2026-10-10) says:

- Almaz has a Borgmatic repository marked **"secondary/untrusted backup repo
  … until cleanup"**, with no documented restore test.
- The primary homelab tool is **restic** (Almaz and the NUC to the router's
  USB drive), and Kvant keeps encrypted copies on Dozor.

So the target host is open: a fresh borg repository on Almaz after its
cleanup, or one on Dozor beside Kvant's encrypted copies. Whichever is chosen
needs a restore test before it counts as protection.

## Options considered

| Option | Why not chosen |
|---|---|
| restic (the homelab's main tool) | The owner chose borg. |
| Proton Drive CLI as target | Not chosen; could be a second, offsite copy later. |

## Consequences

- Packages: `borg`, `borgmatic` (Arch `extra`).
- A first-run step creates the SSH key, the repository and the passphrase,
  and runs the first backup and a restore test.
- There is no offsite copy yet, as in the rest of the homelab.

Related: [[decision-map|Decision map]] · [[0011-snapshots|ADR 0011]] · [[0023-authentication|ADR 0023]]
