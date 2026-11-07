---
title: "ADR 0025: Package repository and signing"
type: decision
status: accepted
adr: 25
created: 2026-11-06
updated: 2026-11-06
tags: [decision, adr, packages]
aliases: [ADR 0025, P1, Package repository]
---

# ADR 0025: Package repository and signing

Decision map item P1. Accepted 2026-11-06.

## Decision

- Subarchy has **its own pacman repository**, listed in `pacman.conf` with
  `SigLevel = Required`.
- It holds every Subarchy package and **rebuilds of the AUR packages
  Subarchy depends on**. Omarchy's `[omarchy]` repository is not used.
- Packages are **built in CI** from PKGBUILDs in this repository
  (`packaging/`) and signed with a Subarchy key.

AUR packages the decisions so far need, all currently served only by
`[omarchy]` on `sputnik` (2026-11-06):

| Package | Needed by |
|---|---|
| `nvidia-580xx-dkms`, `nvidia-580xx-utils`, `lib32-nvidia-580xx-utils` | [[0006-gpu-drivers\|ADR 0006]] |
| `limine-snapper-sync` | [[0011-snapshots\|ADR 0011]] |
| `limine-mkinitcpio-hook` | [[0008-initramfs\|ADR 0008]] |
| `ufw-docker` | [[0019-firewall\|ADR 0019]] |
| `tzupdate` | [[0024-time-locale-input\|ADR 0024]] |
| `yay` | [[0027-third-party-software\|ADR 0027]] |

## Options considered

| Option | Why not chosen |
|---|---|
| Keep `[omarchy]` for AUR rebuilds | Trusts and tracks a third-party repository. |

## Hosting

First candidate: the package registry on `git.subcult.tv`. On 2026-11-06 it
reported version `28.3.0`. Gitea's documentation describes an Arch registry
at `/api/packages/{owner}/arch/{repository}/{arch}`, uploads by `PUT`, and a
verification key at `/api/packages/{owner}/arch/repository.key`. The
documentation does not say whether a Subarchy-owned key can sign the
database. If it cannot, Gitea's own key becomes the trust root, or the
repository moves to a static host with `repo-add` and our key. Test this
before building on it.

## Consequences

- A `subarchy-keyring` package installs and trusts the signing key, like
  `omarchy-keyring`.
- CI must rebuild DKMS and AUR packages when their upstream changes, and
  rebuild against the staged Arch snapshot ([[0026-update-model|ADR 0026]]).
- The owner holds the signing key; it is on `soyuz` (2026-11-07), and the
  owner will copy it to a second place. A rotation plan is still needed.

## Progress

- 2026-11-07: `packaging/aur/` holds the reviewed, pinned AUR PKGBUILDs for
  `limine-mkinitcpio-hook` 1.40.0 and `limine-snapper-sync` 1.32.1.
  `packaging/aur/build.sh` builds them in a clean `archlinux` container into
  the local, unsigned test repository `build/repo`. Signing and hosting are
  still open.

Related: [[decision-map|Decision map]] · [[0026-update-model|ADR 0026]] · [[0027-third-party-software|ADR 0027]]
