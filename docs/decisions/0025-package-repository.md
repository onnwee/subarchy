---
title: "ADR 0025: Package repository and signing"
type: decision
status: accepted
adr: 25
created: 2026-11-06
updated: 2026-11-13
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
verification key at `/api/packages/{owner}/arch/repository.key`. Answered
2026-11-08 (issue #44): the registry signs the database and every package it
serves with a key of its own, generated per instance and published at
`repository.key`; nothing a client uploads carries our signature into the
repository. On `git.subcult.tv` that key is `CCE8 B0F3 BCDD 601D 9097 73E4
466A A6E8 2414 53D2` ("Arch Registry", RSA 2048, created 2026-11-07). So the
trust root for the package repository is the registry's key, carried by
`subarchy-keyring`; the owner's own signing key stays for what Subarchy
publishes outside the registry (release images and their checksums). A new
registry key, or a move to a static host with `repo-add`, means a new
keyring release.

## Consequences

- A `subarchy-keyring` package installs and trusts the registry's key, like
  `omarchy-keyring` does for Omarchy's.
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
- 2026-11-08: `packaging/subarchy-keyring` (issue #64) ships the registry's
  key as the `subarchy` pacman keyring with full trust; its install script
  and the installer run `pacman-key --populate subarchy`, so a system is
  ready for `SigLevel = Required` on the `[subarchy]` repository the moment
  packages are published there (#67).
- 2026-11-13: the app list's AUR apps joined `packaging/aur/`, pinned and
  built in a clean container: `cliamp`, `localsend-bin`, `voxtype-bin`,
  `ttfx`, `proton-mail-bin`, `proton-pass-cli`, `proton-authenticator-bin`
  and `proton-drive-cli-bin`. The install lists name them, so new installs
  get them. `claude-code` and `proton-pass-bin` are over the registry's
  100 MB upload limit and are added after their files are uploaded through
  the origin ([[package-publishing|Package publishing]]); `proton-pass-bin`
  followed once its file was in both channels.

Related: [[decision-map|Decision map]] · [[0026-update-model|ADR 0026]] · [[0027-third-party-software|ADR 0027]]
