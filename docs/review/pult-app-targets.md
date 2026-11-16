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

| Target | Integration | Repository acceptance check | Native acceptance on 2026-11-16 |
|---|---|---|---|
| swayimg | Upstream registry and Lua template; a `dofile()` in `init.lua`, version 5.5+ | Default, Dracula and light palette update viewer, gallery and text fields; custom Lua retained; exact undo | Installed swayimg 5.7 rendered viewer/gallery in all three palettes on a private headless display; background, text and selection-border pixels matched; normal undo restored original Lua |
| VS Code | Upstream `vscode` registry; JSONC keys in `Code/User/settings.json`, version 1.78+ | Editor and ANSI colours, dark/light base themes, comments and custom keys retained; duplicate keys rejected before writing; exact undo | Official portable Code 1.105.1 rendered workbench, Python syntax and terminal on owned Xvfb; dark/light base themes and live palette changes passed; normal undo restored original settings bytes |
| Obsidian | Upstream `obsidian` registry; theme CSS, manifest and selector in each registered vault | Two vaults, including a closed one and a path containing spaces; duplicate/stale registry entries; metadata, notes and workspace bytes retained; exact undo | Installed Obsidian 1.15.0 discovered and selected Pult in a disposable registered vault; all three palettes rendered, live changes and light restart passed; initialized-baseline undo passed, with first-launch conflict protection described below |
| bat, git-delta, eza, fzf | Existing upstream registry; ANSI selection or YAML colour keys | Included in the same apply/change/undo check with existing config fixtures | Native CLI rendering was not repeated for this change |
| Neovim | Existing `subcult` scheme reads the Pult shell palette | Existing `nvim-theme-test.sh`; shell palette generation checked by the new Pult fixture | Native installed-editor acceptance was not repeated |
| fastfetch | Existing terminal palette behaviour | No new registry entry or config rewrite; unchanged from #78's recorded covered list | Terminal colour rendering was not repeated |
| Chromium | Existing packaged managed `color.json`; `subcult theme apply-system` writes the selected palette through polkit | Existing `internal/systheme` tests and package-content checks | Sputnik's installed managed policy sets `BrowserThemeColor` to `#100b19` and dark appearance; a native browser policy-page readback was not performed |

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

## Native qualification and issue boundary

The November 16 Kvant/Sputnik native lane used the recipe-built Pult binary
with SHA-256
`6d7876d908d54f1b9b9ad353a52cd3ae815f1d349fcd2d8c26f178659b45aa55`.
Its upstream pin, embedded-data version and app integration code match the
merged recipe. Native tests used SUBCULT Minimal, Dracula and Catppuccin
Latte, disposable HOME/XDG roots, private D-Bus sessions and owned headless
Wayland/Xvfb displays. No owner vault, app singleton or desktop was used.
The screenshots were inspected; application configuration and rendering
checks are distinct in the matrix above.

The Code archive came from Microsoft's version API for 1.105.1; its
SHA-256 matched that API's
`32a650f1a111df00354ad9571f57d12268376777677dd5af2162ead921067a89`.
No extension or account was used. Code's default terminal contrast correction
can adjust glyph RGB values; runtime terminal theme variables matched Pult,
and all six Dracula ANSI colours also matched captured glyph pixels. The
test retained that accessibility behavior.

Native swayimg caught an invalid test preference before Pult's Lua could
load: `viewer.scale = 'fit'` requires a number in swayimg 5.7. The fixture
now uses its valid fixed-scale setting, `viewer.default_scale = 'fit'`, and
still requires byte-for-byte retention through palette changes and undo.
This corrects the test input; Pult's generated Lua did not need changing.

Obsidian's first launch adds preferences and reformats `appearance.json`.
Normal uninstall detected that app-written change, reported a conflict and
retained the edited file; no force was used. That is conflict protection,
not an exact-undo pass. A second round began with Obsidian's initialized
preferences, rendered dark/light palettes and then closed the app: normal
uninstall restored those original bytes and removed Pult's theme assets.

The native lane's cleanup readback found no owned app, D-Bus, display or
tunnel process left behind. Relevant real Sputnik config hashes matched
before and after; temporary binaries, profiles, runtime trees and Xauthority
were removed. Dated logs, screenshots, palette/pixel observations, source
provenance and cleanup receipts are retained privately with roadmap #230's
coordinator evidence.

#78 is an agent-completable integration issue: its criteria are coverage of
the listed app targets and a managed Chromium colour policy. The existing
Neovim palette reader and fastfetch terminal-colour path are the accepted
design recorded in [[0037-theming|ADR 0037]] and the issue's earlier comments;
they do not need redundant registry entries. The new entries/templates,
upstream tests, native checks and installed Chromium policy establish that
integration. No owner-acceptance gate is added to #78.

Package publication, the exact-release ISO install test and replacement of
the owner's installed Pult remain separate release qualification under #84
and hardware acceptance under #51. This native run used a supplied binary
in disposable roots: it did not install the new package, install Code on
Sputnik, inspect Chromium's native policy page or qualify the owner's
desktop. Those broader claims are not made by completing the integration.

VS Code's integration handles the default user profile; workspace and named
profile settings can override it. It uses built-in Modern themes and colour
customizations, so no extension registration is needed. VS Code is still a
pending preinstalled package in Subarchy's application inventory; this change
does not add it to the image. Obsidian discovers available absolute vault
paths from `obsidian/obsidian.json` with the default `.obsidian` directory;
custom config-directory names are not discovered. A first theme discovery
may require restarting Obsidian. swayimg reads its Lua config at launch.

Related: [[0037-theming|ADR 0037]] · [[review-index|Review]] · [[0048-config-ownership|ADR 0048]] · [[first-install|First install]]
