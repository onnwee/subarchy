---
title: "ADR 0002: Base distribution"
type: decision
status: accepted
adr: 2
created: 2026-11-06
updated: 2026-11-06
tags: [decision, adr, foundation]
aliases: [ADR 0002, F1, Base distribution]
---

# ADR 0002: Base distribution

Decision map item F1. Accepted 2026-11-06.

## Decision

Subcarchy builds on **Arch Linux** with **pacman**, as a rolling release.
Packages are installed and updated on the device; the system is not shipped as
an immutable image.

## Options considered

| Option | Why not chosen |
|---|---|
| NixOS | Declarative and atomic, but almost no Omarchy code carries over. |
| Fedora Atomic / bootc | Stable image-based base; Hyprland only through third-party repositories, and Omarchy's scripts need rewriting. |
| Arch, image-based | Most control and safest updates, but the most build infrastructure to own before anything ships. |

## Borrowed from Omarchy

Omarchy is Arch-based, so its package lists, install scripts and PKGBUILD
practices can be read and copied directly.

## Consequences

- Rolling-release breakage is Subcarchy's to catch. The update model (P3) and
  snapshots (B5) carry that risk.
- The AUR is available; how much of it Subcarchy relies on is P2.
- The owner's fleet and the SUBCULT rice already run on Arch.

Related: [[decision-map|Decision map]] · [[0001-fork-strategy|ADR 0001]] · [[0003-cpu-architectures|ADR 0003]]
