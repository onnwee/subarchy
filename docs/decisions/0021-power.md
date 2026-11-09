---
title: "ADR 0021: Power and thermal management"
type: decision
status: accepted
adr: 21
created: 2026-11-06
updated: 2026-11-06
tags: [decision, adr, system, power]
aliases: [ADR 0021, S7, Power]
---

# ADR 0021: Power and thermal management

Decision map item S7. Accepted 2026-11-06.

## Decision

- **power-profiles-daemon** from Arch (`power-profiles-daemon`), not Omarchy's
  patched `omarchy-power-profiles-daemon`, whose extra profiles target NVIDIA
  RTX Spark and Snapdragon X, both aarch64 ([[0003-cpu-architectures|ADR 0003]]).
- **Automatic profile by power source**: `balanced` on AC, `power-saver` on
  battery. A profile the user picks by hand wins until the power source
  changes again.
- **thermald** on Intel CPUs.
- **Vendor backends** (for example Dell firmware power and charge profiles)
  are optional add-ons installed by hardware detection (R3).

## Options considered

| Option | Why not chosen |
|---|---|
| TLP | Conflicts with power-profiles-daemon, so profile switchers need rework. |
| tuned with tuned-ppd | Less common on Arch. |

## Borrowed

- `sputnik-power-profile` and `sputnik-power-profile-watch` from the owner's
  `~/.local/bin`: AC detection through `/sys/class/power_supply` and
  `powerprofilesctl`. The hook into `subcult-motion` becomes a theme or motion
  setting (D5).
- `omarchy-dell-power-profiles` as the model for vendor add-ons.

## Consequences

- The automatic switch runs as a user service or udev-triggered unit; the
  `sputnik` version polls, which should become event-driven.
- Charge thresholds are vendor-specific and belong to the vendor add-ons.

## Progress

- 2026-11-07: power-profiles-daemon is installed and enabled, thermald on
  Intel CPUs. `subcult power auto` (`bin/subcult-power-auto`) sets `balanced`
  on AC and `power-saver` on battery, at boot (`subcult-power-auto.service`)
  and when the power source changes (udev rule), so a hand-picked profile
  holds until the next change. Machines without a system battery are left
  alone. `tools/test/power-auto-test.sh` covers the detection; the VM has no
  battery, so switching itself is untested.
- 2026-11-08: thermal alerts (rice port, issue #98). Quickshell's UPower has
  no temperature and sysfs has no inotify for one, so the alert source is
  the kernel's thermal generic-netlink events: `subcult thermal watch`
  (`internal/thermal`, on `golang.org/x/sys/unix`, no new dependency)
  subscribes to the `event` group and prints each `hot` or `critical` trip
  crossed; the shell alerts once per excursion with a cooldown per zone.
  No event can be provoked without touching the kernel's trip points, so
  the live tests stop at resolving the family; parsing is covered with
  built messages.

- 2026-11-08: the Dell add-on (issue #91). `subcult dell power`
  (`bin/subcult-dell-power`) reads and sets the firmware's platform profile
  (quiet, cool, balanced, performance; the daemon's power-saver, balanced or
  performance goes with it) and the dell-wmi-sysman charging mode (adaptive,
  standard, express, primarily AC, custom with start and stop thresholds,
  checked against the firmware's range, step and five-point gap). A udev
  rule and a short oneshot service hand those sysfs files to wheel, so the
  bar writes them as the user; no sudo rule. The `dell-power` widget and
  panel ship off: `subcult hw apply` enables them on a machine with the
  dell-pc platform profile through the machine layer of the bar config
  (`/etc/subcult/shell/bar.json`, [[0048-config-ownership|ADR 0048]]). The
  state is read when the widget appears, when the panel opens and after a
  change; nothing polls. Tested against a fake sysfs tree
  (`tools/test/dell-power-test.sh` and the headless shell check); no Dell
  was at hand.

Related: [[decision-map|Decision map]] · [[0014-swap-hibernation|ADR 0014]]
