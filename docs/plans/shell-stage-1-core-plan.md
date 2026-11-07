---
title: "Shell stage 1, plan 1: look, fonts and core bar"
type: plan
status: accepted
created: 2026-11-07
updated: 2026-11-07
tags: [plan, shell, theme, fonts]
aliases: [Shell core plan]
---

# Shell stage 1, plan 1: look, fonts and core bar — implementation plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A fresh Subarchy install shows `sputnik`'s look: the flat
`subcult-minimal` compositor, the font roles, and a Quickshell bar with every
widget that works from local events, plus notifications, OSD, polkit and
Alt-Tab.

**Architecture:** Static defaults (palette, Hyprland look, GTK, fontconfig,
kitty, Neovim) install from `default/` through the `subarchy` package. A Go
command `subcult-font` manages font roles. The shell is QML in `shell/`,
installed to `/usr/share/subcult/shell/` and run by `subcult-shell.service`.
Logic that can be pure lives in `.js` files tested with `qmltestrunner`; QML
files only bind models to Quickshell.

**Tech Stack:** Quickshell 0.3.2 (`extra`), Qt 6 QML, Go 1.27, Bash,
fontconfig, Python 3 for the VM test.

**Spec:** [[shell-and-look-design|Shell and look: design]] and
[[0068-shell-plugin-api-v0|ADR 0068]]. Plans 2 (weather, Soma, n8n, HT3) and
3 (calendar) follow this one.

## Global Constraints

- Palette values (from the spec): `base` `#100B19`, `mantle` `#0B0812`,
  `crust` `#06040A`, `surface0` `#1F1830`, `text` `#F0ECE4`, `subtext1`
  `#DDD6E8`, `subtext0` `#9A92A8`, `overlay0` `#5E5570`, `green` `#00FF88`,
  `mauve` `#8F4BC8`, `lavender` `#A78BFA`, `selection_bg` `#3B2470`; ANSI 0–15
  from `~/.config/omarchy/themes/subcult-minimal/colors.toml` on `sputnik`.
- Compositor: gaps 0, border 1 px, rounding 0, opacity 1, no blur, shadow,
  dimming or animations; active border `mauve`, inactive `surface0`.
- Cursor: Subarchy's own `subcult-cursor`, fill role `lavender` by default,
  outline `crust`, size 24; no third-party cursor set.
- Bar: top edge, about 26 px at scale 1, opaque `base`; Full on the primary
  output and any `eDP-*` output, Minimal elsewhere.
- Font roles are fontconfig aliases: `monospace` JetBrainsMono Nerd Font,
  `sans-serif` JetBrainsMono Nerd Font Propo, `serif` Libertinus Mono then
  Noto Serif; Symbols Nerd Font and Noto behind every role.
- Every widget is written fresh. Nothing is copied from
  `/usr/share/omarchy/shell` or from `~/.config/omarchy/plugins`; read them
  only to list features.
- Paths: system defaults `/usr/share/subcult/default/…`, user config
  `~/.config/subcult/…`, state `~/.local/state/subcult/…`
  ([[0048-config-ownership|ADR 0048]]). Widget ids `subcult.<name>`.
- No timer in a widget without AC and battery values in its manifest
  ([[0068-shell-plugin-api-v0|ADR 0068]]). Panels load only while open.
- Commits as `SUBCULT Agent <info@subcult.tv>`, unsigned, ending with the
  `Co-Authored-By` line; PRs end with the Claude Code line. One PR per phase.
- `make verify` stays green on `ubuntu-latest`; shell checks run in the
  `archlinux:latest` container job.

## Review Focus

1. **A broken or partial user palette** (`~/.config/subcult/theme/palette.json`
   with bad JSON, a missing role or a non-hex value): every bad role falls
   back to the default value; the shell keeps running. Tested in Task 6.
2. **A broken user `bar.json`:** the shell logs one warning and uses the
   defaults. Tested in Task 6.
3. **Monitors plugged or unplugged while running:** a bar appears or goes
   away, and Full/Minimal is recomputed. Tested in Task 9's headless harness
   by adding a second output.
4. **A machine with no battery:** `onBattery` stays false and the battery
   widget is hidden. Tested in Task 11.
5. **A font role pointing at a family that was uninstalled:**
   `subcult font current` shows the configured and the resolved family and
   flags the mismatch. Tested in Task 4.

---

## Phase A: look layer (PR "feat: subcult-minimal look layer")

### Task 1: Palette, Hyprland look and theme include

**Files:**
- Create: `default/theme/palette.json`
- Create: `default/hypr/theme.lua`
- Modify: `default/hypr/looknfeel.lua`
- Create: `tools/test/palette-test.py`
- Modify: `Makefile` (`docs-check` runs the palette test)

**Interfaces:**
- Produces: `palette.json` with `schema: 1`, `name: "subcult-minimal"`,
  `appearance: "dark"`, and an object `colors` holding the 26 Catppuccin role
  names, `ansi0`…`ansi15`, `background`, `foreground`, `cursor`,
  `selection_bg`, `selection_fg`. Roles the spec does not pin are filled by
  the implementer from `subcult-minimal` (`surface1` `#2A2140`, `surface2`
  `#3B2470` are acceptable). Task 6 reads this file.
- Produces: `default/hypr/theme.lua` sets the border and group colours, then
  runs `~/.config/subcult/theme/hyprland.lua` with `dofile` if it exists
  (the file Theme Tender will own).

