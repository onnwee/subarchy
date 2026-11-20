---
title: "ADR 0049: Installer and install image"
type: decision
status: accepted
adr: 49
created: 2026-11-06
updated: 2026-11-20
tags: [decision, adr, delivery]
aliases: [ADR 0049, R2, Installer, ISO]
---

# ADR 0049: Installer and install image

Decision map item R2. Accepted 2026-11-06.

## Decision

- A **Subarchy live ISO**, built with **archiso** in CI.
- A **terminal (TUI) installer** on the ISO: keyboard, disk, LUKS passphrase,
  user, hostname and time zone, then the scripted install of everything the
  decisions above define.
- The ISO carries a **package cache** for the base and default apps, so an
  install works offline; with network it can fetch newer packages from the
  stable channel.

## Options considered

| Option | Why not chosen |
|---|---|
| Arch ISO plus an install script | First boot looks like Arch, and it needs network. |
| Calamares graphical installer | Heavy to build and theme; the disk, LUKS and btrfs choices must be encoded in its modules. |

## Borrowed from Omarchy

- `omacom/omarchy-iso` (MIT, active on 2026-11-06): the ISO builder and its
  offline mirror built from the package lists.
- `install/provisioning/setup-form.sh`: the questions asked and the rules
  their answers are checked against, shared by the ISO and first-boot setup.
- `install/` scripts for the post-partition steps.

## Consequences

- The installer creates the layout from [[0009-disk-layout|ADR 0009]],
  encryption from [[0010-disk-encryption|ADR 0010]], the systemd UKIs from
  [[0008-initramfs|ADR 0008]], Limine from [[0007-bootloader|ADR 0007]] and
  the snapper config from [[0011-snapshots|ADR 0011]].
- Hardware detection ([[0005-firmware|ADR 0005]],
  [[0006-gpu-drivers|ADR 0006]], [[0050-hardware-support|ADR 0050]]) runs in
  the installer.
- The CI boot test ([[0026-update-model|ADR 0026]]) uses the same ISO in a
  VM.
- The installer asks which disk to use and leaves every other disk untouched.
  On a machine with another OS on a second disk it creates its own EFI
  partition on the target disk, adds its own firmware boot entry, and can
  add a Limine entry that chainloads the other disk's bootloader.
  The first install is `sputnik`'s empty second drive: `nvme0n1`, a 931.5 GB
  SPCC SSD with a blank GPT and no partitions (2026-11-07). Omarchy stays on
  `nvme1n1` (Crucial P5) as the fallback; its Limine firmware entry is
  `Boot0002`.
- The installer takes an `@factory` btrfs snapshot of the finished install,
  kept outside snapper's rotation, and supports a first-boot owner setup, so
  factory reset works ([[0056-quality-of-life|ADR 0056]]). Borrowed from
  Omarchy's `omarchy-system-factory-reset` and
  `install/provisioning/` (owner setup, LUKS re-key).
- ISO size grows with the full default app set
  ([[0044-default-apps|ADR 0044]]).

## Progress

- 2026-11-07: the live ISO builds with archiso (`make iso`) and boots in QEMU
  (`make iso-test`). The scripted installer `install/subarchy-install`
  installs the base system into a VM disk: LUKS2, btrfs subvolumes, UKIs for
  both kernels, Limine, snapper, zram and NetworkManager. The disk boots,
  takes the passphrase on the serial console and reaches `running`
  (`make install-test`). Still to come: the TUI, snapshot boot entries,
  Plymouth, the desktop and the offline package cache.
- 2026-11-07, later: snapshot entries, Plymouth and the desktop session
  landed. `subarchy-setup` asks the questions with plain line prompts instead
  of a full-screen TUI, so it works on any console including serial; the VM
  test drives it end to end with `--guided`. The image carries Subarchy's own
  packages in `/opt/subarchy/repo`; Arch packages still come from the
  network, so the offline cache is still open.
- 2026-11-08: the offline cache (issue #77). `make iso` downloads the whole
  install set, the install lists plus every hardware package `subcult hw
  packages --all` can pick, with dependencies, into the same repository the
  image carries at `/opt/subarchy/repo`. The installer probes one Arch
  mirror: reachable, the mirrors come first in its pacman.conf so newer
  packages win and the image's repository serves as a package cache;
  unreachable (or `OFFLINE=1`), the repository alone serves the install.
  `make install-test-offline` runs the guided install in a VM with no
  network device.
- 2026-11-11: first step towards Omarchy's installer flow (issue #124). The
  installer starts by itself on the first console, shows the partitions on
  each disk and can open one read-only, uses the password as the disk
  passphrase unless asked otherwise, confirms with yes/no, and ends with
  the install time and a reboot offer or, on failure, a menu. Still plain
  line prompts, so the serial console keeps working.
- 2026-11-11, later: on a virtual console the questions are full screens
  drawn with `gum` (greeter, pick lists, summary table, Escape to go back),
  with the SUBCULT palette and a Terminus console font. Serial consoles
  keep the line prompts. The VM install test now installs through the
  screens: keys go in through QMP and the console text is read from
  `/dev/vcs`. While the install runs, a bar with a percentage, the phase
  and a rotating tip replace the raw output, which stays in the log. A
  language screen sets the installed system's locale; the installer's own
  text stays English.
- 2026-11-12: after the first install on real hardware. The bar names
  pacman's checks before the first package unpacks, and counts pacman's
  hooks after the last one ("Setting up packages (n of m)"), where the
  DKMS modules and kernel images are built; the configuring phase starts
  at 90%. The log window drops terminal escape sequences and marks a cut
  line with an ellipsis. The time zone and computer name come under the
  machine heading, the time zone list holds tzdata's zone.tab and
  zone1970.tab names (no US/Central-style aliases) and matches typed text
  as a substring, and the summary shows each secret as "set (hidden)".
  Before a reboot or power-off the installer restores the console's
  palette and lowers the kernel's console log level.
- 2026-11-12: before the read-only browse opens, a page lists the
  partitions it opened, the ones it left closed and why, and how to come
  back: q, or Esc then 0, since F10 is a media key on many laptops. `mc`
  opens both panels on the disk and runs with no subshell and no command
  line, and the disk is mounted `noexec`, so typed text and Return on a
  file do not run anything. Its pull-down menus can still run a command
  typed into their dialogs.
- 2026-11-13: more of issue #124. The disk list puts internal disks
  before USB and removable ones. The time zone list opens on the zone of
  the network's location when the live system is online (ipapi.co or
  ipwho.is, two of the services tzupdate asks, per
  [[0024-time-locale-input|ADR 0024]]), else on the chosen language's
  zone, else UTC. A failed install says why it stopped and at which
  step, from its own log, instead of "exit status 1". Still open:
  installing into free space beside another system, which changes the
  whole-disk layout of [[0009-disk-layout|ADR 0009]].
