# ADR 0001: How Subcarchy relates to Omarchy

- Status: **proposed**, awaiting owner review
- Date: 2026-11-06
- Inputs: [component map](../inventory/omarchy-overview.md),
  [branding surfaces](../inventory/branding-surfaces.md),
  [SUBCULT rice](../inventory/subcult-rice.md)

## Context

Subcarchy should be a SUBCULT-branded desktop distribution. Three facts shape
the choice:

1. **Upstream moves fast.** Omarchy 4.5.0 ships 218 migrations dated
   2026-05-12 to 2026-11-02; 157 of them landed in the last 90 days. It also
   ships 556 commands, 32 shell plugins and hardware fixes for a dozen vendors.
2. **Branding is package-level.** The OS name, boot menu, boot splash, login
   screen and logos belong to `omarchy` and `omarchy-settings`, and
   `omarchy-settings` rewrites `/etc/os-release` and `plymouthd.conf` on every
   upgrade. A user-level overlay cannot rebrand them durably.
3. **The ecosystem depends on Omarchy's internal names.** All 39 community
   plugins and the 38 rice plugins run inside the Omarchy shell, call
   `omarchy-*` commands and read `~/.config/omarchy`. The existing rice is an
   overlay and needs a `post-update` hook to re-apply itself after updates.

## Options

| Option | What it means | Branding reach | Upstream cost | Plugin compatibility |
|---|---|---|---|---|
| A. Overlay (current rice) | Stock Omarchy plus Subcarchy packages and user config | User-level only; boot, login and OS name stay Omarchy | Low, but re-applies after every update | Full |
| **B. Tracking fork, internal names kept** | Fork `omacom/omarchy`; change branding, defaults and package selection; keep `omarchy-*` commands, `~/.config/omarchy` and `$OMARCHY_PATH` | Full | Medium: regular merges of a small diff | Full |
| C. Hard fork with full rename | Rename commands, paths and packages to `subcarchy` | Full | High: every upstream merge conflicts with the rename | Breaks community plugins until they are ported |
| D. From scratch | Arch, Hyprland and Quickshell with original code | Full | None, but everything is rebuilt | None; plugins target the Omarchy shell API |

## Proposed decision

Option **B**, in stages:

1. Fork `omacom/omarchy` to `git.subcult.tv` and track upstream `main` (or the
   release tags) on a schedule. This repository becomes that fork, or the fork
   is imported into it; see the open question below.
2. Build `subcarchy` and `subcarchy-settings` packages that declare
   `provides=(omarchy=<version> omarchy-settings=<version>)` and
   `conflicts=(omarchy omarchy-settings)`, so anything depending on `omarchy`
   still installs.
3. Keep the diff to branding (`etc-overrides/os-release`, Plymouth, SDDM,
   Limine, logos, fastfetch, menu text), default package and web-app selection,
   and fixes such as the shell overlay patch.
4. Ship SUBCULT features as separate packages in a Subcarchy pacman repository
   listed before `[omarchy]`: the theme and brand kit, the rice's commands and
   plugins, own plugins, and a curated set of community plugins.
5. Keep using `[omarchy]` for the kernel, Omarchy's own apps and its rebuilt AUR
   packages.
6. Defer renaming `omarchy-*` commands and paths. Revisit only if the fork's
   diff stays small for several upstream releases, and then as wrappers rather
   than a rename.

## Consequences

- Subcarchy can replace every visible Omarchy brand, which an overlay cannot.
- Community and rice plugins keep working unchanged.
- The rice's restore hook and the `~/.local/bin` shell overlay go away, because
  their changes move into the fork's packages.
- Someone must merge upstream regularly. With 157 migrations in 90 days,
  falling behind by a month means a large merge. The merge cadence and who
  does it are open.
- Users see `omarchy` in command names and config paths. That is a visible
  seam until a later decision removes it.
- Subcarchy needs its own signing key, repository host and build pipeline for
  a handful of packages, plus a choice about the ISO.

## Open questions for this decision

- Should this repository *be* the fork (import Omarchy's history and add the
  `docs/` and `tools/` folders), or stay a separate build repository that
  vendors the fork as a submodule or package source? The current layout mirrors
  Omarchy's tree so either works.
- Track upstream `main` or tagged releases only?
- Does the ISO reuse Omarchy's builder with Subcarchy package lists, or is the
  first target "install Omarchy, then convert"?
- Does the old `PatrickFanella/omarchy-subcult-theme` repository, which also
  installs as `subcult`, need retiring to avoid name clashes?
