---
title: "Roadmap"
type: plan
status: draft
created: 2026-11-06
updated: 2026-11-07
tags: [plan]
aliases: []
---

# Roadmap

Built from scratch ([[0001-fork-strategy|ADR 0001]]), in the order of the
[[decision-map|decision map]]. Each phase ends with something that boots or
runs and is checked in CI.

The open items below are tracked as Gitea issues under
[roadmap issue #29](https://git.subcult.tv/subculture-collective/subarchy/issues/29),
one issue per PR in dependency order. The issue plan is
`tools/roadmap/subarchy-roadmap.json`; edit it and republish with the
`roadmap-slicer` skill when this page changes.

## Phase 0: inventory and decisions

- [x] Inventory of Omarchy 4.5.0 and `sputnik`
- [x] Foundation, boot, system, package, session, shell, app and delivery
      decisions (ADRs 0002 to 0053)
- [x] Product name: Subarchy, shown as SUBCULT ([[0052-name-identity|ADR 0052]])
- [x] Owner's app list ([[app-list|App list]])
- [x] Owner's theme tool: Theme Tender ([[0037-theming|ADR 0037]])

## Phase 1: infrastructure

- [ ] Create the repository on `git.subcult.tv` with a GitHub mirror (repository
      and CI exist since 2026-11-07; no mirror yet)
      ([[0051-hosting-ci|ADR 0051]])
- [ ] Test the Gitea Arch registry with a Subarchy signing key, or set up a
      static repository ([[0025-package-repository|ADR 0025]])
- [ ] Signing key with offline backup; keyring package
- [ ] CI runner with KVM for package builds and VM boot tests
- [ ] Choose how the stable Arch snapshot is served
      ([[0026-update-model|ADR 0026]])

## Phase 2: base system boots

Packages and installer for the foundation, boot and system layers: Arch with
`linux-zen` and `linux-lts`, Limine, systemd UKIs, LUKS2 on btrfs, snapper,
Plymouth, NetworkManager with the DNS trust policy, PipeWire, ufw.

- [ ] ISO builds in CI ([[0049-installer|ADR 0049]]); builds and boots locally since 2026-11-07 (`make iso iso-test`), CI needs a privileged runner
- [x] Installs in a VM to an encrypted, bootable system with snapshot entries
      (2026-11-07, `make install-test`; snapshot entry boots)
- [ ] Set the CI memory and package budgets from this first build
      ([[0054-lightweight-battery-first|ADR 0054]])
- [ ] Update command: snapshot, upgrade, DKMS check, migrations (`subcult
      update` works in the VM test; channels and the check timer remain)

## Phase 3: session and shell

- [ ] SDDM theme, uwsm session, Hyprland defaults with layered user overrides
      ([[0048-config-ownership|ADR 0048]]); session, greeter and layered
      defaults boot in the VM test since 2026-11-07, theme still to do
- [x] Plugin API design record: [[0068-shell-plugin-api-v0|ADR 0068]] (v0)
- [ ] Quickshell shell, stage 1 ([[shell-and-look-design|Shell and look
      design]]):
  - [x] Plan 1 ([[shell-stage-1-core-plan|core plan]]): look layer, font
        roles and `subcult font`, Subarchy cursor, shell core, event-driven
        bar widgets, notifications, OSD, polkit dialog, Alt-Tab, VM checks
        (2026-11-07)
  - [x] Hardening (Epic A, findings F1–F11 from the Omarchy and dux
        comparison): global shortcuts, logind keep-awake, event-driven
        keyboard layout and recording marks, notification replacement and
        plain text, overlay placement, polkit focus; qualified by the full
        VM install test on 2026-11-08 (62 checks, main-thread idle budget)
  - [ ] Plan 2: weather (with `linecast`), Soma, n8n, HT3
  - [ ] Plan 3: calendar sync and widget
- [ ] Shell stage 2: a panel per widget
- [ ] Shell stage 3: plugins shipped off by default (Dell power, otoru,
      auto-wallpaper, agents usage)
- [ ] Launcher ([[0057-launcher|ADR 0057]])
- [ ] Standalone QML lock program with the screensaver until input, and
      hypridle ([[0036-shell-components|ADR 0036]])
- [ ] Ported rice features ([[rice-port-review|rice port review]]): dock and
      monitor profiles, reduced motion on battery, battery and thermal alerts,
      privacy indicator, settings panel, destructive-action confirmation,
      workspace names, media controls

## Phase 4: apps and theming

- [ ] Theme Tender registry entries and templates for Subarchy's apps, the
      SUBCULT palette, and system-level apply for SDDM, Plymouth and Limine
- [x] App installer and default picker reading the app list (`subcult app`,
      2026-11-07; web apps and per-app integration still to do)
- [ ] LazyVim starter and branding layer ([[0045-editor|ADR 0045]])
- [ ] Distribution CLI: dispatcher, Bash commands, Go binary (dispatcher and
      `subcult app` done 2026-11-07)
      ([[0046-distribution-cli|ADR 0046]])

## Phase 5: hardware and release

- [ ] Port Omarchy's x86 hardware fixes, marked untested until run on real
      hardware ([[0050-hardware-support|ADR 0050]])
- [ ] Install on `sputnik`'s empty second drive (`nvme0n1`), keeping Omarchy on
      `nvme1n1` as the fallback ([[0049-installer|ADR 0049]])
- [ ] First release on the stable channel

Related: [[decision-map|Decision map]] · [[0001-fork-strategy|ADR 0001]] · [[open-questions|Open questions]]
