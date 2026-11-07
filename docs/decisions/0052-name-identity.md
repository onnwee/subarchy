---
title: "ADR 0052: Name and identity"
type: decision
status: accepted
adr: 52
review: pending
created: 2026-11-06
updated: 2026-11-06
tags: [decision, adr, brand]
aliases: [ADR 0052, R4, Name, os-release]
---

# ADR 0052: Name and identity

Decision map item R4. Accepted 2026-11-06 in part; the name is pending.

## Decision

- **The product name is not chosen yet.** "Subcarchy" stays the working name
  for the repository and documents only. No artwork, package name, path or
  `os-release` value uses it.
- Until the name exists, specs and code use the placeholder **`<name>`**
  (paths like `/usr/share/<name>/`, commands like `<name> theme set`).
- **CLI**: the full product name is installed as the dispatcher
  ([[0046-distribution-cli|ADR 0046]]), plus a **short alias** of two to four
  letters for daily use. `sc`, `sub` and `subc` were free on `sputnik`
  (2026-11-06); recheck against Arch and AUR package names when choosing.

## Checks for the name

From [[brand-identity|Brand identity]]:

- It must not suggest an official Omarchy product.
- It must not collide with **Subcult OS**, the existing event-operations
  product in `subculture-collective/subcult-os`.
- It should fit the SUBCULT sub-brand map's commitments: legibility, agency,
  memory and anti-extraction.
- It needs a lowercase `ID=` for `os-release` and must work as a package
  prefix and a command.

## Consequences

Branding work waits for the name: Plymouth splash
([[0013-boot-splash|ADR 0013]]), SDDM theme ([[0030-login-manager|ADR 0030]]),
Limine strings ([[0007-bootloader|ADR 0007]]), the editor branding layer
([[0045-editor|ADR 0045]]) and every row in
[[branding-surfaces|Branding surfaces]].

Related: [[decision-map|Decision map]] · [[brand-identity|Brand identity]] · [[0053-licence|ADR 0053]]
