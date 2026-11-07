# iso

The Subarchy live ISO ([ADR 0049](../docs/decisions/0049-installer.md)),
built with archiso.

`profile/` is a copy of archiso's `releng` profile, changed to:

- name the image, volume label and boot entries Subarchy;
- boot with systemd-boot on UEFI only (no BIOS, no GRUB);
- use `linux-zen` (the LTS kernel is not on the image yet);
- add the `subarchy` package from a local repository, which sets
  `/etc/os-release`;
- log root in on the serial console too, so the boot test can drive it.

The installer is not on the image yet.

## Build and test

Needs `archiso`, `qemu-base` and `edk2-ovmf`, and sudo for `mkarchiso`.

```bash
make iso        # tools/iso/build.sh: package -> local repo -> mkarchiso -> build/iso/
make iso-test   # tools/iso/boot-test.py: UEFI boot in QEMU, checks over the serial console
```

The boot test passes when the image reaches a root shell, `/etc/os-release`
says Subarchy, the kernel is `linux-zen`, and systemd reports `running` or
`degraded`. The first passing run (2026-11-07, `sputnik` with KVM): systemd
greeting after 12 s, shell after 34 s, state `running`, no failed units.
The image is 1.6 GB.

CI does not build the ISO yet: `mkarchiso` needs root and mount namespaces,
which the Gitea runners' containers do not grant.
