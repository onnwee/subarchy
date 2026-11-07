---
title: "ADR 0054: Lightweight and battery-first defaults"
type: decision
status: accepted
adr: 54
created: 2026-11-06
updated: 2026-11-06
tags: [decision, adr, principle, power]
aliases: [ADR 0054, Design principle, Battery first]
---

# ADR 0054: Lightweight and battery-first defaults

A cross-cutting principle, not a decision map item. Accepted 2026-11-06.

## Decision

Subarchy is **laptop-first**:

1. **Lightweight by default.** Install, memory and background activity are
   kept small. Anything heavy is on demand, not preinstalled or running.
2. **Battery efficiency by default.** On battery, defaults favour low power:
   no avoidable wakeups, timers, polling, animation or GPU use.
3. **No degradation as a desktop.** On AC or a desktop machine, nothing is
   slower or missing; the power-saving defaults relax automatically on AC
   ([[0021-power|ADR 0021]]), and the user can turn any of them off.

When an earlier decision conflicts with this, this principle wins unless the
owner keeps the earlier choice explicitly.

## How it is applied

- New features must state their idle cost: resident memory, wakeups per
  second on battery, and background services they add.
- Event-driven over polling: `sputnik`'s power switcher and dock watcher poll
  every few seconds and are rewritten to react to events.
- Background services run only when needed: socket activation, timers or
  session binding ([[0031-session-manager|ADR 0031]]).
- Visual effects (blur, shadows, animations, video wallpaper) are reduced or
  off on battery.
- CI tracks budgets for idle memory and package count; targets are set after
  the first measurement.

## Baseline on `sputnik` (2026-11-06, Omarchy 4.5, on AC)

- The Quickshell shell process used about 390 MB resident memory, with 86
  user plugin directories installed.
- 708 processes were running in the owner's full working session (browsers,
  T3 Code, agents), so this is not an idle baseline.
- Battery discharge could not be measured: the machine was on AC.

An idle, on-battery baseline (power draw from `upower` and `powertop`, idle
memory, wakeups) is the first measurement to take, on Omarchy now and on
Subarchy later.

## Earlier decisions rechecked (2026-11-06)

| Decision | Outcome |
|---|---|
| [[0006-gpu-drivers\|ADR 0006]] 32-bit graphics libraries | Now on demand with gaming apps |
| [[0044-default-apps\|ADR 0044]] app set | Now a lean core; the full list is the installer's catalogue |
| [[0038-wallpaper\|ADR 0038]] wallpaper | Still image by default; video opt-in, paused on battery |
| [[0040-terminal\|ADR 0040]] terminals | kitty only; WezTerm offered in the installer |
| [[0043-file-manager\|ADR 0043]] Dolphin | Kept; its KDE Frameworks cost counts against the budget |
| [[0004-kernel\|ADR 0004]] `linux-zen` | Kept; measure power against stock `linux` once a baseline exists |

The rice features kept under this principle are in
[[rice-port-review|the rice port review]].

Related: [[decision-map|Decision map]] · [[0021-power|ADR 0021]] · [[rice-port-review|Rice port review]]
