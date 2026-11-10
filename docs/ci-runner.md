---
title: "KVM CI runner"
type: guide
status: active
created: 2026-11-08
updated: 2026-11-09
tags: [guide, ci, delivery]
---

# KVM CI runner

Subarchy's dedicated runner lives on Kvant under `/opt/subarchy-kvm-runner`.
It is registered only for `subculture-collective/subarchy`, with the label
`subarchy-kvm`. The existing shared runner is independent.

`tools/ci/compose.yaml` and `tools/ci/runner-config.yaml` are the deployed
configuration. The daemon uses the pinned act_runner image, one CPU and
1 GiB RAM. It admits one job at a time. Job containers are privileged, have
`/dev/kvm`, and are limited to four CPUs, 8 GiB RAM without swap, and 1,024
processes. The Docker socket is available to the daemon; the runner does
not mount it into jobs. Actions caching is disabled.

The label uses an Arch container. `.gitea/workflows/kvm.yml` checks at least
60 GB free on its filesystem, then starts QEMU with `-enable-kvm` and
requires the monitor to report `kvm support: enabled`. This is a runner
capability check. `.gitea/workflows/iso.yml` builds the live ISO and boots
it on this runner (#60); the installed-system test is a separate job (#68).

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
