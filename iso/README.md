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
  gets the kernel's errors and its own root login, which the tests drive;
- build a smaller initramfs (#330): no `archiso_pxe_*` hooks, and
  `subarchy_kms` (`airootfs/etc/initcpio/install/`) in place of `kms`, which
  leaves out nouveau and radeon. The image holds no `autodetect` hook, so
  it carries every storage and filesystem driver by design.

The installer, `subarchy-setup`, starts by itself on the first console
(`airootfs/root/.zlogin`). That console's autologin prints no banner, and
`.zlogin` turns systemd's status lines off and clears the boot messages and
the motd first, so the installer is the first thing on the screen after
boot and units still starting do not print over it.

## Two images

One profile builds two images (#329; owner's decision 2026-11-20):

- **full**, `subarchy-full-<date>-x86_64.iso`: carries Subarchy's own
  packages and the whole install set in `/opt/subarchy/repo`, so it installs
  with no network (`OFFLINE=1`, or no mirror answering), as every image did
  before. It stays in the builds.
- **net**, `subarchy-net-<date>-x86_64.iso`: the same live system without
  `/opt/subarchy/repo`. `subarchy-setup` then points the install at the
  stable channel's registry, and `subarchy-install` takes Arch packages from
  the Arch Linux Archive at the snapshot date the `subarchy` package ships
  (ADR 0026). The network page says the install needs the internet. If the
  archive or the registry does not answer, the installer stops before it
  touches the disk and says which one.

Both live images carry `subarchy-keyring`, so the live system trusts the
registry's key and the net install can require signed packages.

The net image's size is not measured yet. From the parts of the
2026-11-16 image measured on 2026-11-20 (#329: 4.8 GiB of offline
repository in a 7,099,686,912-byte image), it should be about 1.6 GB,
under GitHub's 2 GiB per-file limit. The first build on main will give the
real number.

## Build and test

Needs `archiso`, `qemu-base` and `edk2-ovmf`, and sudo for `mkarchiso`.

```bash
make iso                    # tools/iso/build.sh: package -> local repo (+ the install set, downloaded) -> mkarchiso, once per image -> build/iso/
make iso ISO_EDITIONS=net   # one image only
make iso-test               # tools/iso/boot-test.py: UEFI boot in QEMU (ISO_EDITION=net for the net image)
make install-test-offline   # the full image, guided, network off
make install-test-net       # the net image, guided, online
```

The boot test passes when the image reaches a root shell, `/etc/os-release`
says Subarchy, the kernel is `linux-zen`, systemd reports `running` or
`degraded`, and the screen is `/dev/console`. The systemd greeting now
shows on the screen, not the serial log, so the test no longer times it.
The first passing run (2026-11-07, `sputnik` with KVM): systemd
greeting after 12 s, shell after 34 s, state `running`, no failed units.
The image was 1.6 GB then.

CI builds and boots the images in `.gitea/workflows/iso.yml` on the
`subarchy-kvm` runner, whose job containers are privileged and have
`/dev/kvm` ([KVM CI runner](../docs/ci-runner.md)). On every push to
`main`, `net` runs as the `iso-net` job of `.gitea/workflows/packages.yml`,
after that commit's packages are published (since 2026-11-20). `iso.yml`
runs `net` and `full` on release tags (`v*`) and on demand
(`workflow_dispatch`). Running both on every
push would hold the runner's one slot for about 100 minutes: one full run
took 47 to 53 minutes on 2026-11-16. Pull requests are turned off on Gitea and
are verified on GitHub (`.github/workflows/mirror-ci.yml`), which has no ISO
or VM job ([ADR 0051](../docs/decisions/0051-hosting-ci.md)). Every branch is
mirrored to Gitea, so a change to the image or the test harness can run
before it merges: start the workflow by hand on that branch.
`tools/ci/build-iso.sh full|net` builds the core package from the
checkout, takes the pinned rebuilds from the signed stable registry and,
for `full`, the install set from Subarchy's Arch snapshot, then runs
`make iso` for that one image, prints its size and SHA-256 (and writes the
sum beside it as `<image>.sha256`), and runs the boot test.
`tools/ci/install-test.sh full|net` then installs from that image into a
VM disk and runs every check of `tools/iso/install-test.py` (#68). For
`full` it is the guided, offline install, so the result comes from the
image's own setup command, installer and repository. For `net` it is the
guided install online: Arch packages from the snapshot archive, and
Subarchy's own from the checkout's `build/repo` (`--repo`), so the
installed system is this commit's rather than whatever the registry holds
when the job runs. A failed check fails the job; the serial logs,
screendumps and sums are kept in the `iso-logs-net` or `iso-logs-full`
artifact either way. A run started by hand keeps each image and its sum as
`subarchy-iso-net` and `subarchy-iso-full` for 2 days. Other runs do not:
the full image's upload held the runner's only job slot for 45 minutes.
