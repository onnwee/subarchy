---
title: "ADR 0034: Shell toolkit"
type: decision
status: accepted
adr: 34
created: 2026-11-06
updated: 2026-11-06
tags: [decision, adr, shell]
aliases: [ADR 0034, D1, Quickshell]
---

# ADR 0034: Shell toolkit

Decision map item D1. Accepted 2026-11-06.

## Decision

The desktop shell is a **Quickshell** program written in **QML** (Qt 6).

## Options considered

| Option | Why not chosen |
|---|---|
| AGS / Astal (TypeScript, GTK4) | Nothing from Omarchy's shell or the owner's QML plugins carries over. |
| Separate tools (Waybar, launcher, mako, hyprlock) | No unified look, panels or plugin system. |

## Consequences

- One QML component and theme library can serve the shell and the SDDM theme
  ([[0030-login-manager|ADR 0030]]).
- The owner's QML work is reusable: `omarchy-monitor-bar`, Shelfish, the
  Super Productivity plugin, and the SUBCULT rice's 38 plugins.
- Omarchy's shell (`shell/`: `Commons/`, `Ui/`, `services/`, 32 plugins) is
  MIT-licensed QML and can be copied piece by piece, but its plugin API is not
  kept ([[0035-plugin-api|ADR 0035]]).
- Qt version changes can break the shell (as Chatterino's Qt 6.12 mismatch did
  on `sputnik`); Qt upgrades go through the staged channel.

Related: [[decision-map|Decision map]] · [[0035-plugin-api|ADR 0035]] · [[0036-shell-components|ADR 0036]]
