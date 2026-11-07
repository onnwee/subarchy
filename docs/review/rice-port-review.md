---
title: "SUBCULT rice port review"
type: review
status: active
review: done
created: 2026-11-06
updated: 2026-11-06
tags: [review, rice, shell]
aliases: [Rice port list, What to port from the rice]
---

# SUBCULT rice port review

The owner does not want the SUBCULT rice's theme in Subarchy and wants only
the useful parts ported, judged against lightweight, battery-first defaults
([[0054-lightweight-battery-first|ADR 0054]]). Decided 2026-11-06.

Every port is a rewrite through Subarchy's plugin API
([[0035-plugin-api|ADR 0035]]) and CLI ([[0046-distribution-cli|ADR 0046]]),
guided by the rice's code, docs and tests in
`~/Work/Forks/subcult-omarchy-rice`. Each must state its idle cost
(ADR 0054). The `subcult-*` command name overlap is accepted
([[0052-name-identity|ADR 0052]]).

## Port

| Feature | Rice source | Lands in |
|---|---|---|
| Dock and monitor profiles: save, restore and apply layouts on dock and undock, event-driven | `subcult-topology`, `subcult-machine-profile`, `subcult.operating-profile`, `TOPOLOGIES.md`, `MACHINE_PROFILES.md` | Display settings and a session service; replaces `sputnik-dock-workspaces` |
| Reduced motion on battery: animations, blur and shadows cut on battery, full on AC; also an accessibility setting | `subcult.motion`, `subcult-motion` | Setting read by the shell, Hyprland and hyprlock |
| Battery and thermal alerts with hysteresis and cooldowns | `subcult.thermal`, `subcult-thermal-alert`, `subcult-battery-alert` | Shell service, triggered by kernel and UPower events |
| Privacy indicator: microphone, camera, screen sharing, recording | `subcult.privacy`, `subcult-privacy` | Bar widget |
| Settings panel with preview, apply and one-step undo | `subcult.settings`, `subcult-settings`, `omarchy/settings-schema.json`, `SETTINGS.md` | Shell settings panel |
| Confirmation before destructive actions | `subcult.command-palette`, `COMMAND_PALETTE.md` | Launcher ([[0036-shell-components\|ADR 0036]]) |
| Workspace names with compact labels and a switch overlay | `subcult.workspace-names`, `subcult.workspace-osd`, `WORKSPACES.md` | Bar and OSD |
| Media controls across several players, privacy-safe artwork | `subcult.media`, `subcult-media`, `MEDIA_CONTROLS.md` | Bar media widget |
| Installer and migration safety: read-only preflight, dry run, backup, rollback | `preflight.py`, `install.sh --dry-run`, `rollback.sh`, `recovery/`, `migrations/` | Installer ([[0049-installer\|ADR 0049]]) and migrations ([[0026-update-model\|ADR 0026]]) |
| Memory and power budgets enforced in CI | `subcult-performance-budget`, `PERFORMANCE.md` | CI; the enforcement arm of ADR 0054 |
| Accessibility standard: contrast, scaling, keyboard, timeouts, flashing | `ACCESSIBILITY.md`, `tests/accessibility.py` | Design rules and CI checks |

The **brand kit** (`theme/brand/`: marks, lockups, Oswald, Space Grotesk,
JetBrains Mono) is also carried over as brand assets for the SUBCULT screens,
after checking `ASSETS_LICENSE.md`.

## Not ported

| Part | Reason |
|---|---|
| The theme: palette, wallpapers, affinity palettes, scenes, terminal profiles, theme variants | Owner declined the theme. |
| Activity modes, focus timer and closed-door indicator, context layer, sound cues, communications summary, device and dock overlay | Owner declined. |
| Translation system, update phase feedback, offline-resilience layer, demo scenarios and visual regression, capability detection, health report, operations log, performance diagnostics overlay | Not selected; not needed for a lightweight first release. |
| Ambient, boot sequence, screensaver mode, idle overlay, intrusion demo, Neon Overdrive, Cava, clocks | Presentation extras. |
| Clones and wrappers of Omarchy built-ins | Subarchy builds its own shell. |
| Suite packaging, updates, deployment and the start page | Specific to installing the rice over Omarchy. |

Related: [[subcult-rice|SUBCULT rice]] · [[0054-lightweight-battery-first|ADR 0054]] · [[0035-plugin-api|ADR 0035]]
