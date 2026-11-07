---
title: "ADR 0053: Licence"
type: decision
status: accepted
adr: 53
created: 2026-11-06
updated: 2026-11-06
tags: [decision, adr, legal]
aliases: [ADR 0053, R5, Licence, GPL]
---

# ADR 0053: Licence

Decision map item R5. Accepted 2026-11-06.

## Decision

Subarchy's own code is licensed under the **GNU General Public License,
version 3 or later** (`GPL-3.0-or-later`). The text is in `LICENSE` at the
repository root.

The owner chose "GPL-3.0"; "or later" is the assumed variant, matching
common practice and the SPDX file used. Change to `GPL-3.0-only` here and in
file headers if later versions should not apply.

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

## Consequences

- Forks and derivatives of Subarchy's code must stay open under the GPL.
- Copied files need a header recording their origin and original licence.
- Community shell plugins ported under [[0035-plugin-api|ADR 0035]] need
  GPL-compatible licences.
- GPL-3.0 plugin code such as Obsidian's Advanced Tables could now be
  committed, but the vault still installs plugins from pinned releases to keep
  third-party code out of the repository.

Related: [[decision-map|Decision map]] · [[0052-name-identity|ADR 0052]]
