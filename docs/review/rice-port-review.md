---
title: "SUBCULT rice port review"
type: review
status: draft
review: pending
created: 2026-11-06
updated: 2026-11-06
tags: [review, rice, shell]
aliases: [Rice port list, What to port from the rice]
---

# SUBCULT rice port review

The owner does not want the SUBCULT rice's theme in Subarchy, but wants
anything useful from it ported (2026-11-06). This note sorts the rice 2.0.0
(`~/Work/Forks/subcult-omarchy-rice`) into **port**, **port the idea**, and
**skip**. Ports go through Subarchy's own plugin API
([[0035-plugin-api|ADR 0035]]) and CLI ([[0046-distribution-cli|ADR 0046]]),
so every port is a rewrite guided by the rice's code, docs and tests, not a
copy.

The command name overlap (`subcult-*` in both) is accepted; the rice is
removed from a machine before Subarchy is installed
([[0052-name-identity|ADR 0052]]).

Change any verdict you disagree with.

## Port

Theme-independent features that fill a gap in the decisions so far.

| Feature | Rice source | Lands in | Why |
|---|---|---|---|
| Settings control center: schema-backed, preview, apply, one-step undo | `subcult.settings`, `subcult-settings`, `omarchy/settings-schema.json`, `SETTINGS.md` | Shell settings panel | Subarchy has no settings design yet; the schema and undo model are reusable. |
| Command palette with danger confirmation | `subcult.command-palette`, `COMMAND_PALETTE.md` | Shell launcher ([[0036-shell-components\|ADR 0036]]) | Pairs with `subcult commands --json`; confirmation before destructive actions. |
| Privacy indicator: microphone, camera, screen sharing, recording, remote control | `subcult.privacy`, `subcult-privacy` | Bar widget | Nothing else in the plan shows when a device or screen is being captured. |
| Monitor topology and machine profiles; docked and mobile profile | `subcult-topology`, `subcult-machine-profile`, `subcult.operating-profile`, `TOPOLOGIES.md`, `MACHINE_PROFILES.md` | Display settings and a user service | Replaces the hand-written `sputnik-dock-workspaces` watcher with a general feature. |
| Workspace names with compact labels; workspace change overlay | `subcult.workspace-names`, `subcult.workspace-osd`, `WORKSPACES.md` | Bar and OSD | Fits the per-monitor bar from `omarchy-monitor-bar`. |
| Thermal and battery alerts with hysteresis and cooldowns; quiet-when-nominal health summary | `subcult.thermal`, `subcult-thermal-alert`, `subcult-battery-alert`, `subcult.health` | Shell services and bar | Hardware-neutral, with tested thresholds. |
| Motion preference: Off, Reduced, Full | `subcult.motion`, `subcult-motion` | Accessibility setting read by shell, Hyprland animations and hyprlock | Accessibility; the power switcher already hooks into it on `sputnik`. |
| Media controls across several MPRIS players, privacy-safe artwork | `subcult.media`, `subcult-media`, `MEDIA_CONTROLS.md` | Bar media widget | Handles more than one player without moving the bar layout. |
| Update phase feedback | `subcult.update-operation` | UI for the update command ([[0026-update-model\|ADR 0026]]) | Shows snapshot, upgrade, DKMS and migration phases without blocking. |
| Localisation runtime: versioned catalogue, fallback, RTL tests | `subcult.localization`, `subcult-i18n`, `LOCALIZATION.md` | Shell i18n | The owner's plugins already ship ten languages. |
| Accessibility standard: contrast, scaling, keyboard, timeouts, flashing | `ACCESSIBILITY.md`, `tests/accessibility.py` | Design rules and CI checks for the shell and themes | Applies to every screen. |
| Brand kit: marks, lockups, Oswald, Space Grotesk, JetBrains Mono | `theme/brand/` | `branding/` ([[0052-name-identity\|ADR 0052]], [[0039-fonts-icons\|ADR 0039]]) | Brand, not theme: the screens show SUBCULT. Check `ASSETS_LICENSE.md` first. |

## Port the idea, not the code

Patterns worth keeping where Subarchy builds the equivalent itself.

