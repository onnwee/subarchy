---
title: "ADR 0015: Init and service manager"
type: decision
status: accepted
adr: 15
created: 2026-11-06
updated: 2026-11-06
tags: [decision, adr, system]
aliases: [ADR 0015, S1, Init system]
---

# ADR 0015: Init and service manager

Decision map item S1. Accepted 2026-11-06 as implied by earlier decisions; the
owner did not object.

## Decision

**systemd** is the init system and service manager, including
`systemd-resolved`, `systemd-cryptenroll`, user services and timers.

## Why there is no real alternative

- Arch Linux ([[0002-base-distribution|ADR 0002]]) ships only systemd.
- The initramfs uses systemd hooks ([[0008-initramfs|ADR 0008]]).
- TPM2 and FIDO2 unlock ([[0010-disk-encryption|ADR 0010]]) use
  `systemd-cryptenroll`.

## Consequences

Subcarchy services ship as systemd units (system and user), and scheduled jobs
use systemd timers rather than cron.

Related: [[decision-map|Decision map]] · [[0008-initramfs|ADR 0008]]
