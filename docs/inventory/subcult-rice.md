# SUBCULT Omarchy Rice

The rice is the closest thing to Subcarchy that already exists. It is an
overlay on top of a stock Omarchy install, not a fork.

| Field | Value |
|---|---|
| Repository | `git.subcult.tv/PatrickFanella/subcult-omarchy-rice` (canonical), GitHub mirror `PatrickFanella/subcult-omarchy-rice` |
| Local checkout | `~/Work/Forks/subcult-omarchy-rice`, 127 commits |
| Version | 2.0.0. The 1.x line was published as Evangelion Omarchy Rice. |
| Supported Omarchy | `>=4.0.0, <5.0.0`, verified on 4.0.1-1. `sputnik` runs 4.5.0-3, which the rice has not recorded as verified. |
| Supported Hyprland | `>=0.56.0, <0.57.0` |
| Licence | MIT for software. The SUBCULT marks and fonts have separate terms in `ASSETS_LICENSE.md`. |
| Installed on `sputnik` | Plugins, commands, hooks and services dated 2026-10-05; the theme `subcult-minimal` is current; the SUBCULT bar layout is not active since 2026-11-02. |

## What it contains

| Part | Contents | Repo path |
|---|---|---|
| Theme | `subcult` palette, 7 wallpapers rendered from the brand kit, btop and icon themes, keyboard RGB | `theme/` |
| Brand kit | SVG marks and lockups, fonts (Oswald, JetBrains Mono) | `theme/brand/` |
| Shell plugins | 38 `subcult.*` plugins plus `neon.overdrive` compatibility widget | `omarchy/plugins/` |
| Commands | 61 `subcult-*` commands and two `omarchy-*` overrides (`omarchy-launch-screensaver`, `omarchy-launch-terminal`) | `bin/` |
| Configuration | 27 JSON files (settings schema, scenes, activity modes, topologies, motion, sound, privacy) and a `shell.json` | `omarchy/` |
| Menus | `omarchy-menu.subcult.jsonc` | `omarchy/extensions/` |
| Hooks | boot sequence, post-update restore, theme-set affinity and terminal profile | `omarchy/hooks/` |
| Services | `subcult-affinity.path`/`.service`, `subcult-start-page.service`, `subcult-topology.service` | `systemd/` |
| Hyprland | Lua overrides and a recovery copy | `hypr/`, `recovery/` |
| Shell integration | bash, zsh and fish snippets | `shell/` |
| Extras | Fastfetch, Neovim, start page, tmux theme | `fastfetch/`, `nvim/`, `start-page/` |
| Packaging | Release PKGBUILD template, VCS PKGBUILD, release archive builder | `packaging/arch/`, `scripts/build-*` |
| Safety | `preflight.py` (read-only checks), `install.sh --dry-run`, `rollback.sh`, `validate.sh`, migrations between versions | repo root, `migrations/` |
| Tests | 69 test files and visual-regression fixtures | `tests/`, `visual-regression/` |
| Docs | 46 Markdown documents covering settings, scenes, workspaces, accessibility, privacy, performance and release | repo root |

## Features worth carrying into Subcarchy

These are described in the rice's own documents; this inventory did not
re-test them on Omarchy 4.5.

- **Control center** (`subcult-settings`, `subcult.settings`): one keyboard-first
  surface for palette, motion, profile, widgets, weather, media, privacy, sound
  and display, with preview and one-step undo.
- **Affinity palettes**: the wallpaper selects one of five palettes (Press,
  Acid Block, Paper Stock, Violet Field, Ink Run). Theme variants add Standard,
  OLED, Daylight and High Contrast treatments.
- **Scenes and activity modes**: reversible bundles of wallpaper, palette,
  terminal profile, motion and sound; Work, Focus, Gaming, Presentation, Travel
  and Quiet modes.
- **Workspace identities**: named workspaces that shorten safely against the
  bar width.
- **Monitor topology profiles** and **machine profiles**: save and restore dock
  layouts; export privacy-sanitised profiles between machines. This covers the
  problem `sputnik-dock-workspaces` solves by hand.
- **Context layer**: on-demand, allowlisted facts (power, thermal, displays,
  connectivity, media) that drive advisory recommendations. No network I/O.
- **Operations log, command palette, sound cues, offline resilience,
  accessibility standards, localisation.**

## Limits of the overlay approach

The rice already shows what an overlay costs:

- It replaces whole Omarchy shell and Hyprland files after confirmation, so
  upstream changes to those files have to be merged by hand.
- `post-update.d/90-restore-subcult` re-applies the rice after every Omarchy
  update because updates can undo it.
- It cannot change `/etc/os-release`, Plymouth, SDDM, Limine or the installer,
  which `omarchy-settings` controls.
- It supports a version range (`<5.0.0`) and must be re-verified as Omarchy
  moves; 4.5 is untested by its own records.

[ADR 0001](../decisions/0001-fork-strategy.md) uses these points to choose
between continuing the overlay and forking.