| Idea | Rice source | Applies to |
|---|---|---|
| Read-only preflight, dry run, backup and rollback before writing | `preflight.py`, `install.sh --dry-run`, `rollback.sh`, `recovery/` | Installer ([[0049-installer\|ADR 0049]]) and migrations |
| Versioned migrations between releases with JSON manifests | `migrations/`, `subcult-migrate` | Migrations ([[0026-update-model\|ADR 0026]]) |
| Offline resilience: bounded retries, cache-age labels, privacy-safe unavailable states | `subcult-resilience`, `OFFLINE_RESILIENCE.md` | Every widget that fetches data |
| Performance budgets and opt-in shell diagnostics | `subcult-performance-budget`, `subcult.performance`, `PERFORMANCE.md` | CI budgets for the shell |
| Deterministic demo scenarios and visual regression captures | `subcult.demo`, `visual-regression/`, `DEMO.md` | Screenshot tests for the shell, SDDM and lock screen |
| Portable hardware capability detection | `subcult-capabilities` | Hardware detection ([[0050-hardware-support\|ADR 0050]]) |
| Health report a user can attach to a bug | `subcult-rice-health`, `beta-report.sh`, `COMMUNITY_REPORT_TRIAGE.md` | `subcult doctor` style diagnostics |
| Privacy-bounded event history | `subcult.operations-log`, `OPERATIONS_LOG.md` | Notification history: decide whether it needs more than the notification centre |

## Decide later

Useful but large or overlapping; each needs a yes or no from the owner.

| Feature | Rice source | Question |
|---|---|---|
| Activity modes: Work, Focus, Gaming, Presentation, Travel, Quiet | `subcult-activity-mode`, `ACTIVITY_MODES.md` | Wanted as one-step bundles of settings? |
| Focus timer and "closed door" indicator | `subcult.mission`, `subcult.closed-door`, `subcult-focus` | Overlaps Super Productivity and Tadooer focus features. |
| Context layer: explainable recommendations from power, thermal, display and network facts | `subcult.context`, `subcult-context*`, `CONTEXT.md` | Large; worth it in the first release? |
| Sound cues with quiet hours and a kill switch | `subcult-sound`, `SOUND.md` | Wanted at all? |
| Communications summary: network, VPN, Bluetooth, Tailscale | `subcult.communications` | Could fold into the network panel with the DNS trust policy ([[0020-dns\|ADR 0020]]). |
| Device and dock overlay | `subcult.device-osd`, `subcult-device-monitor` | Overlaps topology profiles. |
| Theme variants mechanism (OLED, Daylight, High Contrast) | `subcult-theme-variant`, `THEME_VARIANTS.md` | The mechanism is theme-independent; High Contrast matters for accessibility. Keep for [[0037-theming\|ADR 0037]]? |

## Skip

| Part | Rice source | Why |
|---|---|---|
| The theme: `subcult` palette, seven wallpapers, affinity palettes and affinity switching | `theme/colors.toml`, `theme/backgrounds/`, `subcult-affinity`, `subcult-visual` | The owner does not want the theme ported. |
| Scenes and scene editor | `subcult-scene`, `subcult.scene-editor`, `SCENES.md` | Built around wallpapers, affinities and terminal profiles. |
| Terminal profiles and terminal context | `subcult-terminal-profile`, `subcult-terminal-context` | Theme treatment. |
| Ambient, boot sequence, screensaver mode, idle overlay, intrusion demo, Neon Overdrive | `subcult-ambient`, `subcult-boot-sequence`, `subcult-screensaver*`, `subcult.idle`, `subcult.intrusion`, `neon.overdrive` | Theme presentation. |
| Clones and wrappers of Omarchy built-ins | `subcult.battery`, `.clipboard`, `.lock`, `.notifications`, `.power`, `.workspaces`, `.agents`, `.bluetooth`, `.dropbox`, `.tailscale`, `.icon-theme` | Subarchy builds its own shell; lock is hyprlock ([[0036-shell-components\|ADR 0036]]). |
| Suite packaging and lifecycle | `subcult-suite-update`, `subcult-update`, `subcult-deployment`, `subcult-extension-state`, `subcult-user-config`, `subcult-disclosure`, `packaging/`, `release/` | Specific to installing the rice over Omarchy. |
| Start page | `subcult-start-page`, `start-page/` | A local dashboard outside the decided scope. |
| Clock and world clock | `subcult-clock`, `subcult.world-clock` | Omarchy's `elsewhen` widget is already in use on `sputnik`; one clock widget is enough. |
| Cava visualiser | `subcult.cava` | Optional eye candy; revisit with the media widget. |

## Consequences for other notes

- [[0037-theming|ADR 0037]] no longer ships the rice's `subcult` and
  `subcult-minimal` themes or affinity palettes. A new SUBCULT theme is
  designed in Subarchy's format from the brand colours.
- [[triage|Triage]]'s SUBCULT rice section is replaced by this note.

Related: [[subcult-rice|SUBCULT rice]] · [[0035-plugin-api|ADR 0035]] · [[0037-theming|ADR 0037]] · [[triage|Triage]]
