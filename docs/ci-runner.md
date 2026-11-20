---
title: "KVM CI runner"
type: guide
status: active
created: 2026-11-08
updated: 2026-11-20
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
installed system (#68). Since #329 it builds two images: the
network-install one on every main push, and the full offline one on
release tags and runs started by hand, because both per push would take
about 100 minutes of the single slot. A separate KVM
smoke workflow ran on every main push until 2026-11-13; the ISO run already
needs KVM, so it was removed to free the runner's single slot.

## One runner, one slot

Observed 2026-11-20 with `tea api --login subcult-agent` (read-only): the
repository has one runner, id 99, `subarchy-kvm-kvant`, label `subarchy-kvm`,
online. `runner-config.yaml` sets `capacity: 1`, so the iso and packages
workflows (and the packages publish job) run one after another. The run list
shows it: on 2026-11-16 each packages run (for example 23046) started within
a second of the ISO run for the same commit finishing. `verify.yml` uses the
shared `ubuntu-latest` runner and does not wait for this one.

**Run time.** Five successful ISO runs on main, 2026-11-16 (23045, 23065,
23085, 23103, 23108), took 47 to 53 minutes from start to finish, not the
40 minutes this note gave before. The job limit is 120 minutes. Successful
packages runs that day took 2 to 35 minutes, depending on how many packages
needed building.

**Bursts replace pending runs.** Each main-branch workflow sets a
`concurrency` group per workflow and ref (`iso-<ref>`, `packages-<ref>`,
`<workflow>-<ref>`) with `cancel-in-progress: false`. A running job is left
alone, but a group holds only one pending run, so a newer push replaces the
one that was waiting. In a merge burst only the newest commit is built and
tested; the commits in between get no ISO or package run. Such runs show as
`cancelled` with no start time and no runner. Of 79 cancelled runs counted
on #264, 76 were of this kind. The other three were cancelled by hand while
running, which this setting does not do. The ISO result for a head commit
therefore says nothing about the skipped commits before it.

**Pull requests get no ISO or VM job.** Pull requests are checked on GitHub
by `.github/workflows/mirror-ci.yml` (`make verify`, a package build and
headless shell tests, on GitHub-hosted runners). It has no ISO build, no boot and no install test.
Gitea has pull requests turned off, and `iso.yml` and `packages.yml` run
only on pushes to main and, for `iso.yml`, by hand. So a change to the image,
the packages or the install harness merges without the ISO run, and a break
shows up after the merge. To test such a change first, start `iso.yml` by
hand on the mirrored branch (`workflow_dispatch`). That uses the one slot, and
a manual run on a branch sits in the queue behind main's runs.

## Host limits and incidents

The runner, the weekly snapshot timer and the GitHub-to-Gitea mirror all run
on Kvant, which is a shared development host with 60 GiB of RAM. From
Kvant's host briefing (`~/.homelab/HOMELAB.md`, read 2026-11-20):

| Date | What happened |
|---|---|
| 2026-11-08 | Kvant hung at about 11:14 CST and was rebooted at about 11:51. Cause not established; memory was tight beforehand. |
| 2026-11-14 | A lockup; the owner rebooted at 00:14 UTC. Docker also restarted on the host that night, which ended ISO attempts running at the time (#264). |
| 2026-11-16 | Kernel logs show global out-of-memory kills of Codex and an agent-launched test during concurrent development work. |

Changes made on 2026-11-16 at 04:50 UTC: `app-t3code.slice` has a persistent
20 GiB soft memory threshold (its parent's soft threshold had been 45 GiB,
which left too little reserve; the hard limit is unchanged), and a 16 GiB
Btrfs swapfile at priority 10, behind zram, is active. About 19 GiB of RAM
was available afterwards with no further OOM kill seen. Activation at boot
and longer stability were not tested. Earlier, on 2026-11-10, a
`batch.slice` was added (system: `MemoryHigh` 8G, `MemoryMax` 10G; user:
14G and 18G); the snapshot script starts its container there.

What this means for the runner. A job container is capped at 8 GiB with no
swap, four CPUs and 4,096 processes, and the daemon at 1 GiB, so the runner
itself needs about 9 GiB, plus 60 GB of free disk for the ISO check. It
cannot stop the host from running out of memory because other workloads
share that host. A host reboot or Docker restart ends the running job; the
daemon restarts (`restart: unless-stopped`) and the run has to be rerun. A
run that ends with no failure line and a gap in the host journal is a host
event, not a Subarchy failure.

## Weekly snapshot timer

`subarchy-snapshot.timer` is a user timer on Kvant (Mondays 06:00 UTC, up
to one hour of random delay, `Persistent=true`). It runs
`tools/ci/advance-snapshot.sh`, which builds and installs a test ISO against
yesterday's Arch snapshot and, if that passes, opens a pull request that
merges itself. See
[[package-publishing#Advancing the stable snapshot|the snapshot procedure]].

**Paused since 2026-11-20 07:49 UTC.** The owner decided on #258 to keep
main on the qualified candidate `9e32591` (core `0.0.0-638`) until the first
release is tagged. It was disabled with
`systemctl --user disable --now subarchy-snapshot.timer`; the owner's readback
on #258 was `is-enabled` disabled and `is-active` inactive. The service unit
and its files are unchanged. While it is paused the stable channel stays on
Arch snapshot `2026/11/15`, and no Arch security or package updates reach
stable through this path. To resume after the tag (or earlier, if the owner
chooses to re-qualify a new head):

```bash
systemctl --user enable --now subarchy-snapshot.timer
systemctl --user list-timers subarchy-snapshot.timer   # check the next run
```

`Persistent=true` makes a run that was missed while the timer was off fire
soon after re-enabling. The run builds and installs a test ISO before it
opens anything, so the pull request comes after that, not at once. The next
Monday run would otherwise have been 2026-11-23.

## Standing up the runner and timer on another host

Not run for this note: these steps come from `tools/ci/` and the Gitea
act_runner documentation, and have not been tested on a second host. The
current runner was set up the same way on Kvant.

1. **Host.** Docker, `/dev/kvm` readable by Docker, at least 60 GB free on
   the Docker filesystem, and about 9 GiB of RAM you can spare for the
   runner. Do not share the host with unbounded workloads (see above).
2. **Files.** Copy `tools/ci/compose.yaml` and `tools/ci/runner-config.yaml`
   to `/opt/subarchy-kvm-runner/` and create `data/` there. Keep the image
   digest pinned in `compose.yaml`; change it in a pull request.
3. **Register.** Create a repository registration token in the Gitea
   repository's Actions runner settings. Read it into a shell variable
   without echoing it (`read -rs TOKEN`), then run the pinned image's
   `act_runner register --no-interactive` against `https://git.subcult.tv`
   with the name `subarchy-kvm-kvant` (or a new name), the label
   `subarchy-kvm:docker://archlinux:latest`, and its working directory set
   to `data/` so that `data/.runner` is written. Unset the variable.
4. **Start and check.** `sudo docker compose up -d`, then confirm the runner
   shows online with the label in the repository settings, or with
   `tea api --login subcult-agent /repos/subculture-collective/subarchy/actions/runners`.
5. **Retire the old runner first.** With one slot and one label, two
   runners would split jobs between hosts. Stop the old one with
   `sudo docker compose stop` and remove its registration only when the
   new one is online.
6. **Snapshot timer.** On the host that runs it, install a `gh` login that
   can push branches and open pull requests on the GitHub repository, run
   `loginctl enable-linger <user>` so the user timer runs without a login,
   make a `batch.slice` if you want the snapshot container kept off
   interactive work, and install the units as in
   [[package-publishing#Advancing the stable snapshot|the snapshot procedure]].
   Try a day first with `SUBARCHY_SNAPSHOT_DRY=1`, which pushes nothing.
   Run the timer on one host only. If main is being held (as now), install
   it disabled.
7. **Prove it.** Start `iso.yml` by hand on a branch and expect a green run
   in about 50 minutes.

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

Privileged jobs require trusted repository writers. The runner's job
containers are privileged with `/dev/kvm` and the host Docker daemon
behind them, so code that runs there can reach Kvant. Code reaches it two
ways: a push to main, and `workflow_dispatch` on any branch, which Kvant
mirrors from GitHub to Gitea. `.github/workflows/auto-merge.yml` turns on
auto-merge for every ready pull request from a branch of this repository, and
it merges once the required checks pass, with no human review in that path.
So anyone who can push a branch to the GitHub repository can get code onto
the runner by merging. Keep write access to people and agents you trust
with Kvant, use a draft or the `hold` label for changes that should wait,
and never register this runner for forks or other repositories. This runner is
not registered for other repositories or for the GitHub repository.

Related: [[0051-hosting-ci|Source hosting and CI]] · [[roadmap|Roadmap]]
