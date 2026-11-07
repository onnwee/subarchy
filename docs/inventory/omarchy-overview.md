# Omarchy component map

Observed on `sputnik` with Omarchy `4.5.0-3`. Upstream source:
<https://github.com/omacom/omarchy> (MIT). Full tables are in
[`generated/omarchy/`](generated/omarchy/).

## How Omarchy is delivered

Omarchy 4.x is a set of pacman packages, not a dotfiles script:

| Package | Contents |
|---|---|
| `omarchy` | `/usr/share/omarchy` (config templates, defaults, shell, themes, install scripts, migrations) and the `omarchy-*` commands in `/usr/bin`. Depends on Hyprland, Quickshell, uwsm, SDDM, Limine, snapper and others. |
| `omarchy-settings` | `/etc/skel` content, fonts, the Plymouth theme and support helpers. Built from the same repository. |
| `omarchy-keyring` | Signing keys for the `[omarchy]` repository. |
| `omarchy-themes-intros` | Background intro videos for stock themes. |
| `linux-omarchy`, `linux-omarchy-headers` | Kernel with the BORE CPU scheduler and ADIOS I/O scheduler. |
| `omarchy-nvim` | Prebuilt LazyVim configuration with cached plugins. |
| `omarchy-hyprland-titlebars` | Titlebars for floating workspaces. |
| `omarchy-power-profiles-daemon` | power-profiles-daemon with extra CPU profiles. |
| `omarchy-speedtest` | Network speed test client. |

The `[omarchy]` repository at `https://pkgs.omarchy.org/stable/$arch` carries
256 packages. Most are AUR or third-party packages rebuilt so users never need an
AUR helper ([list](generated/omarchy/repo-packages.md)). `omarchy channel set`
switches the package channel.

Updates run `omarchy update`, which upgrades packages and then applies
timestamped migrations from `migrations/` (218 in 4.5.0). Pacman hooks guard
updates and pause Hyprland reloads during a transaction.

## Layers

| Layer | Components | Where configured |
|---|---|---|
| Boot | Limine, `limine-snapper-sync` (snapshot boot entries), Plymouth, mkinitcpio | `default/limine`, `default/plymouth`, `etc-overrides/` |
| Login and session | SDDM with an Omarchy theme, uwsm session manager | `default/sddm`, `default/uwsm` |
| System | btrfs with snapper, ufw and `ufw-docker`, NetworkManager, PipeWire and WirePlumber, bluez, CUPS, Avahi, zram, fcitx5 input methods | `install/config/`, `default/systemd` |
| Compositor | Hyprland configured in Lua (`hyprland.lua`, `bindings.lua`, `looknfeel.lua`, `monitors.lua`, `input.lua`, `autostart.lua`), hyprsunset, hyprpicker | `default/hypr`, user copies in `config/hypr` |
| Shell | Quickshell program `shell/shell.qml` with 32 plugins: bar, menu/launcher, notifications, OSD, lock, idle, dock, clipboard, emojis, polkit agent, reminders, image picker, and panels for audio, Bluetooth, network, power, weather, Tailscale, Dropbox, speed tests and world clock | `config/omarchy/shell.json`, `config/omarchy/extensions/omarchy-menu.jsonc` |
| Theming | 24 themes; each is a `colors.toml` plus backgrounds. `default/themed/*.tpl` renders matching configs for Alacritty, Foot, Ghostty, Kitty, btop, Chromium, Hyprland, Neovim, Helix, VS Code, Obsidian, fcitx5, keyboard RGB, the shell and several agent CLIs | `themes/`, `default/themed/` |
| Commands | 556 `omarchy-*` commands in 85 groups behind one `omarchy` dispatcher | `/usr/bin/omarchy-*` |
| Hardware | Fixes and setup for Apple T2 and Apple Silicon, ASUS, Dell XPS, Framework, Lenovo, Surface, Tuxedo, Intel, NVIDIA, Qualcomm and NVIDIA GB10/N1X | `install/hardware/`, `omarchy hw …` |
| Agents | `omarchy agent …` signs in Claude, Codex and Grok subscriptions and manages accounts; the `omarchy.agents` bar widget shows usage and limits; `default/agents/skills` ships agent skills | `default/agents` |

## Default applications

From `omarchy-base.packages` (162 entries). Omarchy-built or Omarchy-distributed
apps are marked with *.

