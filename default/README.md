# default

System defaults read at runtime rather than copied
([ADR 0048](../docs/decisions/0048-config-ownership.md)). The package installs
this directory to `/usr/share/subcult/default/`. Omarchy counterpart:
`/usr/share/omarchy/default/`.

| Path | What |
|---|---|
| `apps.toml` | App catalogue read by `subcult app` (ADR 0044) |
| `hypr/` | Hyprland Lua defaults (ADR 0032). `user-hyprland.lua` is the user's `~/.config/hypr/hyprland.lua` as the installer writes it: it runs `bootstrap.lua`, loads `subcult.lua`, then the user's overrides. Helpers live in the global `sub` table (`sub.bind`, `sub.launch`, `sub.alias` for a launcher alias's hotkey). |
| `theme/subcult-minimal.json` | The default theme, `subcult-minimal`, in Pult's palette-file format (schema 1, 26 roles, ANSI 0–15, terminal specials); what `pult apply` reads (ADR 0037) |
| `theme/subarchy.toml` | The Pult profile the installer applies for a new user (`pult apply -profile`): the default theme, every installed app |
| `theme/palette.json` | The shell's palette, generated from `subcult-minimal.json` by `tools/theme/gen-palette.py` (`make verify` checks they agree); the user's `~/.config/subcult/theme/palette.json` overrides roles |
| `shell/bar.json` | The bar layout; the user's `~/.config/subcult/shell/bar.json` overrides keys. `primary` and `full` name outputs by connector (`DP-3`) or by part of the monitor's description (`LG ULTRAGEAR`), so a monitor keeps its Full bar when it moves to another connector |
| `chromium/extensions/` | Chromium external extension files (→ `/usr/share/chromium/extensions/`): Vencord Web for the Discord web app (ADR 0042) |
| `chromium/policies/managed/color.json` | Chromium's frame colour for the default theme (→ `/etc/chromium/policies/managed/`); `subcult theme apply-system` replaces it with the user's (ADR 0037) |
| `shell/workspaces.json` | Workspace names: `{"workspaces": [{"id": 3, "name": "Workbench", "short": "WRK"}]}`; the user's `~/.config/subcult/shell/workspaces.json` replaces entries by id. The bar shows the token (or the number), the OSD shows the name on a switch |
| `shell/zshrc`, `shell/bashrc`, `shell/aliases.sh`, `shell/functions.sh`, `shell/starship.toml` | The interactive shell setup (ADR 0041), sourced by the user's `~/.zshrc` and `~/.bashrc`: aliases and functions for both shells (files through eza and fzf, git shortcuts, the coding agents, `y` for yazi, `ga`/`gd` worktrees, `fip`/`dip`/`lip` port forwards, the `tdl`/`tdlm`/`tsl` tmux layouts, `compress`), starship with this prompt until the user has `~/.config/starship.toml`, atuin on Ctrl-R, zoxide behind `cd`, fzf keys, mise. `shell/completions/` completes the `subcult` command in both shells from the `subcult-*` programs on `PATH` |
| `launcher/snippets.json` | The launcher's default snippets; the user's `~/.config/subcult/launcher/snippets.json` adds to them (ADR 0057) |
| `launcher/quicklinks.json` | The launcher's web search engines and quicklinks; the user's `~/.config/subcult/launcher/quicklinks.json` adds or replaces them by keyword (ADR 0057) |
| `launcher/favorites.json` | The launcher's home-screen favorites, by desktop entry id; the user's `~/.config/subcult/launcher/favorites.json` replaces the list (ADR 0057) |
| `fontconfig/` | The three font roles (→ `/usr/share/fontconfig/conf.avail/`, linked from `/etc/fonts/conf.d/`); includes the user's `~/.config/subcult/fonts.conf` first |
| `cursor/` | The Subarchy cursor's SVG shapes and `shapes.tsv`; `subcult cursor` builds them (the package ships the lavender theme in `/usr/share/icons/subcult-cursor/`) |
| `gtk/` | GSettings override (→ `/usr/share/glib-2.0/schemas/`) and GTK 3/4 `settings.ini` (→ `/etc/xdg/`); theme adw-gtk3-dark, which takes Pult's colours (ADR 0037) |
| `kde/` | `kdeglobals` (→ `/etc/xdg/`) selecting the `Pult` colour scheme for KDE apps, and `Pult.colors` (→ `/usr/share/color-schemes/`), the default theme's copy until `pult apply` writes the user's (ADR 0037) |
| `kitty/` | kitty's system config and the Subcult Ink colours (→ `/etc/xdg/kitty/`) |
| `nvim/` | Subcult Ink for Neovim (→ `/usr/share/nvim/site/`) |
| `system/` | systemd units, drop-ins and rules, including `subcult-shell.service` |
| `polkit/` | The polkit action for `subcult theme apply-system` (ADR 0037, 0062) |
| `sddm/` | SDDM greeter running in Hyprland (`subarchy.conf` → `/usr/lib/sddm/sddm.conf.d/`), the greeter's compositor config, and the `SUBCULT` session file (→ `/usr/share/wayland-sessions/`) that starts Hyprland through uwsm (ADR 0030, 0031). |
| `pacman/snapshot` | The stable channel's Arch Linux Archive snapshot date (ADR 0026) |
| `pam/` | The lock's password and fingerprint PAM stacks (→ `/etc/pam.d/`, ADR 0036) |
| `plymouth/` | The boot splash theme (→ `/usr/share/plymouth/themes/subarchy/`, ADR 0013) |
| `security/faillock.conf` | pam_faillock settings the installer copies to `/etc/security/` (ADR 0063) |

`subcult theme apply-system` applies the user's palette to SDDM, Plymouth, Limine and Chromium (ADR 0037).

Check the Hyprland configs with `SUBCULT_PATH=$PWD Hyprland --verify-config -c default/hypr/user-hyprland.lua`.
