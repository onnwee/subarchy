---
title: "ADR 0012: Secure Boot"
type: decision
status: accepted
adr: 12
created: 2026-11-06
updated: 2026-11-06
tags: [decision, adr, boot, security]
aliases: [ADR 0012, B6, Secure Boot]
---

# ADR 0012: Secure Boot

Decision map item B6. Accepted 2026-11-06.

## Decision

- Secure Boot is **opt-in**. Installs boot with it off, as `sputnik` does now.
- Subarchy ships **sbctl** and one setup command that, with the firmware in
  setup mode, creates and enrolls the machine's own keys, keeps Microsoft's
  keys enrolled for GPU and network option ROMs, signs Limine and the UKIs,
  and enrolls Limine's config hash.
- After setup, kernel and bootloader updates are signed automatically.
- TPM2 disk unlock ([[0010-disk-encryption|ADR 0010]]) is offered only once
  Secure Boot is on.

## Options considered

| Option | Why not chosen |
|---|---|
| On by default at install | Firmware setup-mode steps differ by vendor and would make installs fail on some machines. |
| Not supported | Leaves TPM2 unlock unsafe to offer. |

## Consequences

- Signing must hook into every path that writes a UKI or Limine binary:
  kernel updates, DKMS rebuilds, snapshot entries.
- A firmware reset can drop the custom keys; the machine then refuses to boot
  signed images until keys are re-enrolled or Secure Boot is turned off.
  Document the recovery.
- Omarchy has no Secure Boot support to borrow; this is new work.

Related: [[decision-map|Decision map]] · [[0007-bootloader|ADR 0007]] · [[0010-disk-encryption|ADR 0010]]
