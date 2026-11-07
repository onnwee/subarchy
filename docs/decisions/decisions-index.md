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
| [[0006-gpu-drivers\|0006]] | GPU drivers |
| [[0007-bootloader\|0007]] | Bootloader |
| [[0008-initramfs\|0008]] | Initramfs and kernel images |
| [[0009-disk-layout\|0009]] | Disk layout and filesystem |
| [[0010-disk-encryption\|0010]] | Disk encryption |
| [[0011-snapshots\|0011]] | Snapshots and rollback |
| [[0012-secure-boot\|0012]] | Secure Boot |
| [[0013-boot-splash\|0013]] | Boot splash |
| [[0014-swap-hibernation\|0014]] | Swap and hibernation |
| [[0015-init-system\|0015]] | Init and service manager |
| [[0016-networking\|0016]] | Networking and Wi-Fi |
| [[0017-audio\|0017]] | Audio |
| [[0018-bluetooth\|0018]] | Bluetooth |
| [[0019-firewall\|0019]] | Firewall |
| [[0020-dns\|0020]] | DNS and name resolution |
| [[0021-power\|0021]] | Power and thermal management |
| [[0022-printing\|0022]] | Printing and device discovery |
| [[0023-authentication\|0023]] | Secrets and login factors |
| [[0024-time-locale-input\|0024]] | Time zone, locale and input methods |

Related: [[home|Docs home]]
