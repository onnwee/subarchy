---
title: "Branding surfaces"
type: inventory
status: active
host: sputnik
observed: 2026-11-06
created: 2026-11-06
updated: 2026-11-06
tags: [inventory, branding]
---

# Branding surfaces

Every place a user sees the Omarchy name, logo or URLs, and what it takes to
change it. Observed in Omarchy 4.5.0-3.

"User-level" means a supported command or user file changes it and it survives
updates. "Package-level" means the file belongs to an Omarchy package or is
rewritten by one, so only a fork or a replacement package can change it
permanently.

| Surface | Source | Level | Notes |
|---|---|---|---|
| OS identity (`NAME`, `ID=omarchy`, URLs, `LOGO`) | `/usr/share/omarchy/etc-overrides/os-release` → `/etc/os-release` | Package | The `omarchy-settings` install script deletes and recopies `/etc/os-release` on every install and upgrade. |
| Boot menu title | `default/limine/limine.conf`: `interface_branding: Omarchy Bootloader` | Package | Limine entries also come from `limine-snapper-sync`. |
| Boot splash | `default/plymouth/` (`omarchy.plymouth`, `omarchy.script`, `logo.png`, `logos/oma.png`), installed to `/usr/share/plymouth/themes/omarchy/` by `omarchy-settings` | Package, partly user | `omarchy plymouth set` changes colours and logo per user; `/etc/plymouth/plymouthd.conf` is reset on each `omarchy-settings` upgrade. |
| Login screen | `default/sddm/omarchy/` (`Main.qml`, `theme.conf`, `metadata.desktop`) | Package | `omarchy plymouth reset` also resets SDDM. |
| Logos and icon | `/usr/share/omarchy/logo.svg`, `logo.txt` (ASCII wordmark), `icon.png`, `icon.txt` | Package | Read by `omarchy-show-logo`, the branding and Plymouth commands, owner provisioning and the web-app installer. |
| About screen and fastfetch | `/etc/fastfetch/config.jsonc` reads `~/.config/omarchy/branding/about.txt` and prints `Omarchy <version>` | User for the art, package for the version line | `omarchy branding about` edits the art. `sputnik` already has a custom `about.txt`. |
| Screensaver | `~/.config/omarchy/branding/screensaver.txt` | User | `omarchy branding screensaver`. Customised on `sputnik`. |
| Theme intro videos | `omarchy-themes-intros` package | Package | Only for stock themes. |
| Command namespace | 556 `omarchy-*` binaries and the `omarchy` dispatcher | Package | Renaming is the largest single branding cost; see ADR 0001. |
| Config paths | `~/.config/omarchy/`, `~/.local/state/omarchy/`, `$OMARCHY_PATH` | Package | Every plugin and hook depends on these paths. |
| Menu and shell text | `shell/` QML strings, `default/omarchy/omarchy-menu.jsonc` | Package, partly user | Menu extensions can add entries; renaming built-in text needs the shell source. |
| Default web apps | `applications/*.desktop` (Basecamp, HEY and others) | Package | Product choices by Omarchy's maintainers; review for Subcarchy. |
| Package repository | `[omarchy]` in `/etc/pacman.conf`, `https://pkgs.omarchy.org`, `omarchy-keyring`, `default/pacman/*` mirrorlists | Package | A distribution needs its own repository and signing key for its own packages. |
| Kernel name | `linux-omarchy` | Package | Can stay; it is a technical dependency, not a visible brand. |
| Agent skills and docs links | `default/agents/skills/omarchy/`, references to `omarchy.org` and `learn.omacom.io` | Package | Point users to Omarchy's manual and Discord. |
| ISO and installer | Omarchy's ISO builder and installer screens | Package | Not inspected in this inventory. |

## Trademark note

Omarchy's code is MIT-licensed, which permits forking and redistribution with
the licence notice. The licence does not grant use of the Omarchy name or
logo. A distribution should replace the name, logos, Plymouth and SDDM art and
support URLs, and credit Omarchy as upstream. Get advice before shipping
anything that could look like an official Omarchy release.

Related: [[omarchy-overview|Omarchy component map]] · [[brand-identity|Brand identity]] · [[0001-fork-strategy|ADR 0001]]
