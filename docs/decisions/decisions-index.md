---
title: "Decisions"
type: index
status: active
created: 2026-11-06
updated: 2026-11-06
tags: [index, decision]
aliases: [ADR index]
---

# Decisions

Architecture decision records. One file per decision, numbered in order. A
record starts as **proposed** and moves to **accepted**, **rejected** or
**superseded** after owner review. Do not rewrite an accepted record; add a new
one that supersedes it.

Each record's `status` property holds its state. Create a new record from
`docs/templates/adr-template.md` (Templates: *Insert template*).

![[decisions.base]]

The [[decision-map|decision map]] lists every decision still to take, in
order.

| ADR | Title |
|---|---|
| [[0001-fork-strategy\|0001]] | How Subcarchy relates to Omarchy |
| [[0002-base-distribution\|0002]] | Base distribution |
| [[0003-cpu-architectures\|0003]] | CPU architectures |
| [[0004-kernel\|0004]] | Kernel |
| [[0005-firmware\|0005]] | Firmware and microcode |

Related: [[home|Docs home]]
