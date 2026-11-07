# Additions beyond Omarchy on `sputnik`

Snapshot 2026-11-06. Full tables are in [`generated/local/`](generated/local/).
This page groups them by purpose so they can be reviewed for the distribution.

`sputnik` carries three kinds of additions, and they need different treatment:

1. **Distribution candidates**: plugins, themes and tools that could ship to
   every Subcarchy user.
2. **Owner preferences**: apps and settings for one person's workflow. These
   belong in an optional profile, not the default image.
3. **Host fixes**: workarounds for this laptop's docks, monitors and power
   behaviour. These stay out of the distribution unless they generalise.

## Shell plugins (86 directories)

### Own plugins (9)

Source repositories are under `~/Work/Tools/`.

| Plugin | What it does | In `shell.json` | Notes |
|---|---|---|---|
| `patrickfanella.monitor-bar` | Full, Minimal or Hidden bar per monitor; it is the active `bar.id` | yes | Source `git.subcult.tv/PatrickFanella/omarchy-monitor-bar`. Depends on the user shell overlay patch (see host fixes). |
| `onnwee.monitor-bar` | Earlier per-monitor bar | no | Superseded by `patrickfanella.monitor-bar`. |
| `io.github.patrickfanella.shelfish` | Collapsible groups of bar widgets, ten languages | no | Source `omarchy-plugin-shelfish`. |
| `patrickfanella.superproductivity` | Super Productivity tasks in the bar | no | Source `omarchy-superproductivity`; needs the custom Super Productivity build. |
| `patrickfanella.ht3` | TOZO HT3 headphone volume, EQ, ANC | yes | Hardware-specific. |
| `onnwee.switchyard` | Read-only Switchyard and Open Pilot status | yes | Homelab-specific. |
| `onnwee.gitea-pipelines` | Gitea Actions status for `git.subcult.tv` | no | Homelab-specific. |
| `onnwee.spool` | Cassette companion that follows T3 Code sessions | no | Source `omarchy-plugin-spool`. |
| `onnwee.command-palette` | Curated apps, Omarchy commands, calculator | no | Overlaps `subcult.command-palette` and the stock menu. |

### SUBCULT rice plugins (38)

All `subcult.*` plugins come from
[`subcult-omarchy-rice`](subcult-rice.md). None is referenced in the current
`shell.json`: the bar moved to `patrickfanella.monitor-bar` with stock and
community widgets on 2026-11-02, and the SUBCULT layout was kept as
`shell.subcult.json` and `shell.json.bak.subcult-plugins-20261102-195151`. The
`theme-set` and `post-update` hooks from the rice still run.

### Community plugins (39)

Grouped by function. **Bold** ids are referenced in `shell.json`.

| Function | Plugins |
|---|---|
| Bar organisation | `leyanora.plugincontainers`, `io.github.salemsayed.omatender` |
| Plugin management | **`omaplug`**, `io.github.weedwhitesandwine.plug`, **`shell.settings`** |
| Window and workspace switching | **`io.github.pablo-merino.altswitch`**, `io.github.thebenwalther.switchboard`, `io.github.chinofmaya.spaces`, `io.github.agata.omasets`, `burninc0de.dock` |
| Notifications | **`foamy.notification-center`**, `shavanced.notification-center`, `dailen.omartfy` (ntfy) |
| Calendar, time, weather | **`tmn73.calendar`**, **`ashuttl.linecast`**, `eduardodallecort.weather-radar` |
| Media | **`io.github.joshuaswarren.somafm`**, `ky.navidrome-remote`, **`ussego.otoru`** (yt-dlp downloads) |
| Wallpaper, lock, cursor, theme | **`dizziee.auto-wallpaper`**, **`io.github.sirjul1337.lock-explorer`**, `taxin.cursor-style`, `davies-sam.omatheme` |
| Security | **`io.github.elevate08.qs-bitwarden-cli`** |
| System and services | `harshith.system-monitor`, `io.github.rickycbanks.osystemd`, `io.github.randazraik.xray`, `devgtv.docker`, `com.github.linuxgameruk.ollama-status`, `yashwanth.link` (network hub) |
| Homelab | **`legendik.n8n`**, `io.github.luccast.omarr` (Arr stack) |
| Hardware | **`stappmus.dell-power-profiles`**, `io.github.thisisgm.omapods` (AirPods), `io.github.chernicharo.voxtype-mode` |
| Notes | `rperaza.obsidian-notes`, `mateuszkowalczyk.obsidian-quick-switcher` |
| Learning | `omakey` (shows the keybinding you could have used) |
| Novelty | `io.github.roman.ovaxry` |