- [x] **Step 1: Write the failing test** `tools/test/palette-test.py`:
  asserts `colors` has all 47 keys, every value matches `^#[0-9A-F]{6}$`,
  `base == "#100B19"`, `mauve == "#8F4BC8"`, `green == "#00FF88"`, and that
  `default/hypr/theme.lua` contains `rgb(8F4BC8)` and `rgb(1F1830)`.
- [x] **Step 2: Run it:** `python3 tools/test/palette-test.py` → FAIL, file
  missing.
- [x] **Step 3: Write `palette.json`, `theme.lua`, and change
  `looknfeel.lua`** to the compositor values in Global Constraints, with
  `require("default.hypr.theme")` at the end. Keep `resize_on_border`,
  `layout = "dwindle"` and the `misc` block.
- [x] **Step 4: Run** `python3 tools/test/palette-test.py && make hypr-check`
  → PASS, `hypr-check: ok`.
- [x] **Step 5: Commit** `feat: subcult-minimal palette and flat compositor`.

### Task 2: GTK, icons, kitty and Neovim defaults

**Files:**
- Create: `default/gtk/90-subarchy.gschema.override`,
  `default/gtk/settings.ini` (installed for both GTK 3 and 4)
- Create: `default/kitty/kitty.conf`, `default/kitty/subcult-ink.conf`
- Create: `default/nvim/colors/subcult-ink.lua`, `default/nvim/sysinit.vim`
- Modify: `install/packages/desktop.txt`, `packaging/subarchy/PKGBUILD`,
  `tools/test/package-test.sh`

**Interfaces:**
- GSettings override for `org.gnome.desktop.interface`: `gtk-theme`
  `'Adwaita-dark'`, `color-scheme` `'prefer-dark'`, `icon-theme`
  `'Papirus-Dark'`, `cursor-theme` `'subcult-cursor'`,
  `cursor-size` `24`, `font-name` `'Sans 11'`, `monospace-font-name`
  `'Monospace 11'`, `document-font-name` `'Serif 11'`.
- kitty: `font_family monospace`, `font_size 9.0`, `window_padding_width 0`,
  `hide_window_decorations yes`, `cursor_shape block`,
  `include subcult-ink.conf`. Because kitty asks fontconfig for `monospace`,
  font changes need no kitty edit. Colours come from
  `~/.local/share/subcult-ink/kitty.conf` on `sputnik` (owner's theme).
- Install targets: override →
  `/usr/share/glib-2.0/schemas/90-subarchy.gschema.override`; `settings.ini`
  → `/etc/xdg/gtk-3.0/settings.ini` and `/etc/xdg/gtk-4.0/settings.ini`;
  kitty →
  `/etc/xdg/kitty/`; Neovim colours → `/usr/share/nvim/runtime/colors/`,
  `sysinit.vim` → `/usr/share/nvim/sysinit.vim` (sets `colorscheme
  subcult-ink` only when no colourscheme was chosen).
- `desktop.txt` adds: `quickshell`, `papirus-icon-theme`,
  `brightnessctl`, `libsecret`, `mpv`.

- [x] **Step 1: Extend `package-test.sh`** to assert each install target
  above exists in the built package with mode 0644.
- [x] **Step 2: Run** `make package` → FAIL on the first missing path.
- [x] **Step 3: Add the files, PKGBUILD lines and package list.**
- [x] **Step 4: Run** `make package && make verify` → PASS.
- [x] **Step 5: Commit** `feat: GTK, Papirus, kitty and Neovim defaults`.

### Task 2b: Subarchy cursor

**Files:**
- Create: `default/cursor/svg/<shape>.svg` (about 15 shapes, 32×32 viewBox,
  fill `#FILL#`, outline `#LINE#`, 1 px at 24 px size), `default/cursor/shapes.tsv`
  (`shape  hotspot_x  hotspot_y  names…` mapping each shape to the standard
  cursor names, for example `default left_ptr arrow top_left_arrow`)
- Create: `bin/subcult-cursor`
- Create: `default/icons/index.theme` (`Inherits=subcult-cursor`)
- Modify: `default/hypr/envs.lua` (`XCURSOR_THEME` and `HYPRCURSOR_THEME` =
  `subcult-cursor`), `packaging/subarchy/PKGBUILD` (build the default theme in
  `build()` with `bin/subcult-cursor build --role lavender --out
  "$srcdir/subcult-cursor"` and install it to
  `/usr/share/icons/subcult-cursor/`; `index.theme` to
  `/usr/share/icons/default/`), `install/packages/desktop.txt` (`librsvg`,
  `xorg-xcursorgen`, `hyprcursor`), PKGBUILD `makedepends` (same three)
- Test: `tools/test/cursor-test.sh`, wired into `make smoke` when the three
  tools are present and always in the `package` CI job

**Interfaces:**
- `subcult-cursor` (subcult metadata header like the other `bin/` scripts):
  - `build --role <role> [--palette <file>] --out <dir>`: reads the role and
    `crust`/`text` from the palette (default: user palette, else the system
    one), picks the outline (`crust` unless the fill's OKLab lightness is
    below 0.5, then `text`), substitutes colours, renders PNGs at 24, 32, 48
    with `rsvg-convert`, writes Xcursor files with `xcursorgen` and symlinks
    every alias, writes the hyprcursor working state (`manifest.hl`, one
    `meta.hl` per shape with `define_override` for the aliases, the SVGs) and
    compiles it with `hyprcursor-util --create`. Writes `index.theme`
    (`Name=subcult-cursor`).
  - `apply`: reads `~/.config/subcult/cursor.json` (`{"role": "lavender",
    "size": 24}`, defaults if missing or broken), runs `build` into
    `~/.local/share/icons/subcult-cursor/` through a temp dir and an atomic
    rename, then `hyprctl setcursor subcult-cursor <size>` and
    `gsettings set org.gnome.desktop.interface cursor-theme subcult-cursor`
    / `cursor-size`.
  - `set [--role <role>] [--size 24|32|48]`: validates the role against the
    palette's keys, writes `cursor.json`, runs `apply`.
- Task 7's `Theme` runs `subcult cursor apply` (detached, through
  `Process`) when the palette file changes; a change to `cursor.json` from
  `set` already applies.
