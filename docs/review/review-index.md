---
title: "Review"
type: index
status: active
created: 2026-11-06
updated: 2026-11-20
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
| [[pending-decisions\|Pending decisions]] | Every open owner decision once, with its issue and a default (2026-11-20) |
| [[next-decisions\|Next decisions]] | Frozen 2026-11-07: the decisions open then, kept as history |
| [[first-install\|First install on sputnik]] | Runbook for the first real install, and what is and is not tested |
| [[nvidia-rtd3-source-qualification\|NVIDIA RTD3 source qualification]] | Reproduce #1512's source applicability check and qualify a candidate before the remaining Zen battery test |
| [[test-checklist\|Hardware test checklist]] | What the owner tests by hand on sputnik, and the decisions still open before release |
| [[shell-display-findings\|Shell and display finding acceptance]] | #98 evidence, remaining physical-monitor check and the parent's next frame-attribution probe |
| [[pult-app-targets\|Pult application targets]] | Package checks and remaining native acceptance for swayimg, VS Code and Obsidian (#78) |
| [[go-application-notices\|Go application notice retention]] | #243 package retention, later xlab licence evidence, and remaining #84 source-delivery/image gates |
| [[release-licence-notices\|Release licence notice audit]] | #241 notice repair, checked package bytes and remaining final-image/owner limits under #84 |
| [[release-notes-0.0.0\|Release notes 0.0.0]] | Draft for #84 (checklist Q21): tested hardware, untested ports, limitations and what is not in the release; tag-time fields still empty |

## How to review

1. Start with [[pending-decisions]]: it lists everything still open.
2. Each document states a default. Change what you disagree with and leave
   the rest.
3. When a review document is done, set its `review` property to `done`. It
   then drops out of the list below.

![[docs.base#Needs review]]

Related: [[home|Docs home]]