Two built-in plugins are disabled in `shell.json`: `omarchy.battery` and
`omarchy.lock`. The Dell power panel and `lock-explorer` appear to replace them;
the reason was not recorded.

## Themes (10)

| Theme | Origin | Notes |
|---|---|---|
| `subcult`, `subcult-minimal` | SUBCULT rice | `subcult-minimal` is current. |
| `evangelion` | Former Evangelion rice | Predecessor of the SUBCULT theme. |
| `kvant-sputnik`, `kvant-tty` | Local, no origin | Fleet host themes; 61 files each. |
| `01`, `event-horizon`, `flat-dracula`, `omarchy` | OldJobobo on GitHub | `omarchy` here is a user theme of that name, not the stock default. |
| `saga` | HANCORE-linux on GitHub | |

## Hooks (9 active, 8 added)

| Event | Scripts | Source |
|---|---|---|
| `post-boot` | `subcult-boot-sequence.hook` | rice |
| `post-update` | `90-restore-subcult`, `setup-agent.hook` | rice; Omarchy's default-agent invitation |
| `theme-set` | `00-subcult-plugins.hook`, `subcult-affinity.hook`, `subcult-terminal-profile.hook` | rice |
| `theme-set` | `10-owe-sync`, `90-omarchy-01-shell-integrations`, `95-sputnik-power-profile` | wallpaper engine sync, `01` theme, host power profile |

`90-restore-subcult` re-applies the rice after each Omarchy update. It shows
the cost of the overlay approach: every upstream update can undo local changes.

## Commands and scripts in `~/.local/bin`

| Group | Count | Examples |
|---|---:|---|
| SUBCULT rice | 61 | `subcult-settings`, `subcult-scene`, `subcult-workspaces`, `subcult-update`, `subcult-rice-health` |
| Desktop overrides | 8 | `omarchy-shell`, `omarchy-launch-shell`, `omarchy-restart-shell`, `omarchy-shell-overlay-sync`, `omarchy-launch-terminal`, `omarchy-launch-screensaver`, `omarchy-screensaver`, `hyprctl` |
| Host helpers | 7 | `sputnik-dock-workspaces`, `sputnik-idle-display`, `sputnik-idle-suspend`, `sputnik-power-profile`, `sputnik-power-profile-watch`, `sputnik-opencode-tasks`, `scrolling-view-toggle` |
| mise shims | 18 | `claude`, `codex`, `opencode`, `gh`, `rtk`, `tea`, `uv` |
| Other | 27 | `tadooer-*`, `t3-nightly`, `sp-mcp`, `gpu-run`, `librepods`, `subsets`, `sync-omarchy-to-kvant` |

The `omarchy-*` files in `~/.local/bin` shadow packaged commands of the same
name. `omarchy-shell-overlay-sync` regenerates a patched copy of the packaged
shell under `~/.local/share/omarchy-shell-overlay` so plugin service access and
monitor-bar saving work. A distribution would carry these patches in its own
shell source instead.

## User services (15 unit files)

| Unit | Purpose | Kind |
|---|---|---|
| `subcult-affinity.path`/`.service`, `subcult-start-page.service`, `subcult-topology.service` | Rice palette, start page and monitor topology | rice |
| `sputnik-dock-workspaces.service` | Assigns workspaces 1-10 across docked monitors | host fix |
| `sputnik-idle.service`, `sputnik-power-profile.service` | Idle display-off/suspend and AC/battery profiles | host fix |
| `voxtype.service` | Dictation daemon | candidate |
| `tmux.service` | Persistent tmux server | preference |
| `omarchy-calendar-sync.service`/`.timer` | Runs the `tmn73.calendar` plugin's sync script | plugin support |
| `omarchy-homelab-tunnels.service` | Homelab tunnels | homelab |
| `opencode-tasks.service`/`.timer` | OpenCode task runner | preference |
| `dev.mise.mise-history.service` | mise config history | preference |

## Packages (179 explicit, outside Omarchy's lists)

Some of these were installed by Omarchy's own `omarchy install` and font
commands; check against `omarchy-other.packages` before treating them as
personal choices.

