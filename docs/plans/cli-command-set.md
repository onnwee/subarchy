---
title: "Distribution CLI: the Bash command set"
type: plan
status: proposed
created: 2026-11-08
updated: 2026-11-08
tags: [plan, cli]
aliases: [CLI command set, E1]
---

# Distribution CLI: the Bash command set

Issue #48 (Epic E). [[0046-distribution-cli|ADR 0046]] puts stateful logic in
Go and thin glue in Bash under one dispatcher, `subcult <group> <action>`.
The Go side exists: `app`, `update`, `calendar`, `hw`, `thermal`, `agent`,
`font`, `cursor`, `display`, `clipboard`, and `subarchy-setup`; the Bash side
has `gpu`, `power auto`, `secureboot` and `disk tpm`. This note proposes the
rest of the Bash set, read off Omarchy 4.5.0's 425 visible commands on
`sputnik` (2026-11-08). The owner asked for the proposal and cuts it down:
strike a row to drop it, and the issue that implements each group follows.

Rules used: a command is proposed only when the shell, Theme Tender or an
existing Go command does not already do it; everything is written for
Subarchy against the behaviour, nothing copied; a command that keeps state,
parses structured data or needs more than a smoke test goes to Go instead.
Hidden helpers that only other scripts call are not commands.

## Proposed, Bash

Each group is one small PR with `shellcheck` and a `bats` smoke test.

### `subcult launch`

