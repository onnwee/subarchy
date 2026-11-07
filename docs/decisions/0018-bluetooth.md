---
title: "ADR 0018: Bluetooth"
type: decision
status: accepted
adr: 18
created: 2026-11-06
updated: 2026-11-06
tags: [decision, adr, system]
aliases: [ADR 0018, S5, Bluetooth]
---

# ADR 0018: Bluetooth

Decision map item S5. Accepted 2026-11-06 as the only Linux Bluetooth stack;
the owner did not object.

## Decision

**BlueZ** (`bluez`, `bluez-utils`), with audio through PipeWire
([[0017-audio|ADR 0017]]).

## Consequences

The Bluetooth panel (D3) talks to BlueZ over D-Bus. Omarchy's
`install/hardware/bluetooth.sh` is the starting point.

Related: [[decision-map|Decision map]] · [[0017-audio|ADR 0017]]
