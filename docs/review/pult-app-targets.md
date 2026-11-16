---
title: "Pult application targets"
type: review
status: active
review: pending
created: 2026-11-16
updated: 2026-11-16
tags: [review, theming, pult]
---

# Pult application targets

Issue #78, under epic #12 and roadmap #230, tracks the application targets
in [[0037-theming|ADR 0037]]. Its November 8–11 comments predate the current
upstream integrations. This note separates the package integration from
native application and installed-system acceptance.

## Package boundary

`packaging/pult/PKGBUILD` pins Pult commit
`7a703f18d2a934d5c4821c24a723c0ad4863417d` as
`0.4.1.r2.g7a703f1`: the two commits after the published 0.4.1 release.
[Pult PR #37](https://github.com/subculture-collective/pult/pull/37)
adds VS Code JSONC editing, and
[Pult PR #38](https://github.com/subculture-collective/pult/pull/38)
adds registered Obsidian vault discovery. The recipe uses that commit's
embedded registry and templates with the unchanged, checksum-pinned 0.4.1
catalog. No upstream source patch or host configuration change is needed.
Replace the snapshot with the next release that contains both commits;
`0.4.2` sorts after this package version.

The built-in data version is `2026.11.16.1`, so an older signed data bundle
cannot replace the new registry. Newer signed bundles retain Pult's normal
precedence. Package source and catalog downloads both require SHA-256 matches.

## Acceptance matrix

| Target | Integration | Repository acceptance check | Remaining native acceptance |
|---|---|---|---|
| swayimg | Upstream registry and Lua template; a `dofile()` in `init.lua`, version 5.5+ | Default, Dracula and light palette update viewer, gallery and text fields; custom Lua retained; exact undo | Launch viewer and gallery on the installed desktop after a palette change |
| VS Code | Upstream `vscode` registry; JSONC keys in `Code/User/settings.json`, version 1.78+ | Editor and ANSI colours, dark/light base themes, comments and custom keys retained; duplicate keys rejected before writing; exact undo | Install/run VS Code and check workbench, syntax and terminal in both appearances |
| Obsidian | Upstream `obsidian` registry; theme CSS, manifest and selector in each registered vault | Two vaults, including a closed one and a path containing spaces; duplicate/stale registry entries; metadata, notes and workspace bytes retained; exact undo | Open registered vaults and check colours and first-time theme discovery on the installed build |
| bat, git-delta, eza, fzf | Existing upstream registry; ANSI selection or YAML colour keys | Included in the same apply/change/undo check with existing config fixtures | Native CLI rendering was not repeated for this change |
| Neovim | Existing `subcult` scheme reads the Pult shell palette | Existing `nvim-theme-test.sh`; shell palette generation checked by the new Pult fixture | Native installed-editor acceptance was not repeated |
| fastfetch | Existing terminal palette behaviour | No new registry entry or config rewrite; unchanged from #78's recorded covered list | Terminal colour rendering was not repeated |
| Chromium | Existing packaged managed `color.json`; `subcult theme apply-system` writes the selected palette through polkit | Existing `internal/systheme` tests and package-content checks | Live Chromium policy readback was not repeated |

The CLI acceptance fixture substitutes app binaries for detection. It runs
the real packaged Pult, its embedded catalog, registry and templates in a
temporary HOME with separate XDG paths and a restricted app profile. It
does not render apps or connect to the owner's desktop. It checks a dry run,
palette changes, repeated application, restoration of the default theme and
byte-for-byte uninstall. The package check also runs Pult's own Go tests.

## Reproduce

```bash
GOMAXPROCS=2 GOFLAGS=-p=2 tools/test/pult-package-test.sh
GOMAXPROCS=2 GOFLAGS=-p=2 make verify
```

The first command downloads about 3 MB of pinned source/catalog assets,
builds and tests the recipe, then stages the executable, licences and README
under a temporary directory. It needs Go, Python 3.11+, Bash, curl, Git,
tar and sha256sum; it does not require pacman or install packages. PR CI
runs it after `make verify`. On Arch, the recipe's `check()` runs the same
app fixture as part of makepkg.

## Installed-system follow-up

Keep #78 open until its acceptance evidence is reconciled with this package.
This checkout does not establish package publication, an ISO install test,
or native rendering on Sputnik. No ISO or VM build belongs in this lane.

- [ ] Qualify the new Pult package in the normal main-branch package/ISO jobs.
- [ ] Run `pult list` on the target and confirm the three remaining entries.
- [ ] With disposable VS Code settings and registered Obsidian vaults, apply
  the default profile, Dracula and a light theme; inspect each native app.
- [ ] Confirm swayimg viewer and gallery use the selected palette after relaunch.
- [ ] Close apps before testing normal `pult uninstall` restoration; do not
  force past app-written configuration conflicts.
- [ ] Record exact package versions and results on #78 before closing it.

VS Code's integration handles the default user profile; workspace and named
profile settings can override it. It uses built-in Modern themes and colour
customizations, so no extension registration is needed. VS Code is still a
pending preinstalled package in Subarchy's application inventory; this change
does not add it to the image. Obsidian discovers available absolute vault
paths from `obsidian/obsidian.json` with the default `.obsidian` directory;
custom config-directory names are not discovered. A first theme discovery
may require restarting Obsidian. swayimg reads its Lua config at launch.

Related: [[0037-theming|ADR 0037]] · [[review-index|Review]] · [[0048-config-ownership|ADR 0048]] · [[first-install|First install]]
