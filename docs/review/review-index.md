---
title: "Review"
type: index
status: active
created: 2026-11-06
updated: 2026-11-13
tags: [index, review]
aliases: [Review checklist]
---

# Review

Documents that need an owner decision. Each proposal states a default so the
review can be a yes/no pass.

| Document | Decisions |
|---|---|
| [[0001-fork-strategy\|ADR 0001]] | Fork, overlay or rebuild |
| [[triage\|Plugin and add-on triage]] | What ships by default, as optional, or not at all |
| [[open-questions\|Open questions]] | Name, licence, hosting, hardware targets, ISO |
| [[app-list\|App list]] | Which apps ship, which are offered, default per role (owner writes) |
| [[rice-port-review\|Rice port review]] | Which SUBCULT rice features to port, rethink or skip |
| [[next-decisions\|Next decisions]] | Everything still open: new decisions, design work, assumptions, questions |
| [[first-install\|First install on sputnik]] | Runbook for the first real install, and what is and is not tested |

## How to review

1. Start with [[next-decisions]]: it lists everything still open.
2. Each document states a default. Change what you disagree with and leave
   the rest.
3. When a review document is done, set its `review` property to `done`. It
   then drops out of the list below.

![[docs.base#Needs review]]

Related: [[home|Docs home]]
