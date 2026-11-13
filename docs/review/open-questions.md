---
title: "Open questions"
type: review
status: active
review: done
created: 2026-11-06
updated: 2026-11-13
tags: [review]
---

# Open questions

Answer inline and move answered items to the bottom with the date.

## Identity

1. Is "Subarchy" the public name, or a working title? See
   [[brand-identity|brand identity]] for the clash checks.
2. Who is the publisher: onnwee personally or the
   `subculture-collective` organisation?
3. Should `os-release` keep `ID_LIKE` including `omarchy` for compatibility?

## Licence and assets

4. Which licence for Subarchy's own code? MIT matches Omarchy and the rice.
5. Can the SUBCULT marks and the Oswald and JetBrains Mono fonts be
   redistributed in an image under the rice's `ASSETS_LICENSE.md` terms?
6. Which community plugins and themes allow redistribution? Not yet checked.

## Hosting and build

7. Where does the canonical repository live? `git.subcult.tv` (matching the
   rice) is the default. This repository has no remote yet.
8. Where is the Subarchy pacman repository hosted, and who holds the signing
   key?
9. Is this repository the Omarchy fork itself, or a separate build repository?
   (ADR 0001 open question.)
10. Track upstream `main` or releases only, and how often to merge?

## Scope

11. Which machines are targets? `sputnik` (x86_64 laptop with dock) is the
    reference. Omarchy also supports aarch64 (Apple Silicon, Qualcomm, NVIDIA
    GB10/N1X); supporting them multiplies testing.
12. Is the first deliverable an ISO, or a conversion of an existing Omarchy
    install?
13. Is the default user a developer like the owner, or a general user? This
    decides how many of the 179 extra packages and 63 mise tools matter.
14. Are AI agent integrations (Omarchy's `omarchy agent` commands and bar
    widget, voxtype dictation) part of the default experience?

## Housekeeping

15. The old `PatrickFanella/omarchy-subcult-theme` also installs as `subcult`.
    Retire or rename it?
16. `sputnik` has many `.bak` files in `~/.config/hypr` and
    `~/.config/omarchy`. Clean up before capturing a reference configuration?
17. The Machinum host briefing lists OmaSSH and Fleetbar plugins as installed
    on 2026-10-06; neither is in `~/.config/omarchy/plugins` now. Were they
    removed on purpose?


## Answered 2026-11-06

- **1. Public name**: Subarchy; screens show SUBCULT and the command is
  `subcult` ([[0052-name-identity|ADR 0052]]).
- **4. Licence**: GPL-3.0-or-later ([[0053-licence|ADR 0053]]).
- **7. Canonical repository**: `git.subcult.tv` with a GitHub mirror
  ([[0051-hosting-ci|ADR 0051]]). Reversed on 2026-11-10: GitHub is the
  source and Gitea the mirror (ADR 0051, progress).
- **9 and 10. Fork questions**: no longer apply; Subarchy is built from
  scratch ([[0001-fork-strategy|ADR 0001]]).
- **11. Targets**: x86_64 only ([[0003-cpu-architectures|ADR 0003]]),
  hardware fixes per [[0050-hardware-support|ADR 0050]].
- **12. First deliverable**: own ISO and installer
  ([[0049-installer|ADR 0049]]).
- **14. AI agents**: built in, lighter than Omarchy
  ([[0047-ai-agents|ADR 0047]]).
- **3. `ID_LIKE`**: `arch` only; Subarchy does not claim `omarchy`
  ([[0052-name-identity|ADR 0052]]).
- **13. Default user**: Subarchy is mainly for the owner, while staying
  compatible with many devices (2026-11-07; [[0054-lightweight-battery-first|ADR 0054]]).

- **2. Publisher**: `subculture-collective` (2026-11-07).
- **5. Assets**: the owner holds the rights to all SUBCULT assets.
- **6. Licences**: not a concern while private; checked before going public.
- **8. Signing key**: held by the owner, on `soyuz`.
- **15. Old theme repository**: left as it is.

- **16. `.bak` files**: 17 backup files and folders from `~/.config/hypr`
  and `~/.config/omarchy` moved to
  `~/.local/state/omarchy/bak-cleanup-20261107/` on `sputnik` (2026-11-07).
- **17. OmaSSH and Fleetbar**: removed on purpose.

All open questions are answered.

Related: [[0001-fork-strategy|ADR 0001]] · [[brand-identity|Brand identity]] · [[roadmap|Roadmap]]