- [x] **Step 1: Write `cursor-test.sh`**: builds into a temp dir with the
  system palette and asserts `cursors/left_ptr`, `cursors/text` and
  `cursors/pointer` exist and are Xcursor files (`head -c4` is `Xcur`), every
  name in `shapes.tsv` resolves, the hyprcursor archive for `left_ptr`
  exists, the 24 px arrow PNG's most common non-transparent colour is
  `#A78BFA`; then `set --role nonsense` fails with exit 2 and leaves
  `cursor.json` unchanged.
- [x] **Step 2:** `tools/test/cursor-test.sh` → FAIL.
- [x] **Step 3:** Draw the shapes, write `shapes.tsv` and the script.
- [x] **Step 4:** `tools/test/cursor-test.sh && make package && make
  shellcheck` → PASS. Look at the 48 px PNGs and compare them with the
  arrow on `sputnik` before committing.
- [x] **Step 5: Commit** `feat: Subarchy cursor coloured from the palette`.

### Task 3: Font roles and preinstalled fonts

**Files:**
- Create: `default/fontconfig/50-subarchy-roles.conf`
- Modify: `install/packages/desktop.txt`, `packaging/subarchy/PKGBUILD`,
  `tools/test/package-test.sh`

**Interfaces:**
- `50-subarchy-roles.conf` installs to `/usr/share/fontconfig/conf.avail/`
  with a symlink in `/etc/fonts/conf.d/`. It prefers, per alias:
  `monospace` → JetBrainsMono Nerd Font, Symbols Nerd Font Mono, Noto Sans
  Mono, Noto Color Emoji; `sans-serif` → JetBrainsMono Nerd Font Propo,
  Symbols Nerd Font, Noto Sans, Noto Sans CJK SC, Noto Color Emoji; `serif`
  → Libertinus Mono, Noto Serif, Noto Serif CJK SC.
- `desktop.txt` adds: `ttf-jetbrains-mono-nerd`, `ttf-3270-nerd`,
  `ttf-adwaitamono-nerd`, `ttf-space-mono-nerd`, `ttf-sharetech-mono-nerd`,
  `otf-atkinsonhyperlegiblemono-nerd`, `ttf-nerd-fonts-symbols`,
  `ttf-nerd-fonts-symbols-mono`, `otf-libertinus`, `ttf-liberation`.
  The user font file written by Task 5 loads after this one (number 60).

- [x] **Step 1:** `package-test.sh` asserts the conf and its symlink.
- [x] **Step 2:** `make package` → FAIL.
- [x] **Step 3:** Add the file, symlink and packages.
- [x] **Step 4:** `make package` → PASS and `xmllint --noout
  default/fontconfig/50-subarchy-roles.conf` → no output. The resolved
  families are asserted in the VM (Task 16).
- [x] **Step 5: Commit** `feat: font roles through fontconfig aliases`.

Open the Phase A PR. Done when CI is green and it merges.

## Phase B: `subcult font` (PR "feat: subcult font")

### Task 4: `internal/font` catalogue, check and user config

**Files:**
- Create: `internal/font/catalog.go`, `check.go`, `userconf.go`
- Test: `internal/font/catalog_test.go`, `check_test.go`, `userconf_test.go`

**Interfaces:**
- Produces:
  - `type Role string` with `Mono Role = "monospace"`, `UI Role =
    "sans-serif"`, `Serif Role = "serif"`.
  - `type Entry struct { Family, Package string; Roles []Role; Preinstalled
    bool; Source string }`; `Source` is `"pacman"`, `"aur"` or `"release"`.
  - `func Catalog() []Entry`: the spec's preinstalled and on-pick tables,
    exactly (family names as fontconfig reports them: `CaskaydiaCove Nerd
    Font`, `BlexMono Nerd Font`, `Terminess Nerd Font`, `UbuntuMono Nerd
    Font`, `Ubuntu Nerd Font`, `Alegreya`, `Alegreya Sans`, …).
  - `const NerdFontsVersion = "v3.5.1"` and `func NerdFamilies() []string`:
    the 72 release archive names.
  - `type Verdict int` with `FullNerd`, `FallbackIcons`, `InterfaceOnly`,
    `BreaksTUI`, and `func (Verdict) String() string` returning "full Nerd
    Font", "works, icons from the Symbols fallback", "interface text only
    (not monospace)", "breaks terminal UIs (no box drawing)".
  - `type FontInfo struct { Family string; Spacing int; Charset []Range }`,
    `type Range struct{ Lo, Hi rune }`.
  - `func ParseFcQuery(out string) ([]FontInfo, error)` for the output of
    `fc-query -f '%{family[0]}\t%{spacing}\t%{charset}\n' <file>`.
  - `func Check(fi FontInfo) Verdict`: `Spacing < 90` → `InterfaceOnly`;
    missing any of U+2500–U+257F → `BreaksTUI`; has U+E0B0 and U+F015 →
    `FullNerd`; else `FallbackIcons`.
  - `func RenderUserConf(roles map[Role]string) string` and
    `func ParseUserConf(xml string) (map[Role]string, error)`: a fontconfig
    document with one `<alias binding="strong">` per role whose `<prefer>`
    holds the family.
