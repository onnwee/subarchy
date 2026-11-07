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

Related: [[decision-map|Decision map]] · [[0031-session-manager|ADR 0031]] · [[0033-portals|ADR 0033]]
