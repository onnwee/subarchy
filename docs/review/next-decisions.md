---
title: "Next decisions"
type: review
status: active
review: done
created: 2026-11-07
updated: 2026-11-07
tags: [review, plan]
aliases: [Decision backlog, Remaining decisions]
---

# Next decisions

Everything still open after the decision map was completed, gathered
2026-11-07 from the ADRs, [[open-questions|open questions]] and the
[[roadmap|roadmap]]. Grouped by kind, most pressing first in each group.

## Decisions made 2026-11-07

| # | Decision | Outcome |
|---|---|---|
| N1 | Backups | Borg via borgmatic to the homelab; which host is open ([[0060-backups\|ADR 0060]]) |
| N2 | Default bar | The owner's current bar ([[0061-default-bar-calendar\|ADR 0061]]) |
| N3 | Calendar | Google and CalDAV ([[0061-default-bar-calendar\|ADR 0061]]) |
| N4 | Wallpapers | The `subcult-minimal` set ([[0038-wallpaper\|ADR 0038]]) |
| N5 | sudo and polkit | Some actions skip the prompt; "skip sudo for X minutes" ([[0062-privilege-policy\|ADR 0062]]) |
| N6 | Hardening | Agent's recommendations ([[0063-security-hardening\|ADR 0063]]) |
| N7 | Virtual machines | Installed, no images ([[0064-virtual-machines\|ADR 0064]]) |
| N8 | Phone integration | None |
| N9 | Telemetry | Nothing leaves the machine ([[0065-privacy-telemetry\|ADR 0065]]) |
| N10 | Versioning | Semver from 0.0.0; cadence later ([[0066-versioning\|ADR 0066]]) |
| N11 | `sputnik` | Install on the empty second drive ([[0049-installer\|ADR 0049]]) |
| N12 | User manual | As Omarchy, on the device and in the repository ([[0067-user-manual\|ADR 0067]]) |

Still open from these: which homelab host holds the borg repository; the
exact list of actions that skip `sudo`; upscaled wallpapers.

## Design work that needs its own session

| # | Item | Source |
|---|---|---|
| W1 | Shell plugin API design record | [[0035-plugin-api\|ADR 0035]] |
| W2 | Full keymap | [[0056-quality-of-life\|ADR 0056]] |
| W3 | SUBCULT palette in Theme Tender's format | [[0037-theming\|ADR 0037]] |
| W4 | Brand assets: wordmark, icons, Plymouth splash, SDDM theme, lock screen and screensaver loops | [[branding-surfaces\|Branding surfaces]], [[0052-name-identity\|ADR 0052]] |
| W5 | App-list file format for the installer and default picker | [[0044-default-apps\|ADR 0044]] |

## Assumptions and questions settled 2026-11-07

- All six agent assumptions confirmed: GPL-3.0-or-later, Intel fallback at
  login, Raycast script headers, desktop-control indicator and lock pause,
  `subcult` paths with `subarchy` packages, `sub` alias.
- Publisher: `subculture-collective`.
- Assets: the owner holds the rights to all SUBCULT assets.
- Licences: not a concern while the repository is private; a gate before
  going public ([[0053-licence|ADR 0053]]).
- Signing key: held by the owner, on `soyuz`, to be copied to a second place.
- `PatrickFanella/omarchy-subcult-theme` and the other old repositories are
  left as they are.
- Theme Tender issues: opened (see [[0037-theming|ADR 0037]]).

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
