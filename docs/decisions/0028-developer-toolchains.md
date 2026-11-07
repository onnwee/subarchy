---
title: "ADR 0028: Developer toolchains"
type: decision
status: accepted
adr: 28
created: 2026-11-06
updated: 2026-11-06
tags: [decision, adr, packages, development]
aliases: [ADR 0028, P4, mise]
---

# ADR 0028: Developer toolchains

Decision map item P4. Accepted 2026-11-06.

## Decision

**mise** manages language runtimes and developer CLIs per user and per
project (`mise.toml`), with shims on `PATH`. pacman packages remain for
anything the OS itself depends on.

## Options considered

| Option | Why not chosen |
|---|---|
| System packages only | One version per language, upgraded on Arch's schedule. |
| Nix devshells | Adds the Nix store and its learning curve. |

## Borrowed from Omarchy

`install/user/mise.sh` and `mise-work.sh`, and `omarchy install` entries for
languages. Omarchy installs `mise-bin` from its repository; Arch's `extra`
has `mise` (2026.10.17 on 2026-11-06), which avoids a rebuild.

## Consequences

- OS scripts must not depend on mise-managed runtimes; they use system
  `python`, `bash` and so on.
- `sputnik` already runs 63 tools through mise.

Related: [[decision-map|Decision map]] · [[0027-third-party-software|ADR 0027]]