| Category | Applications |
|---|---|
| Terminal and shell | Foot (default), Alacritty, Ghostty and Kitty templates, bash, starship, tmux, zoxide, fzf, eza, bat, ripgrep, fd, tldr, `ttfx`* |
| Editors and writing | Neovim with `omarchy-nvim`*, Obsidian, `omawrite`* (Markdown), LibreOffice, `hype`* (Markdown slides) |
| Files and disks | Nautilus with sushi previews, `disktree`* (treemap), GNOME Disks, udiskie, LocalSend |
| Media | mpv, imv, `cliamp`* (terminal music player), `omacut`* (video trimmer), `monologue`* (webcam recorder), gpu-screen-recorder, yt-dlp |
| Images and capture | Pinta, `omasnap`* (screenshot and annotation), grim, slurp, hyprpicker, tesseract OCR, zbar |
| Wallpaper and theming | `owe`* (video/GIF wallpaper engine), `aether`* (theme builder from wallpapers), `omarchy-themes-intros`* |
| Utilities | `omacalc`*, `signed`* (PDF signing), btop, fastfetch, Evince, `tobi-try`*, `gliff`* (Hyprland remote desktop over SSH), Moonlight |
| Browser | Chromium, with Chromium policy and theme templates |
| Development | Docker with buildx and compose, mise, lazygit, base-devel, Ruby, Lua, `tree-sitter-cli` |
| Dictation | `superwhisper-bin` (listed, not installed on `sputnik`), voxtype configuration under `default/voxtype` |

Web apps and default launchers in `applications/`: Basecamp, Discord, Google
Contacts, Google Maps, Google Messages, Google Photos, HEY, WhatsApp, X, YouTube,
Zoom, plus Foot, imv, mpv and the Omarchy browser launcher.

Optional software is installed through `omarchy install …` (46 commands) and
removed through `omarchy remove …` (35 commands). `omarchy-other.packages`
lists what those commands and the hardware fixes can pull in.

## Command groups

The largest groups ([full list](generated/omarchy/commands.md)):

| Group | Commands | Purpose |
|---|---:|---|
| `install` | 46 | Optional software, languages, databases, editors, games |
| `hw` | 42 | Hardware detection and per-vendor fixes |
| `theme` | 40 | Theme set, install, backgrounds, switchers |
| `agent` | 38 | AI agent accounts and usage |
| `remove` | 35 | Remove optional software |
| `hyprland` | 30 | Window, workspace and layout actions |
| `launch` | 24 | Launch apps, browser, terminal, web apps |
| `update` | 23 | System, firmware and component updates |
| `toggle`, `restart` | 16 each | Feature toggles and service restarts |
| `menu` | 13 | Menus and pickers |
| `refresh`, `dev` | 12 each | Reset configs to defaults; Omarchy development |

## Extension points Omarchy supports

These let a distribution add behaviour without editing packaged files:

| Mechanism | Location | Notes |
|---|---|---|
| User shell plugins | `~/.config/omarchy/plugins/<id>/manifest.json` | Kinds: `bar`, `bar-widget`, `panel`, `overlay`, `service`, `menu`. `omarchy plugin clone` copies a built-in plugin for editing. |
| Hooks | `~/.config/omarchy/hooks/<event>.d/` | Every non-`.sample` file runs with `bash`. Events seen: `post-boot`, `post-update`, `theme-set`, `font-set`, `battery-low`, `pre-refresh-pacman`. |
| Menu extensions | `~/.config/omarchy/extensions/omarchy-menu.jsonc` | Hot-reloaded. |
| User themes | `~/.config/omarchy/themes/<name>/` | Same layout as stock themes; a directory with a stock name overlays that theme. |
| Branding | `omarchy branding about`, `omarchy branding screensaver`, `omarchy plymouth set` | User-level About text, screensaver text and Plymouth colours/logo. |
| Hyprland | `~/.config/hypr/*.lua` | Sources Omarchy defaults from `default/hypr`, then user files. |

What these cannot change: files owned by the `omarchy` and `omarchy-settings`
packages, the SDDM and Limine themes, the `omarchy` command namespace, the ISO
and the package repository. The `omarchy-settings` install script also copies
`etc-overrides/` over `/etc/os-release`, `/etc/plymouth/plymouthd.conf`,
`/etc/nsswitch.conf`, `/etc/security/faillock.conf`, `/etc/skel/.bashrc` and
the CUPS configs on every upgrade; its own comment calls this "intentionally
destructive". See [branding surfaces](branding-surfaces.md).
