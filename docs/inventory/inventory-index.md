---
title: "Inventory"
type: index
status: active
host: sputnik
observed: 2026-11-06
created: 2026-11-06
updated: 2026-11-06
tags: [index, inventory]
aliases: [Inventory overview]
---

# Inventory

Snapshot: `sputnik`, 2026-11-06, Omarchy `4.5.0-3`, kernel `7.2.15-1-omarchy`.

## Summary

| Area | Upstream Omarchy | Added on `sputnik` |
|---|---|---|
| Commands | 556 `omarchy-*` commands in 85 groups, 131 hidden | 61 `subcult-*` commands, 15 desktop overrides and host helpers, 27 other scripts |
| Shell plugins | 32 built-in | 86 plugin directories: 39 community, 38 SUBCULT rice, 9 own |
| Themes | 24 stock | 10 user themes (2 SUBCULT, 2 Kvant, 1 Evangelion, 5 community) |
| Packages | 162 base, 63 optional/hardware, 27 aarch64; 256 in the `[omarchy]` repo | 179 explicit packages outside Omarchy's lists, 30 of them AUR or local builds; 63 mise tools |
| User services | Omarchy units such as `omarchy-crash-watch` and `omarchy-sleep-lock` | 15 unit files in `~/.config/systemd/user` |
| Hooks | Six `.sample` hooks in the config template; migration `1786549201` adds `setup-agent.hook` | 8 added hook scripts across `post-boot`, `post-update` and `theme-set` |

## Hand-written documents

- [[omarchy-overview|Omarchy component map]]: the parts of Omarchy and how they fit.
- [[local-additions|Local additions]]: what was added beyond Omarchy, grouped by purpose.
- [[subcult-rice|SUBCULT rice]]: the existing 2.0.0 overlay that supplies the `subcult.*` plugins and `subcult-*` commands.
- [[branding-surfaces|Branding surfaces]]: where the Omarchy name, logo and URLs appear.

## Generated documents

`tools/inventory/collect.py` writes these from the live system. Do not edit
them by hand.

| Note | Source |
|---|---|
| [[omarchy-layout]] | `/usr/share/omarchy` tree, install scripts, migrations, web apps |
| [[omarchy-commands]] | `omarchy commands --json --all` |
| [[omarchy-packages]] | `install/*.packages` with installed versions |
| [[omarchy-repo-packages]] | Every package in the `[omarchy]` pacman repository |
| [[omarchy-shell]] | Built-in shell plugin manifests |
| [[omarchy-themes]] | Stock theme directories |
| [[local-plugins]] | User plugin manifests, git origins, `shell.json` bar layout and dock pins |
| [[local-themes]] | User theme directories and origins |
| [[local-config]] | Hooks, menu extensions, Omarchy and Hyprland config file names |
| [[local-scripts-and-services]] | `~/.local/bin`, user systemd units, desktop entries |
| [[local-packages]] | Explicit packages outside Omarchy's lists, mise tools |

Their properties (`scope`, `observed`, `source`) feed this view:

![[inventory.base]]

## What the collector does not record

- Configuration values. It lists file names and plugin ids, never the contents
  of `shell.json`, hook scripts or JSON settings files, which can hold tokens,
  hostnames and personal data.
- Credentials embedded in git remote URLs; it strips them.
- System-wide changes outside `~/.config`, `~/.local` and pacman, such as
  `/etc` edits, firewall rules or Limine entries.
- Flatpak, npm-global and pip packages other than those mise manages.

## Caveats

- "Referenced" in the plugin table means the plugin id appears somewhere in
  `shell.json`. It does not prove the plugin rendered or works.
- "Packages beyond Omarchy" excludes Omarchy's package lists and the
  dependency tree of the `omarchy` package. Some remaining packages were
  installed by Omarchy's own `omarchy install …` commands and are not personal
  choices; the generated page says so.
- Plugin source is inferred from the id prefix and git origin. A plugin with
  no origin is marked *local*.

Related: [[home|Docs home]]
