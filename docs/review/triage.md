---
title: "Plugin and add-on triage"
type: review
status: draft
review: pending
created: 2026-11-06
updated: 2026-11-06
tags: [review, plugins]
aliases: [Triage]
---

# Plugin and add-on triage

Proposed placement for everything added beyond Omarchy on `sputnik`. Edit the
**Proposed** column; the reason column explains the default.

Placement values:

- **default**: installed and enabled in every Subarchy image.
- **optional**: packaged in the Subarchy repository, off by default.
- **profile**: belongs to the owner's personal profile (estate-config or
  dotfiles), not the distribution.
- **host**: specific to `sputnik` hardware or the homelab; stays out.
- **drop**: superseded or not worth carrying.
- **evaluate**: needs a test on Omarchy 4.5 before deciding.

## Own plugins

| Plugin | Proposed | Reason |
|---|---|---|
| `patrickfanella.monitor-bar` | default | Per-monitor bars are a distinguishing feature. Needs its shell patch moved into the fork. |
| `onnwee.monitor-bar` | drop | Superseded by `patrickfanella.monitor-bar`. |
| `io.github.patrickfanella.shelfish` | evaluate | Overlaps `leyanora.plugincontainers` and `omatender`; pick one bar-grouping plugin. |
| `onnwee.command-palette` | evaluate | Overlaps `subcult.command-palette` and the stock menu; keep one. |
| `patrickfanella.superproductivity` | optional | Useful, but needs the custom Super Productivity build. |
| `onnwee.spool` | optional | Tied to T3 Code. |
| `patrickfanella.ht3` | host | One headphone model. |
| `onnwee.switchyard` | host | Homelab runtime. |
| `onnwee.gitea-pipelines` | profile | Points at `git.subcult.tv`; could become optional if made configurable. |

## SUBCULT rice

Superseded by [[rice-port-review|the rice port review]] (2026-11-06): the
owner does not want the rice's theme, and useful features are ported through
Subarchy's own plugin API.

## Community plugins

| Plugin | Proposed | Reason |
|---|---|---|
| `omaplug` | default | Plugin manager. Pick one of `omaplug` and `weedwhitesandwine.plug`. |
| `io.github.weedwhitesandwine.plug` | evaluate | Alternative plugin manager with AI code scanning before updates. |
| `shell.settings` | evaluate | Overlaps `subcult.settings`. |
| `io.github.pablo-merino.altswitch` | default | Alt-Tab across workspaces is a common request. |
| `io.github.thebenwalther.switchboard`, `io.github.chinofmaya.spaces`, `io.github.agata.omasets` | optional | Window and workspace tools with overlapping scope. |
| `burninc0de.dock` | evaluate | Omarchy now ships `omarchy.dock`. |
| `foamy.notification-center` | default | In current use. Drop `shavanced.notification-center` as a duplicate. |
| `shavanced.notification-center` | drop | Duplicate. |
| `dailen.omartfy` | optional | ntfy notifications. |
| `tmn73.calendar` | default | In current use; brings `omarchy-calendar-sync`. |
| `ashuttl.linecast` | evaluate | Overlaps stock `omarchy.weather`. |
| `eduardodallecort.weather-radar` | optional | |
| `io.github.joshuaswarren.somafm` | optional | |
| `ky.navidrome-remote` | optional | Needs a Navidrome server. |
| `ussego.otoru` | optional | yt-dlp downloads. |
| `dizziee.auto-wallpaper` | default | Fits the affinity-palette feature; confirm it cooperates with `owe`. |
| `io.github.sirjul1337.lock-explorer` | evaluate | Replaces `omarchy.lock` here; a SUBCULT lock design could ship through it. |
| `taxin.cursor-style` | optional | |
| `davies-sam.omatheme` | optional | Theme designer; useful for building Subarchy themes. |
| `io.github.elevate08.qs-bitwarden-cli` | optional | Password manager choice is personal. |
| `harshith.system-monitor`, `io.github.rickycbanks.osystemd`, `io.github.randazraik.xray`, `devgtv.docker`, `com.github.linuxgameruk.ollama-status`, `yashwanth.link` | optional | System tools; overlap with each other and with stock panels. |
| `legendik.n8n`, `io.github.luccast.omarr` | profile | Homelab services. |
| `stappmus.dell-power-profiles` | optional | Dell hardware only; could be enabled by hardware detection. |
| `io.github.thisisgm.omapods` | optional | AirPods. |
| `io.github.chernicharo.voxtype-mode` | evaluate | Depends on whether voxtype dictation ships. |
| `rperaza.obsidian-notes`, `mateuszkowalczyk.obsidian-quick-switcher` | optional | Obsidian is in Omarchy's base list. |
| `leyanora.plugincontainers`, `io.github.salemsayed.omatender` | evaluate | Bar grouping; pick one against `shelfish`. |
| `omakey` | optional | Learning aid. |
| `io.github.roman.ovaxry` | drop | Novelty. |

Before anything community-made ships by default: check its licence, pin a
commit, and record the upstream in the package. None of that is done yet.

## Themes

| Theme | Proposed | Reason |
|---|---|---|
| `subcult`, `subcult-minimal` | default | Identity. |
| `evangelion` | drop | Predecessor of `subcult`. |
| `kvant-sputnik`, `kvant-tty` | profile | Fleet host themes. |
| `01`, `event-horizon`, `flat-dracula`, `saga`, user `omarchy` | optional | Third-party; check licences before redistributing. |
| Omarchy's 24 stock themes | evaluate | Keep all, keep a few, or ship only SUBCULT themes. |

## Host fixes and services

| Item | Proposed | Reason |
|---|---|---|
| Shell overlay patch (`omarchy-shell-overlay-sync`) | default, as a fork patch | Move the fix into the shell source and offer it upstream. |
| `hyprctl` socket wrapper | evaluate | Helps services and SSH sessions; may belong in the fork. |
| `sputnik-dock-workspaces`, idle and power-profile services | host | Replace with topology profiles and a power policy feature. |
| `voxtype.service` | evaluate | With the dictation decision. |
| `tmux.service`, `opencode-tasks`, `mise-history` | profile | Workflow preferences. |

## Packages beyond Omarchy

| Group | Proposed | Reason |
|---|---|---|
| Fonts used by the brand (JetBrains Mono, Oswald) | default | Needed by the theme. |
| Accessibility fonts (Atkinson Hyperlegible, OpenDyslexic) | evaluate | Support the rice's accessibility standard. |
| Browsers, chat, AI desktop apps, editors | profile | Personal choices. Omarchy already ships Chromium. |
| Creative, gaming, media apps | profile | Personal; Omarchy offers many through `omarchy install`. |
| Hardware drivers (DisplayLink, Solaar) | optional | Install on detection or request. |
| mise developer tools | profile | Personal toolchain. |

Related: [[local-additions|Local additions]] · [[subcult-rice|SUBCULT rice]] · [[0001-fork-strategy|ADR 0001]]
