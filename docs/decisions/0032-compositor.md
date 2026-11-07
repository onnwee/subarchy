---
title: "ADR 0032: Compositor"
type: decision
status: accepted
adr: 32
created: 2026-11-06
updated: 2026-11-06
tags: [decision, adr, session]
aliases: [ADR 0032, L4, Hyprland]
---

# ADR 0032: Compositor

Decision map item L4. Accepted 2026-11-06.

## Decision

**Hyprland**, configured in **Lua** (Hyprland 0.56.2 on `sputnik`,
2026-11-06). Subarchy ships defaults under its own system path and the user
overrides them in `~/.config/hypr/` (R1 decides the split).

## Options considered

| Option | Why not chosen |
|---|---|
| niri | Stable scrollable tiling, but a different window model; most existing scripts and bindings would be rewritten. |
| Sway | Very stable, but little room for the branded look. |

## Borrowed from Omarchy

`default/hypr/`: `bootstrap.lua`, `omarchy.lua`, `bindings/`, `looknfeel.lua`,
`windows.lua`, `input.lua`, `envs.lua`, `nvidia.lua`, `monitor-workspaces.lua`,
`workspace-layouts.lua`, `toggles/` and helpers. Also the owner's
`~/.config/hypr` work on `sputnik`: per-monitor workspace assignment,
topology-aware `monitors.lua`, and the dock workspace watcher.

## Consequences

- Hyprland moves fast and has broken config between releases; the staged
  stable channel ([[0026-update-model|ADR 0026]]) and CI boot test must cover
  compositor upgrades.
- Window and workspace scripts use `hyprctl` and Hyprland's IPC socket.
- The GPU session toggle ([[0006-gpu-drivers|ADR 0006]]) writes Hyprland
  environment entries.

## Progress

- 2026-11-07: Subarchy's Hyprland Lua defaults live in `default/hypr/`
  (installed to `/usr/share/subcult/default/hypr/`). The installer writes
  `~/.config/hypr/hyprland.lua`, which runs `bootstrap.lua`, loads
  `subcult.lua` and then the user's overrides (ADR 0048). Helpers are in the
  global `sub` table. The defaults so far: environment, input from
  `/etc/vconsole.conf`, gaps and borders without blur or shadows, a small
  Omarchy-derived binding set, and `dbus-update-activation-environment` at
  start. `make hypr-check` runs `Hyprland --verify-config` on them. In the VM
  test the session starts and `hyprctl` reports the defaults.

Related: [[decision-map|Decision map]] · [[0031-session-manager|ADR 0031]] · [[0033-portals|ADR 0033]]
