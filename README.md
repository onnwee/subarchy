# Subarchy

Subarchy is an Arch Linux desktop distribution from SUBCULT. It runs
Hyprland with its own Quickshell desktop shell, lock screen and theme, and is
managed through one command, `subcult`. It is built from scratch, borrowing
from [Omarchy](https://omarchy.org/) where it fits. Subarchy is the
distribution's name; on screen it shows SUBCULT
([ADR 0052](docs/decisions/0052-name-identity.md)).

Subarchy is in development and has no release yet. The live ISO builds in CI,
boots in a VM and installs from that image into an encrypted VM disk. Hardware
fixes are not yet tested on real machines, and several shell, launcher and
theming items on the [roadmap](docs/roadmap.md) are still open.

## Features

- **Live ISO** built with archiso: UEFI only, systemd-boot, `linux-zen`.
- **Guided installer** (`subarchy-setup`): asks for keyboard layout, disk,
  computer name, user, password, disk passphrase and time zone, checks each
  answer, shows what is on each disk (and can open it read-only) and asks
  before it wipes one. It can
  install with no network from the package repository on the image.
- **Installed system**: GPT with a FAT32 ESP and a LUKS2 root, btrfs
  subvolumes with zstd compression, one unified kernel image per kernel,
  Limine with a boot entry per snapper snapshot, a read-only factory-reset
  snapshot, zram swap, ufw, AppArmor, systemd-resolved with DNS over TLS,
  PipeWire, SDDM and Hyprland under uwsm. See [install/README.md](install/README.md).
- **Updates** (`subcult update`): snapshot, package upgrade, migrations and
  cleanup. A new system follows the stable channel (a dated Arch Linux Archive
  snapshot); `subcult channel set edge` follows the Arch mirrors directly.
- **Desktop shell** in Quickshell: a bar with event-driven widgets (workspaces,
  audio, network, Bluetooth, battery and power profiles, calendar, weather,
  media, tray, updates and more), notifications, on-screen display, polkit
  dialog, Alt-Tab switcher and launcher. See [shell/README.md](shell/README.md).
- **Lock screen** as a separate program, so a shell crash cannot unlock the
  session. See [lock/README.md](lock/README.md).
- **Theming**: one palette applied to the shell, lock screen, terminal,
  Neovim, cursor, SDDM, Plymouth and Limine, with Pult as the theme tool
  ([ADR 0037](docs/decisions/0037-theming.md)).
- **`subcult` commands**, discovered from `subcult-*` programs on the path.
  `subcult commands` lists them. Groups include `app` (catalogue install,
  remove and default apps), `font`, `cursor`, `display` (scale and saved
  monitor layouts), `clipboard` (history), `calendar` (CalDAV and iCal sync),
  `idle`, `hw` (hardware detection and fixes), `gpu`, `secureboot`,
  `disk tpm`, `thermal`, `channel`, `update` and `system`.

## Quick start

The Go tools need Go (version in [go.mod](go.mod)), `shellcheck` and Python 3.

```bash
make verify     # gofmt, go vet, race tests, build, smoke tests, shellcheck, docs and theme checks
make build      # binaries in build/
```

Other targets:

| Target | Needs | Does |
|---|---|---|
| `make package` | Arch Linux | Builds the `subarchy` pacman package and checks its contents |
| `make shell-test shell-lint shell-index-check` | `qt6-declarative`, `quickshell` | Tests and lints the QML shell and lock screen |
| `make shell-native-test` | `quickshell`, `qt6-declarative`, `librsvg`, `imagemagick`, `python` | Draws the panels, greeter and lock offscreen and checks them; screenshots go to `build/*-preview/` |
| `make iso` | `archiso`, sudo | Builds the live ISO into `build/iso/` |
| `make iso-test` | `qemu-base`, `edk2-ovmf` | Boots the newest ISO in QEMU and checks it over the serial console |
| `make install-test` | `qemu-base`, `edk2-ovmf` | Installs from the newest ISO into a VM disk, then boots and checks the result |
| `make install-test-offline` | `qemu-base`, `edk2-ovmf` | The same through the guided installer with the guest's network off |

`tools/test/shell-headless.sh shell` runs the shell in a private headless
sway session. Details are in [iso/README.md](iso/README.md) and
[install/README.md](install/README.md).

## Trying it

There is no published image. To try Subarchy, build the ISO with `make iso`
and install it into a virtual machine, or run `make install-test`. The
installer wipes the disk you choose, so do not point it at a disk you need.

## Configuration

User settings live under `~/.config/subcult/`; the palette Pult writes is
`~/.config/subcult/theme/palette.json`. Hyprland reads the user's
`~/.config/hypr/hyprland.lua` on top of the shipped defaults in
[default/](default/). The app catalogue is [default/apps.toml](default/apps.toml); `subcult app validate`
validates it and any user catalogue.

`subarchy-install` reads a `KEY=value` file: `DISK`, `HOSTNAME`, `USERNAME`,
`USER_PASSWORD_FILE`, `LUKS_PASSPHRASE_FILE`, `TIMEZONE`, `LOCALE`, `KEYMAP`,
`XKB_LAYOUT`, `XKB_VARIANT`, `SUBARCHY_REPO` and others listed in the header of
[install/subarchy-install](install/subarchy-install). It needs `--yes`
because it wipes `DISK`.

## Project layout

The top-level directories follow Omarchy's packaged tree, so upstream files
can be compared path for path.

```text
applications/  desktop entries
bin/           subcult-* shell commands
branding/      backgrounds, marks, fonts, os-release, screensaver
cmd/           Go commands (subcult, subarchy-setup, subcult-*)
internal/      Go packages behind the commands
config/        user config templates
default/       system defaults (Hyprland, SDDM, Plymouth, theme, app catalogue)
install/       installer script and package lists
iso/           archiso profile
lock/          lock screen (Quickshell)
migrations/    upgrade migrations
packaging/     PKGBUILDs: subarchy, keyring, Neovim, pinned AUR rebuilds
shell/         desktop shell (Quickshell)
themes/        themes
tools/         build, test, ISO, theme and inventory scripts
docs/          decisions, inventory, brand notes and roadmap
```

## Documentation

[docs/](docs/home.md) is an Obsidian vault. Notes use frontmatter and
wikilinks, which GitHub shows as plain text, so Obsidian reads them better:

```bash
python3 tools/obsidian/install-plugins.py   # pinned, hash-checked plugins
```

Then open the repository folder with **Open folder as vault**.
[Vault conventions](docs/vault-conventions.md) covers properties, links and
templates. The [decision records](docs/decisions/decisions-index.md) explain
the design choices.

`python3 tools/inventory/collect.py`, run on an Omarchy machine, regenerates
the Omarchy inventory in `docs/inventory/generated/`.

## Contributing

Report bugs and request features in
[GitHub issues](https://github.com/subculture-collective/subarchy/issues).
For code, open a pull request on GitHub against `main`. CI runs `make verify`, builds
and checks the pacman package in an Arch container, and runs the shell tests,
lint and a headless shell session on every pull request; all must pass before
it merges.

## License

GPL-3.0-or-later; see [LICENSE](LICENSE) and
[ADR 0053](docs/decisions/0053-licence.md). Code borrowed from Omarchy (MIT)
and the LazyVim starter (Apache-2.0) keeps its original licence notices.