- [x] **Step 1: Write failing tests**: `TestCatalogMatchesSpec` (7
  preinstalled entries: the six monospace fonts and Libertinus Mono; 13
  monospace choices; 5 interface and serif choices; no duplicate families;
  Symbols and Liberation are support packages, not catalogue entries);
  `TestNerdFamiliesCount` (72); `TestParseFcQuery` on a captured line from
  `sputnik`'s JetBrainsMono file and on a malformed line (error);
  `TestCheck` table: full Nerd, fallback, spacing 0 → interface only, no box
  drawing → breaks TUIs; `TestUserConfRoundTrip`; `TestParseUserConfBadXML`.
- [x] **Step 2:** `go test ./internal/font/` → FAIL (package missing).
- [x] **Step 3:** Implement.
- [x] **Step 4:** `go test -race ./internal/font/` → PASS.
- [x] **Step 5: Commit** `feat: font catalogue, check and role config`.

### Task 5: `cmd/subcult-font`

**Files:**
- Create: `cmd/subcult-font/main.go`, `cmd/subcult-font/main_test.go`
- Modify: `tools/test/dispatcher-smoke.sh` (asserts `subcult font list`)

**Interfaces:**
- Consumes: Task 4; `update.Runner` / `update.ExecRunner` from
  `internal/update` for commands; `dispatch.Metadata` as in `cmd/subcult-hw`.
- Produces subcommands (dispatcher words `font <sub>`):

| Command | Behaviour |
|---|---|
| `list [--all]` | Table: family, roles, `installed`/`available`, `*` on current per role. `--all` appends every `NerdFamilies()` name |
| `current` | Per role: configured family (user file) and resolved family (`fc-match -f '%{family[0]}' <alias>`); prints `mismatch` when they differ |
| `set <family> [--ui\|--serif] [--force]` | Installs if missing (as `install`), runs `check` on its files (`fc-list -f '%{file}\n' "<family>"`), refuses `InterfaceOnly`/`BreaksTUI` for monospace without `--force`, writes `~/.config/fontconfig/conf.d/60-subcult-fonts.conf`, runs `fc-cache -f`, then `pkill -USR1 -x kitty` (ignored if none) |
| `install <name>` | Catalogue or Nerd family with a pacman package → `sudo pacman -S --needed <pkg>`; otherwise downloads `https://github.com/ryanoasis/nerd-fonts/releases/download/<ver>/<Name>.tar.xz` and `SHA-256.txt`, verifies, unpacks to `~/.local/share/fonts/nerd-fonts/<Name>/`, runs `fc-cache -f`. Names outside the catalogue and `NerdFamilies()` are refused |
| `import <files…>` | Copies `.ttf`/`.otf` into `~/.local/share/fonts/subcult/`, runs `fc-cache -f`, prints each family's verdict |
| `check <family>` | Prints the verdict for each face |
| `patch <family>` | Prints the licence warning and asks `y/N`; installs `fontforge` with pacman if missing; downloads `FontPatcher.zip` for `NerdFontsVersion` and verifies it against a SHA-256 pinned in code; runs `fontforge -script font-patcher --complete --outputdir ~/.local/share/fonts/subcult-patched/ <file>` per face; never touches the original |

- [x] **Step 1: Write failing tests** with a fake `update.Runner` and a temp
  `HOME`: `set` writes the expected conf and calls `fc-cache`; `set` refuses
  an `InterfaceOnly` font without `--force`; `install` refuses `rm -rf` style
  and unknown names; a release download with a wrong checksum leaves no
  files behind (use `httptest.Server`, with the base URL injectable);
  `current` reports `mismatch`; `patch` exits without action on `n`.
- [x] **Step 2:** `go test ./cmd/subcult-font/` → FAIL.
- [x] **Step 3:** Implement. Pin the `FontPatcher.zip` SHA-256 by reading
  `SHA-256.txt` from the v3.5.1 release while implementing.
- [x] **Step 4:** `make verify` → PASS; `build/subcult font list` prints the
  catalogue.
- [x] **Step 5: Commit** `feat: subcult font list, set, install, import, check, patch`.

Open the Phase B PR; done when CI is green and it merges.

## Phase C: shell core (PR "feat: Quickshell shell core and bar")

### Task 6: Pure models and their tests

**Files:**
- Create: `shell/Commons/PowerModel.js`, `ConfigModel.js`,
  `LayoutModel.js`, `ThemeModel.js`, `ManifestModel.js`
- Test: `shell/tests/tst_models.qml`
- Modify: `Makefile` (`shell-test`: `qmltestrunner -platform offscreen
  -input shell/tests`; `shell-lint`: `qmllint` on `git ls-files 'shell/*.qml'`)

**Interfaces (all `.pragma library`):**
- `PowerModel.intervalMs(manifest, timerName, onBattery) -> number`: seconds
  from `manifest.cost.timers[name].ac|battery` × 1000; throws
  `Error("no timer <name>")`.
