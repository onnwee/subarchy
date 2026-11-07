---
title: "Roadmap"
type: plan
status: draft
created: 2026-11-06
updated: 2026-11-06
tags: [plan]
aliases: []
---

# Roadmap

Built from scratch ([[0001-fork-strategy|ADR 0001]]), in the order of the
[[decision-map|decision map]]. Each phase ends with something that boots or
runs and is checked in CI.

## Phase 0: inventory and decisions

- [x] Inventory of Omarchy 4.5.0 and `sputnik`
- [x] Foundation, boot, system, package, session, shell, app and delivery
      decisions (ADRs 0002 to 0053)
- [x] Product name: Subarchy, shown as SUBCULT ([[0052-name-identity|ADR 0052]])
- [x] Owner's app list ([[app-list|App list]])
- [x] Owner's theme tool: Theme Tender ([[0037-theming|ADR 0037]])

## Phase 1: infrastructure

- [ ] Create the repository on `git.subcult.tv` with a GitHub mirror
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

- [ ] ISO builds in CI ([[0049-installer|ADR 0049]])
- [ ] Installs in a VM to an encrypted, bootable system with snapshot entries
- [ ] Set the CI memory and package budgets from this first build
      ([[0054-lightweight-battery-first|ADR 0054]])
- [ ] Update command: snapshot, upgrade, DKMS check, migrations

## Phase 3: session and shell

- [ ] SDDM theme, uwsm session, Hyprland defaults with layered user overrides
      ([[0048-config-ownership|ADR 0048]])
- [ ] Plugin API design record ([[0035-plugin-api|ADR 0035]])
- [ ] Quickshell shell: bar, launcher, notifications, OSD, polkit
- [ ] Standalone QML lock program with the screensaver until input, and
      hypridle ([[0036-shell-components|ADR 0036]])
- [ ] Ported rice features ([[rice-port-review|rice port review]]): dock and
      monitor profiles, reduced motion on battery, battery and thermal alerts,
      privacy indicator, settings panel, destructive-action confirmation,
      workspace names, media controls

## Phase 4: apps and theming

- [ ] Theme Tender registry entries and templates for Subarchy's apps, the
      SUBCULT palette, and system-level apply for SDDM, Plymouth and Limine
- [ ] App installer and default picker reading the app list
- [ ] LazyVim starter and branding layer ([[0045-editor|ADR 0045]])
- [ ] Distribution CLI: dispatcher, Bash commands, Go binary
      ([[0046-distribution-cli|ADR 0046]])

## Phase 5: hardware and release

- [ ] Port Omarchy's x86 hardware fixes, marked untested until run on real
      hardware ([[0050-hardware-support|ADR 0050]])
- [ ] Install on `sputnik`'s empty second drive (`nvme0n1`), keeping Omarchy on
      `nvme1n1` as the fallback ([[0049-installer|ADR 0049]])
- [ ] First release on the stable channel

Related: [[decision-map|Decision map]] · [[0001-fork-strategy|ADR 0001]] · [[open-questions|Open questions]]
