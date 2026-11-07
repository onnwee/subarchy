---
title: "ADR 0064: Virtual machines"
type: decision
status: accepted
adr: 64
created: 2026-11-07
updated: 2026-11-07
tags: [decision, adr, apps]
aliases: [ADR 0064, VMs, libvirt]
---

# ADR 0064: Virtual machines

Accepted 2026-11-07.

## Decision

- Virtual machines work out of the box: **QEMU/KVM**, **libvirt** and
  **virt-manager** are preinstalled, with UEFI firmware (`edk2-ovmf`), TPM
  emulation (`swtpm`) and default NAT networking.
- **No VM images** ship.
- `libvirtd` is socket-activated, so it does not run until a VM is used
  ([[0054-lightweight-battery-first|ADR 0054]]).
- The user reaches system VMs through libvirt's polkit rule rather than the
  `libvirt` group.

## Consequences

- KVM needs CPU virtualisation enabled in firmware; the hardware check warns
  when it is off.
- libvirt's NAT network adds its own firewall rules alongside ufw; test both
  together.
- The same QEMU stack runs Subarchy's own ISO boot tests
  ([[0049-installer|ADR 0049]]).

Related: [[decision-map|Decision map]] · [[0055-containers|ADR 0055]]
