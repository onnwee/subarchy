---
title: "ADR 0053: Licence"
type: decision
status: accepted
adr: 53
created: 2026-11-06
updated: 2026-11-13
tags: [decision, adr, legal]
aliases: [ADR 0053, R5, Licence, GPL]
---

# ADR 0053: Licence

Decision map item R5. Accepted 2026-11-06.

## Decision

Subarchy's own code is licensed under the **GNU General Public License,
version 3 or later** (`GPL-3.0-or-later`). The text is in `LICENSE` at the
repository root.

The owner chose "GPL-3.0" and confirmed "or later" on 2026-11-07.

## Borrowed code keeps its licence

| Source | Licence | What that requires here |
|---|---|---|
| Omarchy (`omacom/omarchy`, `omarchy-iso`) | MIT | Keep the copyright and permission notice with copied files |
| SUBCULT rice (code) | MIT | Same |
| LazyVim starter | Apache-2.0 | Keep the licence and NOTICE, mark changed files |
| SUBCULT fonts | SIL OFL 1.1 | Ship the OFL text with the fonts |
| SUBCULT marks and artwork | Rice's `ASSETS_LICENSE.md` | Check before shipping in an image |

MIT and Apache-2.0 code can be combined into a GPL-3.0 work; the combined
distribution is then under GPL-3.0 terms.

## Options considered

| Option | Why not chosen |
|---|---|
| MIT | Allows closed derivatives. |
| Apache-2.0 | Allows closed derivatives. |

## Third-party licences while private

The owner holds the rights to all SUBCULT assets and is not concerned with
third-party licences while the repository stays private (2026-11-07). The
licence checks listed below become a release gate before anything is made
public.

## Consequences

- Forks and derivatives of Subarchy's code must stay open under the GPL.
- Copied files need a header recording their origin and original licence.
- Community shell plugins ported under [[0035-plugin-api|ADR 0035]] need
  GPL-compatible licences.
- GPL-3.0 plugin code such as Obsidian's Advanced Tables could now be
  committed, but the vault still installs plugins from pinned releases to keep
  third-party code out of the repository.

## Progress

- 2026-11-13: the app-list packages Subarchy now rebuilds into its
  repository (`packaging/aur/`) carry these licences, to check at the
  release gate:

  | Package | Licence | Note |
  |---|---|---|
  | `claude-code` | Proprietary (Anthropic) | Anthropic's terms page, shipped as the package licence, says preinstalling Claude Code in a product requires agreeing to its Commercial Terms of Service, shipping the binary unmodified and keeping its sign-in methods. The package runs the binary as published, through a wrapper that only sets `DISABLE_UPDATES` and `DISABLE_INSTALLATION_CHECKS`. The registry is public, so adding the package redistributes the binary: the owner accepted those terms before it was added |
  | `proton-mail-bin`, `proton-pass-bin`, `proton-pass-cli`, `proton-authenticator-bin` | GPL-3.0-or-later | `proton-pass-bin` also bundles Electron (MIT) |
  | `proton-drive-cli-bin`, `cliamp`, `ttfx`, `voxtype-bin` | MIT | `voxtype-bin` ships no models; the user downloads one |
  | `localsend-bin` | Apache-2.0 |  |

  `displaylink` and the NVIDIA 580xx packages carry their vendors' own
  licences (`custom`); their redistribution terms also need checking.
- 2026-11-13: the GitHub repository is public. The third-party checks
  (SUBCULT marks and artwork under the rice's `ASSETS_LICENSE.md`, origin
  headers on borrowed files) are not recorded as done; this is the
  owner's call.

Related: [[decision-map|Decision map]] · [[0052-name-identity|ADR 0052]]