- 2026-11-12: a network page (review finding network-possibly-down: the
  first install, on a laptop with no Ethernet port, came up offline
  because the installer had no network step). With no link up and a Wi-Fi
  device in iwd, the page after the keyboard lists the Wi-Fi networks,
  joins one with a passphrase typed as a hidden input, or skips to an
  offline install. The Wi-Fi network the live session is on when the
  questions end, joined there or by hand with `iwctl`, becomes a
  NetworkManager connection on the installed system
  ([[0016-networking|ADR 0016]]), so the first boot is online. The
  passphrase reaches `subarchy-install` in a mode-600 file, as the
  other secrets do, and is never shown or logged. The VM test can only
  check that a VM without Wi-Fi skips the page; joining a real network is
  untested on hardware. After review, network names that start with `-`
  go to gum and `iwctl` after `--` (both had read such a name as an
  option and failed), names with control characters are not listed, the
  page refuses the 64-digit key that iwd will not join with, iwd's escaped
  saved passphrase is unescaped, and the connection file's name never
  starts with a dot.
- 2026-11-13: issue #77 above (the offline cache) is Gitea #77, now
  GitHub #53; it was written before GitHub became the source
  ([[vault-conventions#Links]]).

- 2026-11-16: reconciled every original #124 item and its November 13
  checklist against main `16475c8`, including merged PR #155 (`a41c936`).
  Under the owner's delegated scope decision, the first release keeps the
  whole-disk layout of [[0009-disk-layout|ADR 0009]] and mandatory LUKS2
  encryption of [[0010-disk-encryption|ADR 0010]]. Same-disk alongside
  installation is deferred beyond that release, with the required layout,
  EFI/free-space and preservation-test decisions in
  [[guided-installer-scope|the acceptance matrix]]. The visible 2-second
  boot menu with its speech entry, visible live-boot progress, and the
  owner's mark above the install progress bar remain the chosen behavior
  (#127, #131, #144); a hidden menu and a traced icon are not pending work.
  This is a documentation/scope reconciliation, with no installer or image
  behavior change. Earlier VM and hardware observations retain their dates;
  the three post-#155 field checks remain unobserved here. No ISO build,
  VM run or device change was performed for this reconciliation.

- 2026-11-20: two images from one profile (#329, the owner's choice of
  option 3 that day). The **full** image is the image above, unchanged:
  the whole install set in `/opt/subarchy/repo`, installing with no
  network. **The offline installer stays in the builds.** The **net**
  image leaves out that repository, which made up 4.8 GiB of the
  7,099,686,912-byte image of 2026-11-16, so it should be about 1.6 GB
  (an estimate from those parts, not a measured build). It installs from
  the stable channel: Subarchy's registry and the Arch Linux Archive at the
  shipped snapshot date ([[0026-update-model|ADR 0026]]). Its network page
  says the install needs the internet, and `subarchy-install` stops before
  touching the disk when the archive or the registry does not answer. CI tests `net` on every main
  push and `full` on release tags and runs started by hand, because both on
  every push would hold the single KVM slot for about 100 minutes
  ([[ci-runner|KVM CI runner]]). Written with the change: neither image
  had been built or installed from at that point. The first main run gives
  the net image's measured size.
- 2026-11-20, later: an online install from the full image no longer takes
  Arch packages from the rolling mirrors (review finding of that day). The
  2026-11-08 note above had the mirrors win so newer packages won; that
  predates the archive-pinned stable channel ([[0026-update-model|ADR
  0026]]), and the installer then set the new system to an older snapshot
  than the packages it had installed. Both images now read the snapshot
  date before the disk is touched, probe the Arch Linux Archive at that
  date, and install Arch's packages from it; the full image's repository
  stays a cache and, offline or when that install fails, the only source.
  Checked with `tools/test/installer-check-test.sh` only: the full image's
  online path has not run in a VM or on hardware, since CI's full job
  installs with the network off.

Related: [[decision-map|Decision map]] · [[0050-hardware-support|ADR 0050]]
