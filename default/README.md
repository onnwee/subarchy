# default

System defaults read at runtime rather than copied
([ADR 0048](../docs/decisions/0048-config-ownership.md)). The package installs
this directory to `/usr/share/subcult/default/`. Omarchy counterpart:
`/usr/share/omarchy/default/`.

| Path | What |
|---|---|
| `apps.toml` | App catalogue read by `subcult app` (ADR 0044) |
| `hypr/` | Hyprland Lua defaults (ADR 0032). `user-hyprland.lua` is the user's `~/.config/hypr/hyprland.lua` as the installer writes it: it runs `bootstrap.lua`, loads `subcult.lua`, then the user's overrides. Helpers live in the global `sub` table (`sub.bind`, `sub.launch`). |
| `sddm/` | SDDM greeter running in Hyprland (`subarchy.conf` → `/usr/lib/sddm/sddm.conf.d/`), the greeter's compositor config, and the `SUBCULT` session file (→ `/usr/share/wayland-sessions/`) that starts Hyprland through uwsm (ADR 0030, 0031). |

Still to come: Plymouth, Limine theming, theme templates (`themed/*.tpl`),
systemd user units for the shell.

Check the Hyprland configs with `SUBCULT_PATH=$PWD Hyprland --verify-config -c default/hypr/user-hyprland.lua`.