- `ConfigModel.merge(defaults, user) -> object`: objects merge recursively,
  arrays and scalars from `user` replace; `user` that is not an object
  returns a copy of `defaults`.
- `ConfigModel.parse(text, defaults) -> {config, warning}`: bad JSON →
  `{config: defaults, warning: "<message>"}`.
- `ConfigModel.withWidgetSetting(user, widgetId, key, value) -> object`: a
  new object with `widgets[widgetId][key] = value`, nothing else changed.
- `LayoutModel.modeFor(outputName, cfg) -> "full"|"minimal"`: full when
  `outputName === cfg.primary`, starts with `"eDP"`, or is in `cfg.full`.
- `LayoutModel.widgetsFor(layout, mode) -> {left, center, right}`: Minimal
  keeps only ids listed in `layout.minimal`.
- `ThemeModel.tokens(palette, fallback) -> object` with keys `base, mantle,
  crust, surface, text, subtext, muted, accent, border, borderInactive,
  selection, warning, error`, mapped as the spec says; any role missing or
  not `#RRGGBB` comes from `fallback`.
- `ManifestModel.validate(manifest, apiVersion) -> string[]`: errors for
  wrong `api`, `kind` not in `["bar-widget","service"]`, id not matching
  `^subcult\.[a-z0-9-]+$`, a timer missing `ac` or `battery`, network host
  not a hostname.

- [x] **Step 1: Write `tst_models.qml`** with `TestCase` functions:
  `test_intervalBattery` (900/1800 → 1800000 on battery),
  `test_intervalMissing` (throws), `test_mergeNested`, `test_parseBadJson`
  (Review Focus 2), `test_withWidgetSettingIsolated`, `test_modeFor`
  (`eDP-1` full, `DP-3` minimal, primary `DP-3` full), `test_widgetsMinimal`,
  `test_tokensFallback` (palette with `base: "red"` and no `mauve` → both
  from fallback; Review Focus 1), `test_validate` (one case per error).
- [x] **Step 2:** `make shell-test` → FAIL.
- [x] **Step 3:** Implement the five files.
- [x] **Step 4:** `make shell-test shell-lint` → PASS.
- [x] **Step 5: Commit** `feat(shell): config, power, layout, theme and manifest models`.

### Task 7: Commons singletons

**Files:**
- Create: `shell/Commons/qmldir`, `Theme.qml`, `Power.qml`, `Config.qml`,
  `Style.qml`
- Create: `default/shell/bar.json`

**Interfaces:**
- `Theme` (singleton): one property per `ThemeModel.tokens` key, of type
  `color`. Reads `$SUBCULT_PATH/default/theme/palette.json` as fallback and
  `~/.config/subcult/theme/palette.json` with `FileView { watchChanges: true }`.
  When the user palette changes it starts `subcult cursor apply` detached
  (Task 2b).
- `Power` (singleton): `readonly property bool onBattery` from
  `UPower.onBattery`; `function interval(manifest, timerName): int`.
- `Config` (singleton): `readonly property var bar` (merged);
  `function set(widgetId, key, value)` writes the user file through
  `ConfigModel.withWidgetSetting`; logs `ConfigModel.parse`'s warning once.
- `Style` (singleton): `fontFamily`, `uiFontFamily`, resolved with
  `fc-match -f '%{family[0]}' monospace|sans-serif` in a `Process`, re-run
  when `~/.config/fontconfig/conf.d/60-subcult-fonts.conf` changes;
  `barHeight: 26`, `iconSize`, `spacing`.
- `default/shell/bar.json`: `{ "primary": "", "full": [], "layout": { "left":
  ["subcult.menu","subcult.workspaces","subcult.active-window"], "center":
  ["subcult.indicators","subcult.microphone","subcult.clock",
  "subcult.world-clock","subcult.updates"], "right":
  ["subcult.keyboard-layout","subcult.tray","subcult.audio",
  "subcult.display","subcult.bluetooth","subcult.network",
  "subcult.notifications","subcult.battery"], "minimal":
  ["subcult.workspaces","subcult.display"] }, "widgets": {} }`. Plans 2 and
  3 insert their ids where `sputnik`'s bar has them.

- [x] **Step 1:** Implement the four singletons and `bar.json` (their
  logic is already tested through the Task 6 models).
- [x] **Step 2:** `make shell-lint` → PASS. Task 9's harness adds the
  behaviour check: with a temp `HOME` holding a broken palette and a broken
  `bar.json`, the bar still draws `#100B19` and the log has the one config
  warning (Review Focus 1 and 2).
- [x] **Step 5: Commit** `feat(shell): theme, power, config and style singletons`.

### Task 8: Widget index and loader

**Files:**
- Create: `tools/shell/gen-index.py`, `shell/widgets/index.json`
  (generated, committed), `shell/WidgetHost.qml`
- Modify: `Makefile` (`shell-index-check`: regenerate and `git diff
  --exit-code shell/widgets/index.json`; part of `verify`)

**Interfaces:**
- `gen-index.py` writes `{"api": 0, "widgets": {"<id>": {"dir": "<folder>",
  "manifest": {…}}}}` for every `shell/widgets/*/manifest.json`, sorted;
  exits non-zero on a manifest that fails the same rules as
  `ManifestModel.validate` (duplicated in Python, tested by
  `tools/shell/test_gen_index.py`).