| Command | Does | Omarchy behaviour reference |
|---|---|---|
| `launch terminal [--cwd]` | The default terminal, in the focused terminal's directory with `--cwd` | `launch-terminal` |
| `launch browser [url]` | The default browser, through xdg-settings | `launch-browser` |
| `launch editor <file>` | The default editor; a terminal editor opens in a terminal | `launch-editor`, `launch-config-editor` |
| `launch tui <command>` | A terminal program in the default terminal with Subarchy's styling | `launch-tui` |
| `launch webapp <url>` | A URL as a web app in the browser | `launch-webapp` |
| `launch or-focus <pattern> <command>` | Focus a matching window or start the program (also for web apps and TUIs) | `launch-or-focus*` |
| `launch about` | The About screen (fastfetch with the SUBCULT art, #121) | `launch-about` |

### `subcult toggle`

| Command | Does | Reference |
|---|---|---|
| `toggle nightlight` | hyprsunset on or off | `toggle-nightlight` |
| `toggle dnd` | Notification silencing, through the shell's IPC | `toggle-notification-silencing` |
| `toggle bar` | Hide or show the bar without restarting the shell | `toggle-bar` |
| `toggle touchpad`, `toggle touchscreen` | Enable, disable or toggle the input device | `toggle-touchpad`, `toggle-touchscreen` |
| `toggle suspend` | Whether the system menu offers suspend | `toggle-suspend` |

Not proposed: `toggle-animations` (the motion setting, #118), `toggle-idle`
(keep-awake in the shell), `toggle-hybrid-gpu` (`subcult gpu mode`),
`toggle-theme-sync` (herdr), `toggle-screensaver` (lock program, #46).

### `subcult restart`

| Command | Does | Reference |
|---|---|---|
| `restart shell` | Restart the shell service | `restart-shell` |
| `restart hyprland` | Reload the Hyprland configuration | `restart-hyprctl` |
| `restart audio` | Restart PipeWire and WirePlumber, recover stuck USB audio | `restart-audio` |
| `restart bluetooth`, `restart wifi` | Unblock and restart the radio's service | `restart-bluetooth`, `restart-wifi` |
| `restart app <name>` | Kill and relaunch an app through uwsm | `restart-app` |

Not proposed: the per-editor and per-terminal reloads (Theme Tender's
apply tells each app itself, [[0037-theming|ADR 0037]]).

### `subcult capture`

| Command | Does | Reference |
|---|---|---|
| `capture screenshot [region\|window\|output]` | Screenshot to the clipboard and `~/Pictures`, with the region picker | `capture-screenshot` |
| `capture recording [--webcam]` | Start or stop a screen recording, with the webcam overlay on request | `capture-screenrecording*` |
| `capture text` | OCR of a screen region to the clipboard | `capture-text` |
| `capture qr` | Decode a QR code from a screen region | `capture-qr` |

### `subcult system`

| Command | Does | Reference |
|---|---|---|
| `system lock` | Lock through the lock program (#46) | `system-lock` |
| `system logout`, `system reboot`, `system shutdown` | After closing applications cleanly | `system` |
| `system snapshot [create\|list\|restore]` | snapper, with the `@factory` snapshot kept outside the rotation | `snapshot` |
| `system factory-reset` | Back to the `@factory` snapshot ([[0056-quality-of-life|ADR 0056]]) | `system-factory-reset` |
| `system kernel [list\|set]` | The kernel Limine boots by default | `kernel` |
| `system hibernation [setup\|remove]` | Swap file and resume settings ([[0014-swap-hibernation|ADR 0014]]) | `hibernation-*` |

### `subcult setup`

| Command | Does | Reference |
|---|---|---|
| `setup keyboard` | Layouts available for switching | `setup-keyboard` |
| `setup input` | Input methods for Japanese, Korean or Chinese | `setup-input` |
| `setup fingerprint`, `setup fido2` | PAM for sudo, polkit and the lock (#117) | `setup-security-fingerprint`, `setup-security-fido2` |
| `setup sshd` | OpenSSH server, firewall rule, authorised key | `setup-security-sshd` |
| `setup git` | Git name and email | `setup-git` |
| `setup docker` | Sudoless Docker (root-equivalent, says so) | `setup-security-sudoless-docker` |
| `setup timezone`, `setup language` | Time zone and locale | `menu-timezone`, `language` |

### `subcult network`

| Command | Does | Reference |
|---|---|---|
| `network password` | The active Wi-Fi password | `network-password` |
| `network qr` | A QR code for the active Wi-Fi | `network-qr` |
| `network portal` | Open a captive portal's sign-in page | `network-captive-portal` |
| `network band` | Show or pin the Wi-Fi band | `network-band` |

### `subcult pkg`

| Command | Does | Reference |
|---|---|---|
| `pkg add <name>...`, `pkg drop <name>...` | Install or remove Arch packages when missing or present; for scripts and hardware fixes | `pkg-add`, `pkg-drop` |
| `pkg present <name>...` | Exit 0 when all are installed | `pkg-present`, `pkg-missing` |

Not proposed: the fuzzy-finder installers (`subcult app` and the launcher,
[[0044-default-apps|ADR 0044]]) and the AUR wrappers ([[0025-package-repository|ADR 0025]]:
AUR packages Subarchy ships are rebuilt into its repository).

### `subcult config`

| Command | Does | Reference |
|---|---|---|
| `config reset <name>` | Put a shipped user config back (hyprland, shell, tmux, chromium), with a backup | `refresh-*`, `reinstall-configs` |
| `config edit <name>` | Open it in the editor | `launch-config-editor` |

### Small ones

| Command | Does | Reference |
|---|---|---|
| `version` | Subarchy's version, channel and snapshot date | `version`, `version-channel` |
| `reminder <when> <text>` | A desktop notification later | `reminder` |
| `transcode <file>` | Pictures and videos for sharing | `transcode` |
| `drive info`, `drive password` | Drive details; a new LUKS passphrase ([[0010-disk-encryption|ADR 0010]]) | `drive-*` |
| `tailscale send`, `tailscale receive` | Taildrop, when tailscale is installed | `tailscale-*` |

## Covered already, or Go

| Omarchy | Subarchy |
|---|---|
| `default-*` | `subcult app default` (ADR 0044) |
| `theme-*`, `plymouth-*`, `refresh-sddm` | Theme Tender (ADR 0037, Epic G) |
| `update*`, `migrate*`, `channel-*` | `subcult update`, `subcult channel` (ADR 0026, #69) |
| `font-*` | `subcult font` |
| `menu-clipboard`, `menu-emoji`, `menu-keybindings`, `menu-file` | the launcher (ADR 0057) |
| `audio-*`, `brightness-*`, `osd`, `notification-*`, `monitor-state`, `network-status`, `battery-*`, `weather-*` | the shell's widgets and IPC |
| `webapp-*`, `tui-install`, `pkg-install` | `subcult app` |
| `dns` | `subcult dns` (Go, ADR 0020, not written yet) |
| `hw-*`, `n1x-probe` | `subcult hw` (ADR 0050) |
| `agent*`, `default-agent` | `subcult agent`, the app list's agent role (ADR 0047) |
| `setup-direct-boot`, `refresh-limine` | Limine and the UKIs the installer writes (ADR 0007, 0008) |
| `dictation*`, `voxtype-*` | the dictation role in the app list |
| `sudo-keepalive`, `cmd-*`, `show-*`, `hook*` | script internals; `lib/` functions, not commands |

## Dropped

| Omarchy | Why |
|---|---|
| `install-*`, `remove-*` (80) | The installer and `subcult app` (ADR 0044, 0049) |
| `dev-*`, `update-dev`, `upgrade-to-quattro` | Omarchy's own development flow |
| `games-*`, `windows-*`, `launch-battlenet`, `launch-1password`, `launch-spotify`, `launch-signal` | Not in the base; apps come from the app list |
| `plugin-*`, `menu-plugin` | Subarchy's widgets ship in the package (ADR 0068); a plugin manager is a later question |
| `openclaw-*`, `launch-openclaw`, `launch-terminal-herdr`, `launch-discord-community`, `webapp-handler-hey`, `webapp-handler-zoom` | Omarchy's services and partners |
| `ascii`, `transcode-ascii` | `figlet` directly; the About art is a file (#121) |
| `sudo-passwordless`, `crash-mute`, `mise-install`, `disk-speedtest`, `network-speedtest`, `screensaver` | Niche, or the lock program's (#46) |

## Count

| | |
|---|---|
| Proposed Bash commands | 52 in 10 groups |
| Covered by the shell, Theme Tender or Go | about 120 |
| Dropped | about 250, 80 of them installers |

Related: [[0046-distribution-cli|ADR 0046]] · [[roadmap|Roadmap]]
