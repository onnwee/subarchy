---
title: "Roadmap"
type: plan
status: active
created: 2026-11-06
updated: 2026-11-20
tags: [plan]
aliases: []
---

# Roadmap

Built from scratch ([[0001-fork-strategy|ADR 0001]]), in the order of the
[[decision-map|decision map]]. Each phase ends with something that boots or
runs and is checked in CI.

The active tracker is
[roadmap issue #250](https://github.com/subculture-collective/subarchy/issues/250):
ship the first release and plan what follows. It replaces
[#230](https://github.com/subculture-collective/subarchy/issues/230), which
tracked desktop qualification; #5 is retired as well.
`tools/roadmap/subarchy-roadmap.json` is #5's historical plan; do not
republish it over #250. Record new scope and qualification on the existing
work issues under #250. The phases below retain the original implementation
history; their checkboxes were brought up to date on 2026-11-20 against the
closed issues named in each line. The numbers after each item are GitHub
issue numbers. The owner's open decisions are in [[pending-decisions]].

Still open on 2026-11-20 (each issue state read that day):

- #195: the NVIDIA GPU never reaches runtime D3 in Intel mode.
- #249: false USB-C charging and UPower external-power state on battery.
- #98: minor review findings from Epic A, deferred.
- #89: Google calendars in the sync; no real-account run yet.
- #51 (reopened) and #84: hardware results on `sputnik` and the first release.

## Phase 0: inventory and decisions

- [x] Inventory of Omarchy 4.5.0 and `sputnik`
- [x] Foundation, boot, system, package, session, shell, app and delivery
      decisions (ADRs 0002 to 0053)
- [x] Product name: Subarchy, shown as SUBCULT ([[0052-name-identity|ADR 0052]])
- [x] Owner's app list ([[app-list|App list]])
- [x] Owner's theme tool: Pult, formerly Theme Tender ([[0037-theming|ADR 0037]])

## Phase 1: infrastructure

- [x] Repository on `git.subcult.tv` with a GitHub mirror (#86); since
      2026-11-10 GitHub is the source and Gitea a fast-forward mirror
      ([[0051-hosting-ci|ADR 0051]])
- [x] Test the Gitea Arch registry with a Subarchy signing key, or set up a
      static repository (#20; [[0025-package-repository|ADR 0025]])
- [x] Signing key with offline backup; keyring package (#40, #87)
- [x] CI runner with KVM for package builds and VM boot tests (Kvant,
      `subarchy-kvm`, 2026-11-08, #29; [[ci-runner|limits and recovery]])
- [x] Choose how the stable Arch snapshot is served (#21;
      [[0026-update-model|ADR 0026]])

## Phase 2: base system boots

Packages and installer for the foundation, boot and system layers: Arch with
`linux-zen` and `linux-lts`, Limine, systemd UKIs, LUKS2 on btrfs, snapper,
Plymouth, NetworkManager with the DNS trust policy, PipeWire, ufw.

- [x] ISO builds in CI ([[0049-installer|ADR 0049]]): since 2026-11-10 the
      `iso / build` job on the KVM runner builds the image, boots it, installs
      from it into a VM disk and runs every install-test check (#36, #44;
      Gitea #236, #244, #246; [[ci-runner|runner limits]])
- [x] Installs in a VM to an encrypted, bootable system with snapshot entries
      (2026-11-07, `make install-test`; snapshot entry boots)
- [x] Set the CI memory and package budgets from this first build (#52;
      [[0054-lightweight-battery-first|ADR 0054]])
- [x] Update command: snapshot, upgrade, DKMS check, migrations, channels,
      the check timer and restart detection (#45, #88)
- [x] Guided installer (#124): delivered behavior and first-release scope
      reconciled 2026-11-16 ([[guided-installer-scope|acceptance matrix]]).
      Whole-disk installs with mandatory encryption; same-disk installation
      beside another OS is deferred. The visible speech-accessible boot
      menu and the mark above a progress bar stay. Remaining field
      observations are listed separately from implementation completion.

## Phase 3: session and shell

- [x] SDDM theme, uwsm session, Hyprland defaults with layered user overrides
      (#49; [[0048-config-ownership|ADR 0048]])
- [x] Plugin API design record: [[0068-shell-plugin-api-v0|ADR 0068]] (v0)
- [ ] Quickshell shell, stage 1 ([[shell-and-look-design|Shell and look
      design]]):
  - [x] Plan 1 ([[shell-stage-1-core-plan|core plan]]): look layer, font
        roles and `subcult font`, Subarchy cursor, shell core, event-driven
        bar widgets, notifications, OSD, polkit dialog, Alt-Tab, VM checks
        (2026-11-07)
  - [x] Hardening (Epic A, A1–A14, findings F1–F11 from the Omarchy and
        dux comparison; [[shell-hardening-plan|plan]]): global shortcuts,
        logind keep-awake, event-driven keyboard layout and recording marks,
        notification replacement and plain text, overlay placement, polkit
        focus; qualified by the full VM install test on 2026-11-08 (62
        checks, main-thread idle budget)
  - [x] Check the polkit wrong-password flow on `sputnik` (A15 #85, closed 2026-11-15)
  - [x] Plan 2: weather with `linecast` (#54, #62), Soma (#63), n8n (#64)
  - [x] Plan 2: HT3 widget and panel (#65) and its controls (#153), closed 2026-11-15
  - [x] Plan 3: calendar sync and widget (#46, #66)
  - [ ] Plan 3: Google calendars in the sync (#89)
- [x] Shell stage 2: a panel per widget (#41, #60, #61)
- [x] Shell stage 3: plugins shipped off by default, Dell power enabled on
      Dell hardware (#67, #68, #90, #91)
- [x] Launcher (#37, #47, #69, #70, #71, #92; [[0057-launcher|ADR 0057]])
- [x] Standalone QML lock program with the screensaver until input, and
      hypridle (#22, #23, #72; [[0036-shell-components|ADR 0036]])
- [x] Unlock with a fingerprint on supported readers (#93, closed 2026-11-15)
- [x] Ported rice features ([[rice-port-review|rice port review]]): dock and
      monitor profiles, reduced motion on battery, battery and thermal alerts,
      privacy indicator, settings panel, destructive-action confirmation,
      workspace names, media controls (#55, #73, #74, #75, #94, #95, #96)

## Phase 4: apps and theming

- [x] Pult packaged with the SUBCULT palette, applied to Hyprland, the
      shell and the lock, and system-level apply for SDDM, Plymouth and
      Limine (#48, #56, #76, #79)
- [x] Pult themes Qt and GTK apps (#77) and editors, CLI tools and
      Chromium (#78), both closed 2026-11-16 ([[pult-app-targets]])
- [x] App installer and default picker reading the app list (`subcult app`,
      2026-11-07), and web apps with Discord preinstalled (#80)
- [x] LazyVim starter and branding layer (#50, #97;
      [[0045-editor|ADR 0045]])
- [x] Distribution CLI: dispatcher, Bash commands, Go binary (Epic E #10,
      #24; [[cli-command-set|command set]], [[0046-distribution-cli|ADR 0046]])

## Phase 5: hardware and release

- [x] Port Omarchy's x86 hardware fixes, marked untested until run on real
      hardware (#42, #57, #58, #81, #82, #83;
      [[0050-hardware-support|ADR 0050]])
- [x] Install on `sputnik`'s empty second drive (`nvme0n1`), keeping Omarchy on
      `nvme1n1` as the fallback (installed 2026-11-08, reinstalled 2026-11-16;
      [[first-install|first install]]; [[0049-installer|ADR 0049]])
- [ ] Record the hardware results (#51, reopened; #195, #249 and #89 above)
- [ ] First release on the stable channel (#84)

Related: [[decision-map|Decision map]] · [[0001-fork-strategy|ADR 0001]] · [[open-questions|Open questions]]
