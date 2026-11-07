---
title: "Brand identity"
type: brand
status: draft
created: 2026-11-06
updated: 2026-11-06
tags: [brand]
aliases: [Brand draft]
---

# Brand identity (draft)

Status: draft for review. The name is decided; palette, marks and type are
not yet approved.

## Name

The distribution is **Subarchy** (sub + Arch + anarchy). Screens show the
**SUBCULT** mark and wordmark, and the command is `subcult`, with `sub` as a
short alias. The full table of where each name appears is in
[[0052-name-identity|ADR 0052]].

Still worth keeping in mind when writing about it:

- Present Subarchy as SUBCULT's distribution, not as an Omarchy edition (see
  the trademark note in [[branding-surfaces|branding surfaces]]).
- Keep it distinct from **Subcult OS**, the event-operations product in
  `subculture-collective/subcult-os`.
- The SUBCULT sub-brand map
  (`Strategy/Identity/Canon/SUBCULT Project and Sub-Brand Map.md` in the
  SUBCULT vault) asks sub-brands to keep SUBCULT's commitments to legibility,
  agency, memory and anti-extraction.

## Starting palette

The SUBCULT rice's `subcult` theme is the obvious base. Its `colors.toml`:

| Role | Value | Notes |
|---|---|---|
| Background (ink) | `#100B19` | Darker steps `#0B0812`, `#06040A`; lighter `#1F1830` |
| Foreground (paper) | `#F0ECE4` | Dim `#9A92A8`, light `#DDD6E8` |
| Accent (acid) | `#00FF88` | Active border colour |
| Selection (violet) | `#3B2470` | Brand violet in the artwork is `#8B5CF6` |
| Active window border | `rgba(8F4BC8ee) rgba(9CF23Aee) 45deg` | Violet to acid gradient |
| ANSI | red `#D52032`, yellow `#F6D447`, green `#00D474`, cyan `#4FD6C8`, blue `#5577CC`, magenta `#A78BFA` | Bright variants in the source file |

`subcult-minimal`, the current theme on `sputnik`, is the "minimal low-power
variant": the same colours with solid borders (`rgb(8F4BC8)` active,
`rgb(1F1830)` inactive) instead of the gradient. The rice also defines five affinity palettes (Press, Acid Block,
Paper Stock, Violet Field, Ink Run) and four variants (Standard, OLED,
Daylight, High Contrast).

## Marks and type

From `subcult-omarchy-rice/theme/brand/`:

- SVG marks: `mark-primary`, `mark-dark`, `mark-mono-dark`, compact marks, and
  primary and dark lockups; `mark-fisheye-circle.png`.
- Fonts: Oswald (display) and JetBrains Mono (interface and terminal).
- Seven 2560×1440 wallpapers rendered from those marks by
  `scripts/build-wallpapers`, with SHA-256 sums in `ARTWORK.md`.

The marks and fonts carry their own licence terms in the rice's
`ASSETS_LICENSE.md`. Check them before the assets go into a redistributable
image.

## Assets the distribution needs

Each replaces an Omarchy surface listed in
[[branding-surfaces|branding surfaces]].

| Asset | Format | Exists? |
|---|---|---|
| Wordmark for terminals (`logo.txt`) and About screen | ASCII/Unicode block text | No; `sputnik` has a custom `about.txt` that could be the start |
| Logo (`logo.svg`) and icon (`icon.png`, `icon.txt`) | SVG, PNG, ASCII | Marks exist; sized icon variants do not |
| Plymouth boot splash | PNG logo, progress art, script | No |
| SDDM login theme | QML and images | No |
| Limine branding string and colours | Text, hex | No |
| Wallpapers | PNG | Yes, seven |
| `os-release` | Text | No |
| Theme intro videos | Video | No; optional |

## Voice

Follow `SUBCULT Brand Voice.md` in the SUBCULT vault for user-facing text. The
rice's documentation already uses a plain, specific style: it states what is
verified and what is not.

Related: [[branding-surfaces|Branding surfaces]] · [[subcult-rice|SUBCULT rice]] · [[open-questions|Open questions]]
