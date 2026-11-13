# iso

The Subarchy live ISO ([ADR 0049](../docs/decisions/0049-installer.md)),
built with archiso.

`profile/` is a copy of archiso's `releng` profile, changed to:

- name the image, volume label and boot entries Subarchy;
- boot with systemd-boot on UEFI only (no BIOS, no GRUB);
- use `linux-zen` (the LTS kernel is not on the image yet);
- add the `subarchy` package from a local repository, which sets
  `/etc/os-release`;
- log root in on the serial console too, so the boot test can drive it;
- boot with its progress on screen: the menu shows for 2 seconds (the
  speech and memory-test entries are still there), the kernel prints only
  errors, and the screen is the last `console=`, so it is `/dev/console`
  and shows the live medium's and systemd's status lines while the image
  starts. Before 2026-11-12 the serial console came last and a laptop
  showed a black screen for about 30 seconds. The serial console still
  gets the kernel's errors and its own root login, which the tests drive.

The installer, `subarchy-setup`, starts by itself on the first console
(`airootfs/root/.zlogin`). That console's autologin prints no banner, and
`.zlogin` turns systemd's status lines off and clears the boot messages and
the motd first, so the installer is the first thing on the screen after
boot and units still starting do not print over it.

## Build and test

Needs `archiso`, `qemu-base` and `edk2-ovmf`, and sudo for `mkarchiso`.

```bash
make iso        # tools/iso/build.sh: package -> local repo (+ the install set, downloaded) -> mkarchiso -> build/iso/
make iso-test   # tools/iso/boot-test.py: UEFI boot in QEMU, checks over the serial console
```

The boot test passes when the image reaches a root shell, `/etc/os-release`
says Subarchy, the kernel is `linux-zen`, systemd reports `running` or
`degraded`, and the screen is `/dev/console`. The systemd greeting now
shows on the screen, not the serial log, so the test no longer times it.
The first passing run (2026-11-07, `sputnik` with KVM): systemd
greeting after 12 s, shell after 34 s, state `running`, no failed units.
The image is 1.6 GB.

CI builds and boots the image in `.gitea/workflows/iso.yml` on the
`subarchy-kvm` runner, whose job containers are privileged and have
`/dev/kvm` ([KVM CI runner](../docs/ci-runner.md)): on `main`, on demand
(`workflow_dispatch`), and on pull requests that change the image or the
pipeline. `tools/ci/build-iso.sh` builds the core package from the checkout,
takes the pinned rebuilds from the signed stable registry and the install
set from Subarchy's Arch snapshot, then runs `make iso` and the boot test.
`tools/ci/install-test.sh` then installs from that image into a VM disk and
runs every check of `tools/iso/install-test.py` (#68): the guided, offline
install, so the result comes from the image's own setup command, installer
and repository. A failed check fails the job; the serial logs and
screendumps are kept in the `iso-logs` artifact either way.
A run started by hand keeps the image as the `subarchy-iso` artifact for
2 days. Other runs do not: the image is 4.6 GB and its upload held the
runner's only job slot for 45 minutes.