| Category | Packages |
|---|---|
| Browsers and communication | `zen-browser-bin`, `vivaldi`, `signal-desktop`, `vesktop`, `proton-mail`, `protonmail-bridge`, `halloy`, `chatterino2-nightly-bin`, `streamlink`, `streamlink-twitch-gui` |
| AI and development apps | `claude-desktop`, `claude-code`, `openai-codex-desktop`, `visual-studio-code-bin`, `helix`, `micro`, `neovim`, `podman`, `podman-desktop`, `lazydocker`, `ollama`, `ollama-cuda`, `clang`, `llvm`, `go-task`, `pnpm`, `shellcheck`, `tea`, `google-cloud-cli`, `googleworkspace-cli-bin`, `twitch-cli-bin`, `unityhub` |
| Security | `1password`, `1password-cli`, `bitwarden`, `bitwarden-cli`, `pam-u2f`, `libfido2`, `fprintd` |
| Creative | `gimp`, `inkscape`, `kdenlive`, `glaxnimate`, `obs-studio`, `ardour`, `guitarix`, `tuxguitar`, `freecad`, `prusa-slicer`, `xournalpp`, `typora-plugin`, `handbrake-cli` |
| Media | `vlc` and plugins, `feishin`, `cava`, `qbittorrent`, `jdownloader2` |
| Desktop tools | `snappy-switcher`, `wayscriber`, `pipewire-control-center`, `qpwgraph`, `blueferry-*`, `tailscale-systray-git`, `omazed`, `owe-lockfeed`, `voxtype-bin`, `hypridle`, `yazi`, `television`, `broot` |
| Hardware | `displaylink`, `evdi-dkms`, `solaar`, `intel-ucode`, `nvme-cli`, `smartmontools`, `rpi-imager`, `popsicle` |
| Gaming | `steam`, `lutris`, `wine-staging`, `protonup-qt-bin` |
| Fonts | Nerd and accessibility fonts (`otf-atkinson-hyperlegible`, `otf-opendyslexic-nerd`, Cascadia, Fira, Iosevka, Meslo and others) |
| KDE helpers | `ark`, `filelight`, `kwalletmanager`, `kio-extras`, `kdegraphics-thumbnailers` |

63 developer tools are managed by mise rather than pacman, including Node,
Python, Go, Rust, Bun, Deno and over a dozen AI coding CLIs
([list](generated/local/packages.md#mise-tools-63)).

## Host fixes that should not ship as-is

These solve problems on `sputnik` and are recorded in the Machinum host
briefing. Each is a lead for a general feature, not a default.

| Fix | Files | General feature it points to |
|---|---|---|
| Shell overlay patch | `~/.local/bin/omarchy-shell-overlay-sync`, overlay wrappers | Fix plugin service access and scoped config writes in the shell source |
| Dock workspace watcher | `sputnik-dock-workspaces`, `hypr/monitors.lua`, `hypr/global-workspaces.lua` | Monitor topology profiles (the rice has `subcult-topology`) |
| Idle and power profiles | `sputnik-idle-*`, `sputnik-power-profile*`, `hypridle.conf` | AC/battery power policy |
| DisplayLink driver | `displaylink`, `evdi-dkms` | Optional hardware installer |
| Chatterino downgrade | pinned `chatterino2-nightly-bin` | None; Qt version mismatch |
| `hyprctl` wrapper | `~/.local/bin/hyprctl` | Finds the Hyprland socket and Wayland display when a service or SSH session lacks them |

## Related local repositories

| Path | What it is |
|---|---|
| `~/Work/Forks/subcult-omarchy-rice` | SUBCULT rice 2.0.0, origin `git.subcult.tv/PatrickFanella/subcult-omarchy-rice` |
| `~/Work/Forks/evangelion-omarchy-rice` | Predecessor rice |
| `~/Work/Forks/omarchy-01-theme` | Fork of the `01` theme |
| `~/Work/Tools/omarchy-monitor-bar`, `omarchy-plugin-shelfish`, `omarchy-plugin-spool`, `omarchy-superproductivity` | Own plugin sources |
| `~/Work/Builds/omarchy-dell-power-profiles` | Package build for the Dell power backend |
| `~/Work/Lab/omarchy-plugin-research`, `omarchy-plugin-review-20261104`, `awesome-omarchy-plugin-submission` | Plugin research and review notes |
| `~/Work/Tools/estate-config` | Fleet configuration (chezmoi, Ansible) that already manages parts of this host |
