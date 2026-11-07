---
title: "ADR 0003: CPU architectures"
type: decision
status: accepted
adr: 3
created: 2026-11-06
updated: 2026-11-06
tags: [decision, adr, foundation]
aliases: [ADR 0003, F2, CPU architectures]
---

# ADR 0003: CPU architectures

Decision map item F2. Accepted 2026-11-06.

## Decision

Subcarchy supports **x86_64 only** at launch. aarch64 can be added later by a
new decision.

## Options considered

| Option | Why not chosen |
|---|---|
| x86_64 and aarch64 | Omarchy needs five extra aarch64 package lists and platform fixes for Apple Silicon, Qualcomm and NVIDIA GB10/N1X. That roughly doubles build and test work. |

## Consequences

- One package set and one test matrix. The reference machine is `sputnik`
  (Dell XPS 15 9520).
- Omarchy's `omarchy-aarch64*.packages` lists and aarch64 hardware scripts are
  not borrowed.
- Packages can be built for the generic `x86-64` level. Whether to target
  `x86-64-v3` for speed is a packaging question for P1.

Related: [[decision-map|Decision map]] · [[0002-base-distribution|ADR 0002]]