- `WidgetHost.qml`: `property string widgetId`, `property string mode`,
  `property var screen`; loads `widgets/<dir>/Widget.qml` with a `Loader`,
  sets `mode`, `screen`, `settings` and `shell`; owns the popup and loads
  `Panel.qml` only while `panelOpen`. An unknown id renders nothing and logs
  one warning.

- [x] **Step 1:** `test_gen_index.py`: a temp tree with one good and one bad
  manifest → exit 1 naming the bad one; a good tree → expected JSON.
- [x] **Step 2:** `python3 tools/shell/test_gen_index.py` → FAIL.
- [x] **Step 3:** Implement both files.
- [x] **Step 4:** Test passes; `make shell-index-check` passes.
- [x] **Step 5: Commit** `feat(shell): widget index and host`.

### Task 9: Shell root, bar, service and headless harness

**Files:**
- Create: `shell/shell.qml`, `shell/Bar.qml`, `shell/Background.qml`,
  `shell/Ui/IconButton.qml`, `shell/Ui/Tooltip.qml`, `shell/Ui/Popup.qml`
- Create: `default/system/subcult-shell.service`
- Create: `tools/test/shell-headless.sh`
- Modify: `packaging/subarchy/PKGBUILD` (install `shell/` to
  `/usr/share/subcult/shell/`, the unit to `/usr/lib/systemd/user/`, enabled
  through a `graphical-session.target.wants` symlink),
  `tools/test/package-test.sh`, `.gitea/workflows/verify.yml` (new `shell`
  job in `archlinux:latest`: installs `quickshell qt6-declarative sway grim
  imagemagick libnotify`, runs `make shell-test shell-lint` and
  `tools/test/shell-headless.sh`)

**Interfaces:**
- `shell.qml`: `ShellRoot` with `Variants { model: Quickshell.screens }`
  creating one `Bar` per screen and one `Background` per screen;
  `IpcHandler { target: "subcult.shell" }` with `function status(): string`
  returning JSON `{bars: [<output>…], onBattery, intervals: {<id>.<timer>:
  ms}}` (used by Task 16).
- `Bar.qml`: `PanelWindow` anchored top/left/right, `implicitHeight:
  Style.barHeight`, colour `Theme.base`, a 1 px bottom line in
  `Theme.borderInactive`; three `Row`s of `WidgetHost` from
  `LayoutModel.widgetsFor(Config.bar.layout, LayoutModel.modeFor(...))`.
- `Background.qml`: `PanelWindow` on the background layer, `Theme.base`
  fill; shows `/usr/share/backgrounds/subarchy/01-acid-negative-space.png`
  when that file exists.
- `subcult-shell.service`: `ExecStart=/usr/bin/quickshell -n -p
  /usr/share/subcult/shell`, `Environment=QS_NO_RELOAD_POPUP=1`,
  `Restart=on-failure`, `RestartSec=1`, `PartOf=graphical-session.target`,
  `After=graphical-session.target`.
- `shell-headless.sh <shell-dir>`: starts `sway` with
  `WLR_BACKENDS=headless WLR_RENDERER=pixman`, runs Quickshell against the
  shell, waits 5 s, fails on any `ERROR` or `TypeError`/`ReferenceError` in
  its log (Hyprland-socket warnings are allowed outside Hyprland), takes
  `grim` shots, asserts the top 20 rows are mostly `#100B19`, then adds a
  second headless output (`swaymsg create_output`) and asserts
  `qs ipc call subcult.shell status` lists two bars (Review Focus 3). A
  second run with a temp `HOME` holding a broken `palette.json` and
  `bar.json` must still draw `#100B19` and log exactly one config warning.

- [x] **Step 1:** Write `shell-headless.sh` and run it → FAIL (no shell).
- [x] **Step 2:** Implement the root, bar, background and Ui files with no
  widgets yet (empty `widgets/`).
- [x] **Step 3:** `tools/test/shell-headless.sh shell` → PASS; `make package`
  → PASS with the new paths.
- [x] **Step 4: Commit** `feat(shell): root, bar, background and user service`.

Open the Phase C PR; done when the new `shell` CI job is green and it merges.

## Phase D: widgets (PR "feat(shell): core bar widgets")

Each widget is a folder `shell/widgets/<name>/` with `manifest.json`
(`api: 0`, id `subcult.<name>`), `Widget.qml`, an optional pure `Model.js`,
and `tests/tst_<name>.qml` for its model. Regenerate `index.json` in each
commit. Task 10 creates `shell/Commons/Glyphs.js` (Nerd Font codepoints);
later tasks add functions to it. `qmltestrunner` tests cover only `.js`
models, because it cannot host Quickshell types; QML behaviour is checked in
the headless harness.

### Task 10: Hyprland widgets

**Widgets:** `workspaces`, `active-window`, `keyboard-layout`, `display`, `menu`.

**Interfaces:**
- `workspaces/Model.js`: `slots(workspaces, outputName, count) -> [{id,
  occupied, active}]` for ids 1…`count` (10), where `workspaces` is
  `[{id, monitor, windows, active}]` from `Hyprland.workspaces`.
- `keyboard-layout`: last `activelayout` event from `Hyprland.rawEvent`,
  shown as a two-letter code. `display`: a monitor glyph; Minimal bars show
  it as on `sputnik`. `menu`: the SUBCULT mark, no action until the launcher.
