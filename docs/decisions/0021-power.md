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

Related: [[decision-map|Decision map]] · [[0014-swap-hibernation|ADR 0014]]
