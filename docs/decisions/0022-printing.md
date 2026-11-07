---
title: "ADR 0022: Printing and device discovery"
type: decision
status: accepted
adr: 22
created: 2026-11-06
updated: 2026-11-06
tags: [decision, adr, system]
aliases: [ADR 0022, S8, Printing]
---

# ADR 0022: Printing and device discovery

Decision map item S8. Accepted 2026-11-06.

## Decision

- **CUPS** on every install, **socket-activated**: `cups.socket` enabled,
  `cups.service` starts only when a job or query arrives.
- **cups-browsed** and **Avahi** so driverless IPP printers on the network
  appear without drivers.
- Avahi also serves `.local` names ([[0020-dns|ADR 0020]]).

## Options considered

| Option | Why not chosen |
|---|---|
| Install printing on demand | A first print would need a setup step. |

## Borrowed from Omarchy

The package set (`cups`, `cups-filters`, `cups-pk-helper`,
`system-config-printer`) and `etc-overrides/cups-*.conf`, applied once at
install rather than on every update.

## Consequences

`sputnik` enables `cups.service` directly; Subarchy switches it to socket
activation.

Related: [[decision-map|Decision map]] · [[0020-dns|ADR 0020]]
