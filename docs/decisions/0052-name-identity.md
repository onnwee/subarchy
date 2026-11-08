---
title: "ADR 0052: Name and identity"
type: decision
status: accepted
adr: 52
created: 2026-11-06
updated: 2026-11-06
tags: [decision, adr, brand]
aliases: [ADR 0052, R4, Name, os-release, Subarchy]
---

# ADR 0052: Name and identity

Decision map item R4. Accepted 2026-11-06.

## Decision

The distribution is **Subarchy**: sub + Arch + anarchy. What users see on
screen and type at the prompt is **SUBCULT**.

| Surface | Uses | Example |
|---|---|---|
| Boot menu, boot splash, login, lock screen, About screen, shell logo | **SUBCULT** mark and wordmark | Limine `interface_branding: SUBCULT`, Plymouth and SDDM artwork |
| Commands | **`subcult`** dispatcher ([[0046-distribution-cli\|ADR 0046]]) and `subcult-<group>-<action>` executables | `subcult theme set`, `subcult update` |
| Short alias | **`sub`** | `sub theme set` |
| User and system paths, plugin IDs, environment | **subcult** | `/usr/share/subcult/`, `~/.config/subcult/`, `subcult.<plugin>`, `SUBCULT_PATH` |
| OS identity | **Subarchy** | `/etc/os-release`: `NAME="Subarchy"`, `ID=subarchy`, `ID_LIKE=arch` |
| Packages and repository | **subarchy** | `subarchy`, `subarchy-keyring`, pacman repository `[subarchy]` |
| ISO, source repository, documentation | **Subarchy** | `subarchy-<version>-x86_64.iso`, `git.subcult.tv/…/subarchy` |

## Checks done (2026-11-06)

| Check | Result |
|---|---|
| Web search for "Subarchy" Linux | No product found; only the kernel's `subarch` build variable |
| Arch repositories and AUR | No package named `subarchy`, `subcult`, `sub`, `subc` or `scl` |
| Arch manual pages (man.archlinux.org) | No command `subcult`, `sub`, `subc` or `scl` |
| `sc` | Taken by an AUR spreadsheet program, so not used as the alias |
| GitHub user or organisation `subarchy` | Not found |
| `git.subcult.tv` user `subarchy`, repo `subculture-collective/subarchy` | Not found |
| Domains | `subarchy.com`, `.net`, `.org`, `.io`, `.sh` returned "no match" or "not found" from whois; `.dev` gave no answer |

This was not a formal trademark search.

## Options considered

| Option | Why not chosen |
|---|---|
| Subcarchy (repository working name) | The owner was not keen on it. |
| Subroot, Undercurrent, Subterra, Undir, Basement | Considered; the owner chose Subarchy. |
| SUBCULT Linux | Too close to Subcult OS, the event-operations product. |

## Consequences

- The `subcult` command and `subcult-*` executables collide with the SUBCULT
  rice's 61 `subcult-*` commands in `~/.local/bin` on `sputnik`. Installing
  Subarchy there means removing the rice first, or porting its commands into
  Subarchy under the same names ([[subcult-rice|SUBCULT rice]]).
- Two names to explain: Subarchy is the distribution, SUBCULT the brand it
  carries. The README and About screen say so in one line.
- `ID_LIKE=arch` lets tools that check for Arch work; Subarchy does not claim
  `omarchy`.
- The local checkout is still at `~/Work/Subcarchy`. Renaming the folder also
  needs the T3 project path changed; the Gitea repository is created as
  `subarchy` ([[0051-hosting-ci|ADR 0051]]).
- Branding work can start: Plymouth ([[0013-boot-splash|ADR 0013]]), SDDM
  ([[0030-login-manager|ADR 0030]]), Limine ([[0007-bootloader|ADR 0007]]),
  the editor layer ([[0045-editor|ADR 0045]]) and every row in
  [[branding-surfaces|Branding surfaces]].

## Progress

- 2026-11-08: the brand assets are in `branding/` (issue #62): the SUBCULT
  marks and lockups from the rice's brand kit, the studio's production logo
  set with its master mark and tokens, the three brand fonts (OFL) and the
  seven poster-press backgrounds, each with its source and commit in
  `branding/README.md`. The owner approved taking them as they are; the
  splash, greeter and screensaver art are built from them next (#73, #96).

Related: [[decision-map|Decision map]] · [[brand-identity|Brand identity]] · [[0046-distribution-cli|ADR 0046]] · [[0053-licence|ADR 0053]]
