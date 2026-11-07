---
title: "Review"
type: index
status: active
created: 2026-11-06
updated: 2026-11-06
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

## How to review

1. Read [[0001-fork-strategy|ADR 0001]] and set its `status` property to
   `accepted` or `rejected`. Most other choices follow from it.
2. Go through [[triage]] and change any **Proposed** value you
   disagree with. Leave the rest.
3. Answer what you can in [[open-questions]]. Unanswered
   items stay open; they do not block the inventory.
4. When a review document is done, set its `review` property to `done`. It
   then drops out of the list below.

![[docs.base#Needs review]]

Related: [[home|Docs home]]
