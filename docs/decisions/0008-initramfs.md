---
title: "ADR 0008: Initramfs and kernel images"
type: decision
status: accepted
adr: 8
created: 2026-11-06
updated: 2026-11-06
tags: [decision, adr, boot]
aliases: [ADR 0008, B2, Initramfs]
---

# ADR 0008: Initramfs and kernel images

Decision map item B2. Accepted 2026-11-06.

## Decision

- **mkinitcpio** with **systemd-based hooks**: `systemd`, `sd-vconsole`,
  `sd-encrypt` instead of `udev`, `keymap`/`consolefont` and `encrypt`.
- Each kernel is packed into a **unified kernel image** (UKI): kernel,
  initramfs, microcode and command line in one EFI file, which Limine boots
  and Secure Boot (B6) can sign.
- Starting hook line, to verify when implementing:
  `base systemd plymouth autodetect microcode modconf kms keyboard sd-vconsole block sd-encrypt filesystems fsck`.

## Options considered

| Option | Why not chosen |
|---|---|
| Busybox hooks (Omarchy x86) | Passphrase-only unlock; `encrypt` cannot use TPM2 or FIDO2 keys. |
| dracut | Works, but Limine's install hooks expect mkinitcpio. |

## Borrowed from Omarchy

- The systemd hook line Omarchy uses for Apple Silicon
  (`/etc/mkinitcpio.conf.d/00-omarchy-hooks.conf`).
- `omarchy_hooks.conf` logic: drop `kms` only when NVIDIA drives every
  display; keep it on hybrid laptops so the integrated GPU shows the unlock
  prompt.
- The rule to bundle `/etc/vconsole.conf` only for Latin-letter keyboard
  layouts, so a passphrase stays typeable at the unlock prompt.

## Consequences

- The LUKS device is named with `rd.luks.name=` or `/etc/crypttab.initramfs`,
  not `cryptdevice=`.
- TPM2 and FIDO2 unlock become possible with `systemd-cryptenroll` (B4).
- Each UKI on `sputnik` is about 256 MB because the NVIDIA modules load early.
  On hybrid laptops the integrated GPU drives the unlock screen, so early
  NVIDIA loading may be dropped to shrink the image; test before deciding.
- `resume` for hibernation is handled by the `systemd` hook; B8 decides
  whether hibernation exists.

Related: [[decision-map|Decision map]] · [[0007-bootloader|ADR 0007]] · [[0010-disk-encryption|ADR 0010]]