- Tests: `test_slotsMarksActiveAndOccupied`, `test_slotsOtherMonitor`
  (another output's workspace is not active here), `test_layoutCode`
  (`"English (US)"` → `"US"`).

- [x] Write failing model tests → run (FAIL) → implement → `make shell-test
  shell-lint shell-index-check` (PASS) → commit
  `feat(shell): workspaces, window, layout, display and menu widgets`.

### Task 11: Device widgets

**Widgets:** `audio`, `microphone`, `network`, `bluetooth`, `battery`, `tray`.

**Interfaces:**
- `Glyphs.js`: `volume(level, muted)`, `microphone(muted)`,
  `wifi(strength)`, `ethernet(connected)`, `bluetooth(enabled,
  connectedCount)`, `battery(percent, charging)` → one-character strings.
- `audio`/`microphone`: `Pipewire.defaultAudioSink` / `defaultAudioSource`
  through `PwObjectTracker`; scroll changes volume by 5 %, click toggles mute.
- `network`: `Networking` devices; wifi strength or ethernet.
- `bluetooth`: `Bluetooth.defaultAdapter`; hidden when there is no adapter.
- `battery`: `UPower.displayDevice`; hidden when `isPresent` is false
  (Review Focus 4); click cycles `PowerProfiles.profile`.
- `tray`: `SystemTray.items`, menus through `QsMenuAnchor`.
- Tests: glyph bands (`battery(5,false) == battery(9,false)`,
  `!= battery(95,false)`, charging differs), `test_batteryHiddenWithoutDevice`
  via `battery/Model.js visible(device)`.

- [x] Failing tests → FAIL → implement → PASS → commit
  `feat(shell): audio, microphone, network, Bluetooth, battery and tray`.

### Task 12: Time, updates and indicators

**Widgets:** `clock`, `world-clock`, `updates`, `indicators`.

**Interfaces:**
- `clock` and `world-clock` share one `SystemClock { precision:
  SystemClock.Minutes }` in `Commons/Clock.qml` (singleton). `clock` format
  `ddd d MMM h:mm AP` as on `sputnik`; `world-clock` reads
  `settings.zones` (list of IANA names, default empty → hidden) and formats
  with `world-clock/Model.js format(date, zone)`.
- `updates`: `FileView` on `~/.local/state/subcult/update-count` with
  `watchChanges`; hidden at 0; click runs `xdg-terminal-exec subcult update`.
- `indicators`: idle inhibit (`IdleInhibitor`, click toggles) and screen
  recording (a PipeWire node whose `media.class` is `Video/Source` with a
  capture client). Task 13 adds the do-not-disturb indicator.
- Manifests: `clock` and `world-clock` have no timers (the singleton's
  minute tick is declared once in `Commons/Clock.qml`'s doc comment and in
  the shell's own budget).
- Tests: `test_formatZone` (`"Asia/Tokyo"` on a fixed UTC date),
  `test_updatesHiddenAtZero`.

- [x] Failing tests → FAIL → implement → PASS → commit
  `feat(shell): clock, world clock, update count and indicators`.

### Task 13: Notifications

**Files:** `shell/services/Notifications.qml` (singleton, `kind: service`
widget `subcult.notifications-daemon`), `shell/widgets/notifications/`
(bar icon with unread count), `shell/NotificationPopups.qml`.

**Interfaces:**
- `services/NotificationsModel.js`: `push(history, n, cap) -> history`
  (newest first, `cap` 100), `shouldPopup(n, dnd) -> bool` (critical always
  pops up), `unread(history) -> number`.
- `Notifications`: `NotificationServer` with actions, images and body markup
  on; `property bool dnd`; history saved to
  `~/.local/state/subcult/notifications.json` on change, at most 100 items.
- Popups: top right of the focused output, `Theme` colours, auto-dismiss 5 s
  (critical stays).
- Adds a do-not-disturb item to `indicators`, shown while `dnd` is on;
  clicking it turns `dnd` off.
- Tests: `test_pushCaps`, `test_dndCriticalStillPopsUp`, `test_unread`.

- [x] Failing tests → FAIL → implement → PASS; in the headless harness,
  `notify-send test` produces a popup layer (`swaymsg -t get_tree` shows it)
  → commit `feat(shell): notification daemon, popups and bar icon`.

### Task 14: OSD and polkit

**Files:** `shell/Osd.qml`, `shell/PolkitDialog.qml`,
`default/hypr/bindings.lua`.

**Interfaces:**
- OSD: `IpcHandler { target: "subcult.osd" }` with
  `function show(kind: string): void` for `"volume"`, `"brightness"`,
  `"capslock"`; also shows on default-sink volume change. Hides after 1.5 s.
- Bindings (all `locked`/`repeating` as Hyprland allows):
  `XF86AudioRaiseVolume`/`Lower`/`Mute` → `wpctl set-volume -l 1.0
  @DEFAULT_AUDIO_SINK@ 5%+` etc.; `XF86MonBrightnessUp`/`Down` →
  `brightnessctl set 5%+` then `qs -p /usr/share/subcult/shell ipc call
  subcult.osd show brightness`; `Caps_Lock` release → `show capslock`.
- Polkit: `PolkitAgent` with a centred dialog on the focused output showing
  `flow.message`, a password field and Cancel/Authenticate; uses
  `flow.submit()` / `flow.cancelAuthenticationRequest()`.
- Tests: `make hypr-check` passes with the new bindings; in the headless
  harness `qs ipc call subcult.osd show volume` creates the OSD layer.

- [x] Write the harness assertions → FAIL → implement → PASS → commit
  `feat(shell): OSD, polkit dialog and media key bindings`.

### Task 15: AltSwitch

**Files:** `shell/widgets/altswitch/` (`kind: service`),
`default/hypr/bindings.lua`.

**Interfaces:**
- `altswitch/Model.js`: `order(clients, focusHistory) -> [address…]` (most
  recently focused first, all workspaces), `next(order, current, step)`.
- `IpcHandler { target: "subcult.altswitch" }`: `next()`, `prev()`,
  `commit()`, `cancel()`. Bindings: `ALT + TAB` → `next`, `ALT + SHIFT +
  TAB` → `prev`, release of `ALT` → `commit`, `Escape` → `cancel`.
- Overlay: a centred row of window titles and app icons; client list read
  only while open.
- Tests: `test_orderRecentFirst`, `test_nextWraps`.

- [x] Failing tests → FAIL → implement → PASS → commit
  `feat(shell): Alt-Tab switcher`.

Open the Phase D PR; done when CI is green and it merges.

## Phase E: VM checks and docs (PR "test: desktop shell checks in the VM")

### Task 16: VM desktop stage, battery mock and idle budget

**Files:** `tools/iso/install-test.py`, `tools/iso/upower-mock.py`,
`tools/iso/idle-budget.json`.

**Interfaces:**
- After the Hyprland checks, `install-test.py` records:
  - `systemctl --user is-active subcult-shell.service` → `active`;
  - `journalctl --user -u subcult-shell -b | grep -cE 'ERROR|TypeError|ReferenceError'` → `0`;
  - a QMP screendump `bar.png` whose top 20 rows contain `#100B19`,
    `#F0ECE4` and `#8F4BC8` (helper `colour_present(png, hex, rows)` in
    `vmlib.py`);
  - `hyprctl layers` lists one `subcult` bar layer per monitor;
  - `fc-match monospace` → `JetBrainsMono Nerd Font`;
  - `gsettings get org.gnome.desktop.interface icon-theme` → `'Papirus-Dark'`.
- `upower-mock.py`: starts `python-dbusmock`'s `upower` template on the
  system bus in the VM (package `python-dbusmock` installed only by the test
  through the 9p cache), flips `OnBattery`; the test reads
  `qs ipc call subcult.shell status` and asserts every interval equals the
  manifest's battery value, then flips back and asserts AC values.
- Idle budget: `/proc/<pid>/status` `voluntary_ctxt_switches` of the shell
  sampled 60 s apart with no input; written to `build/vm/idle.json`. When
  `idle-budget.json` has `null`, the run records the first value and prints
  it for committing; afterwards the check fails above budget × 1.2.

- [ ] Add the checks → run `make install-test` → expected PASS on all new
  checks; commit the measured budget.
- [ ] Commit `test: shell, fonts, battery and idle checks in the VM`.

### Task 17: Docs

**Files:** `docs/decisions/0039-fonts-icons.md` (revision note),
`docs/decisions/0068-shell-plugin-api-v0.md` (`status: accepted`),
`docs/review/triage.md`, `docs/roadmap.md`, `shell/README.md`,
`default/README.md`, `docs/plans/shell-stage-1-core-plan.md` (`status:
accepted`, tasks ticked).

- [ ] Update; `make docs-check` → PASS; commit `docs: shell stage 1 core
  landed`.

Open the Phase E PR; done when CI is green and it merges. Then the owner
checks the result on `sputnik` (scale 1.6, real tray apps, real battery).

## Outcome (2026-11-07)

Executed in one session, one PR per phase, each reviewed by a fresh
reviewer before merge: #21 and #23 (look layer and its fixes), #22
(`subcult font`), #24 (shell core), #25 (widgets and services), and the
Phase E PR (VM checks and these docs). Deviations from this plan, each
recorded as a ruling during the run:

- The cursor builder is Go (`cmd/subcult-cursor`), not a bash script.
- Font roles live in `44-subarchy-roles.conf` with `mode="prepend"`, and the
  user's choices in `~/.config/subcult/fonts.conf`, included first; an
  `alias`/`prefer` file at 50 let Noto's rules win and could not be
  overridden, and `prepend_first` took over named families.
- Neovim's default comes from a site plugin; `neovim` owns
  `/etc/xdg/nvim/sysinit.vim`.
- Widgets get `shell.power` and `shell.config` bound to themselves and are
  created with initial properties; `WidgetTimer` is the only widget timer;
  `WatchedFile` makes user files written after start apply live.
- With no primary output and no laptop panel, the first output gets the
  full bar.
- Services that are not bar items (notifications, OSD, polkit, Alt-Tab) live
  in the shell, not as `kind: service` widgets.
- Hyprland dispatches are Lua expressions (Subarchy's Hyprland config is
  Lua); the OSD's IPC call is `flash`, not `show`.
- No Caps Lock binding and no global Escape binding (both would take the key
  from apps).
- The VM test (Task 16) mocks UPower inline with `python-dbusmock` from the
  mirror and restarts the shell to read it, asserts `onBattery` rather than
  per-widget battery intervals (no plan-1 widget has a timer), checks the
  bar's own line colour instead of the window border, matches errors rather
  than every warning, and counts idle wake-ups over all the shell's threads.

Not verified by the tests: the Alt release key binding with a real
keyboard, the polkit retry flow, HiDPI at scale 1.6 and real tray apps; the
owner checks those on `sputnik`.

Related: [[shell-and-look-design|Shell and look design]] · [[0068-shell-plugin-api-v0|ADR 0068]] · [[roadmap|Roadmap]]
