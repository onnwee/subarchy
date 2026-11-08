# default

System defaults read at runtime rather than copied
([ADR 0048](../docs/decisions/0048-config-ownership.md)). The package installs
this directory to `/usr/share/subcult/default/`. Omarchy counterpart:
`/usr/share/omarchy/default/`.

| Path | What |
|---|---|
| `apps.toml` | App catalogue read by `subcult app` (ADR 0044) |
| `hypr/` | Hyprland Lua defaults (ADR 0032). `user-hyprland.lua` is the user's `~/.config/hypr/hyprland.lua` as the installer writes it: it runs `bootstrap.lua`, loads `subcult.lua`, then the user's overrides. Helpers live in the global `sub` table (`sub.bind`, `sub.launch`, `sub.alias` for a launcher alias's hotkey). |
| `theme/subcult-minimal.json` | The default theme, `subcult-minimal`, in Theme Tender's palette-file format (schema 1, 26 roles, ANSI 0–15, terminal specials); what `tender apply` reads (ADR 0037) |
| `theme/palette.json` | The shell's palette, generated from `subcult-minimal.json` by `tools/theme/gen-palette.py` (`make verify` checks they agree); the user's `~/.config/subcult/theme/palette.json` overrides roles |
| `shell/bar.json` | The bar layout; the user's `~/.config/subcult/shell/bar.json` overrides keys. `primary` and `full` name outputs by connector (`DP-3`) or by part of the monitor's description (`LG ULTRAGEAR`), so a monitor keeps its Full bar when it moves to another connector |
| `launcher/snippets.json` | The launcher's default snippets; the user's `~/.config/subcult/launcher/snippets.json` adds to them (ADR 0057) |
| `launcher/quicklinks.json` | The launcher's web search engines and quicklinks; the user's `~/.config/subcult/launcher/quicklinks.json` adds or replaces them by keyword (ADR 0057) |
| `launcher/favorites.json` | The launcher's home-screen favorites, by desktop entry id; the user's `~/.config/subcult/launcher/favorites.json` replaces the list (ADR 0057) |
| `fontconfig/` | The three font roles (→ `/usr/share/fontconfig/conf.avail/`, linked from `/etc/fonts/conf.d/`); includes the user's `~/.config/subcult/fonts.conf` first |
| `cursor/` | The Subarchy cursor's SVG shapes and `shapes.tsv`; `subcult cursor` builds them (the package ships the lavender theme in `/usr/share/icons/subcult-cursor/`) |
| `gtk/` | GSettings override (→ `/usr/share/glib-2.0/schemas/`) and GTK 3/4 `settings.ini` (→ `/etc/xdg/`) |
| `kitty/` | kitty's system config and the Subcult Ink colours (→ `/etc/xdg/kitty/`) |
| `nvim/` | Subcult Ink for Neovim (→ `/usr/share/nvim/site/`) |
| `system/` | systemd units, drop-ins and rules, including `subcult-shell.service` |
| `sddm/` | SDDM greeter running in Hyprland (`subarchy.conf` → `/usr/lib/sddm/sddm.conf.d/`), the greeter's compositor config, and the `SUBCULT` session file (→ `/usr/share/wayland-sessions/`) that starts Hyprland through uwsm (ADR 0030, 0031). |

Still to come: Plymouth, Limine and SDDM theming, Theme Tender templates.

Check the Hyprland configs with `SUBCULT_PATH=$PWD Hyprland --verify-config -c default/hypr/user-hyprland.lua`.
