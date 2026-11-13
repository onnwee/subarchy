---
title: "KVM CI runner"
type: guide
status: active
created: 2026-11-08
updated: 2026-11-10
tags: [guide, ci, delivery]
---

# KVM CI runner

Subarchy's dedicated runner lives on Kvant under `/opt/subarchy-kvm-runner`.
It is registered only for `subculture-collective/subarchy`, with the label
`subarchy-kvm`. The existing shared runner is independent.

`tools/ci/compose.yaml` and `tools/ci/runner-config.yaml` are the deployed
configuration. The daemon uses the pinned act_runner image, one CPU and
1 GiB RAM. It admits one job at a time. Job containers are privileged, have
`/dev/kvm`, and are limited to four CPUs, 8 GiB RAM without swap, and 4,096
processes. The Docker socket is available to the daemon; the runner does
not mount it into jobs. Actions caching is disabled.

The process limit was 1,024 until November 10, 2026, which the ISO build
exceeded. `mkarchiso` installs the live image with `pacstrap`, and
`pacstrap` runs pacman as PID 1 of a new PID namespace. Each signature
check starts two `gpg` helpers that are reparented to pacman, which does
not reap them, so they remain as zombies until pacman exits: 943 of them
for 470 packages in a test container. The image's 595 packages need about
1,250 processes. Under the old limit the last 112 packages failed with
`GPGME error: Inappropriate ioctl for device` and `missing required
signature`, which reads like a keyring fault and is not one.

The label uses an Arch container. `.gitea/workflows/iso.yml` checks at
least 60 GB free on its filesystem, builds the live ISO and boots it on this
runner with KVM (#60), then installs from it into a VM disk and checks the
installed system (#68). One such run takes about 40 minutes. A separate KVM
smoke workflow ran on every main push until 2026-11-13; the ISO run already
needs KVM, so it was removed to free the runner's single slot.

## Operation and recovery

The root-owned `data/.runner` holds the repository registration credential.
Keep that file out of Git and backups intended for publication. Register
a replacement through the repository's Actions runner settings, using a
repository registration token through private standard input. Match the
name `subarchy-kvm-kvant` and the configured label.

From `/opt/subarchy-kvm-runner`, use `sudo docker compose ps` to inspect
the service. `sudo docker compose stop` stops this runner alone; its five
minute shutdown allowance lets an active job finish. Preserve `data/`
when replacing the daemon. Remove the repository runner registration only
when retiring it, and do not stop the shared `gitea-act-runner` service.

Privileged jobs require trusted repository writers. This runner is not
registered for other repositories or for the public GitHub mirror.

Related: [[0051-hosting-ci|Source hosting and CI]] · [[roadmap|Roadmap]]
