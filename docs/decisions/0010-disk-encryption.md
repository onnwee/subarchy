---
title: "ADR 0010: Disk encryption"
type: decision
status: accepted
adr: 10
created: 2026-11-06
updated: 2026-11-06
tags: [decision, adr, storage, security]
aliases: [ADR 0010, B4, Disk encryption]
---

# ADR 0010: Disk encryption

Decision map item B4. Accepted 2026-11-06.

## Decision

- Every install encrypts the root partition with **LUKS2** and unlocks it with
  a **passphrase** at boot. The installer has no option to skip encryption.
- TPM2 and FIDO2 key unlock are opt-in after install, enrolled with
  `systemd-cryptenroll`; the passphrase always remains as a recovery key slot.
- The EFI partition is not encrypted.

## Options considered

| Option | Why not chosen |
|---|---|
| Ask at install | Some installs would end up unencrypted. |
| TPM2 auto-unlock by default | Only meaningful with Secure Boot on; deferred to B6 and the opt-in. |

## Consequences

- Relies on the systemd initramfs ([[0008-initramfs|ADR 0008]]) for
  `sd-encrypt` and later key enrolment.
- Unattended reboots (for example remote updates) stop at the passphrase
  prompt until a key is enrolled.
- Recommend that TPM2 unlock is enrolled only after Secure Boot (B6) is on, so
  a changed boot chain cannot unlock the disk.
- Key derivation and cipher stay at cryptsetup's LUKS2 defaults unless a
  benchmark shows a reason to change them.

Related: [[decision-map|Decision map]] · [[0008-initramfs|ADR 0008]] · [[0009-disk-layout|ADR 0009]]
