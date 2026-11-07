---
title: "ADR 0051: Source hosting and CI"
type: decision
status: accepted
adr: 51
created: 2026-11-06
updated: 2026-11-06
tags: [decision, adr, delivery]
aliases: [ADR 0051, R6, Hosting, CI]
---

# ADR 0051: Source hosting and CI

Decision map item R6. Accepted 2026-11-06.

## Decision

- **`git.subcult.tv`** (Gitea) is the canonical home for source, issues and
  releases, with **Gitea Actions** for CI: packages
  ([[0025-package-repository|ADR 0025]]), the ISO
  ([[0049-installer|ADR 0049]]) and VM boot tests
  ([[0026-update-model|ADR 0026]]).
- A **read-only GitHub mirror** for visibility, with Actions disabled.

## Options considered

| Option | Why not chosen |
|---|---|
| GitHub primary | Hosted runners are slow for ISO builds and VM boot tests. |

## Consequences

- CI runs on the owner's runners; package builds and ISO boot tests need a
  runner with KVM and enough disk. The fleet has a Gitea runner on Kuznya
  (Machinum, 2026-10-10); its capacity for this is unchecked.
- Commits by agents use the `subcult-agent` identity.
- The SUBCULT rice already follows this pattern (Gitea canonical, GitHub
  mirror).
- This repository has no remote yet; creating it on `git.subcult.tv` is the
  first step.

Related: [[decision-map|Decision map]] · [[0025-package-repository|ADR 0025]] · [[0049-installer|ADR 0049]]
