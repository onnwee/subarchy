---
title: "Next decisions"
type: review
status: draft
review: pending
created: 2026-11-07
updated: 2026-11-07
tags: [review, plan]
aliases: [Decision backlog, Remaining decisions]
---

# Next decisions

Everything still open after the decision map was completed, gathered
2026-11-07 from the ADRs, [[open-questions|open questions]] and the
[[roadmap|roadmap]]. Grouped by kind, most pressing first in each group.

## Decisions not yet made

| # | Decision | Why it matters |
|---|---|---|
| N1 | **Backups of `/home`** | Snapshots cover only the root ([[0011-snapshots\|ADR 0011]]); nothing protects user files. Candidates: restic or borg to the homelab or Proton Drive CLI, on a timer. |
| N2 | **Default bar layout** | Which widgets appear on the full and minimal bars, and in what order ([[0036-shell-components\|ADR 0036]]). |
| N3 | **Calendar source for the bar** | Proton Calendar has no CalDAV for third-party apps; the `sputnik` bar uses the `tmn73.calendar` plugin. Pick a source (Google, CalDAV, ICS link) or none. |
| N4 | **Wallpapers** | The rice's seven SUBCULT wallpapers were part of the declined theme; the default theme needs some. Reuse, redraw, or commission. |
| N5 | **sudo and polkit policy** | Password on every `sudo`? Omarchy offers passwordless sudo as a toggle; which actions (updates, power, network) skip the prompt. |
| N6 | **Security hardening** | AppArmor or not, `sysctl` hardening, USB device policy, kernel lockdown with Secure Boot, and a fast path for security updates on the two-week stable channel ([[0026-update-model\|ADR 0026]]). |
| N7 | **Virtual machines** | QEMU/libvirt or virt-manager preinstalled? CI boot tests already need QEMU. |
| N8 | **Phone integration** | KDE Connect (notifications, clipboard, files) besides LocalSend. |
| N9 | **Telemetry and crash reports** | State plainly that nothing leaves the machine unless the user sends it; crash reports stay local ([[0056-quality-of-life\|ADR 0056]]). |
| N10 | **Versioning and release cadence** | Version scheme for Subarchy, how often stable advances, what a release contains. |
| N11 | **Moving `sputnik` to Subarchy** | Fresh install from the ISO, and what to carry over (home, keys, configs); the rice is removed first ([[0052-name-identity\|ADR 0052]]). |
| N12 | **User documentation** | Where the user manual lives (this vault, a site, `subcult help`). |

## Design work that needs its own session

| # | Item | Source |
|---|---|---|
| W1 | Shell plugin API design record | [[0035-plugin-api\|ADR 0035]] |
| W2 | Full keymap | [[0056-quality-of-life\|ADR 0056]] |
| W3 | SUBCULT palette in Theme Tender's format | [[0037-theming\|ADR 0037]] |
| W4 | Brand assets: wordmark, icons, Plymouth splash, SDDM theme, lock screen and screensaver loops | [[branding-surfaces\|Branding surfaces]], [[0052-name-identity\|ADR 0052]] |
| W5 | App-list file format for the installer and default picker | [[0044-default-apps\|ADR 0044]] |

## Assumptions to confirm

Choices the agent made that the owner has not confirmed:

| # | Assumption | Where |
|---|---|---|
| A1 | GPL-3.0 **or later**, not "only" | [[0053-licence\|ADR 0053]] |
| A2 | NVIDIA mode falls back to Intel at login when undocked or on battery | [[0006-gpu-drivers\|ADR 0006]] |
| A3 | Launcher accepts Raycast's script-command headers | [[0057-launcher\|ADR 0057]] |
| A4 | Desktop control shows an indicator and pauses while locked | [[0059-agent-desktop-control\|ADR 0059]] |
| A5 | Config paths and plugin IDs use `subcult`; packages use `subarchy` | [[0052-name-identity\|ADR 0052]] |
| A6 | The short command alias is `sub` | [[0052-name-identity\|ADR 0052]] |

## Questions still open from earlier

| # | Question | Source |
|---|---|---|
| Q1 | Publisher: the owner personally or `subculture-collective` (the repository is under the organisation) | open question 2 |
| Q2 | Can the SUBCULT marks and wallpapers ship under the rice's `ASSETS_LICENSE.md`? | open question 5 |
| Q3 | Licences of the ported community plugins and Zen mods | open question 6, [[0042-browser\|ADR 0042]] |
| Q4 | Who holds the package signing key, and where it is backed up | open question 8, [[0025-package-repository\|ADR 0025]] |
| Q5 | Retire or rename `PatrickFanella/omarchy-subcult-theme` | open question 15 |
| Q6 | Raise the three Theme Tender items as issues there | [[0037-theming\|ADR 0037]] |

## Implementation choices (decide when building)

- How the stable Arch snapshot is served: own mirror or Arch Linux Archive
  date pin ([[0026-update-model|ADR 0026]]).
- Whether Gitea's Arch registry can sign with Subarchy's key
  ([[0025-package-repository|ADR 0025]]).
- Initramfs hook line and early NVIDIA loading ([[0008-initramfs|ADR 0008]]).
- Whether Intel mode lets NVIDIA power off, and whether NVIDIA mode drives the
  Intel outputs smoothly ([[0006-gpu-drivers|ADR 0006]]).
- Whether ufw needs a rule for `tailscale0` ([[0058-tailscale|ADR 0058]]).

Related: [[decision-map|Decision map]] · [[open-questions|Open questions]] · [[roadmap|Roadmap]]
