---
title: "Subarchy documentation"
type: index
status: active
created: 2026-11-06
updated: 2026-11-13
tags: [index]
aliases: [Docs home, Home]
---

# Subarchy documentation

Subarchy is a SUBCULT-branded Arch distribution, built from scratch and
borrowing from Omarchy. It is in development with no release: the live ISO
builds in CI, boots in a VM and installs from that image into an encrypted VM
disk, and it runs on one laptop (`sputnik`). GitHub
`subculture-collective/subarchy` is the source, with pull requests and
issues; Gitea is a fast-forward mirror ([[0051-hosting-ci|ADR 0051]]).

## Sections

| Section | Contents | Edited by |
|---|---|---|
| [[inventory-index\|Inventory]] | Upstream Omarchy and the additions on `sputnik`, observed on 2026-11-06 with Omarchy 4.5.0-3; rerun `python3 tools/inventory/collect.py` for current numbers | Hand-written summaries; `generated/` is script output |
| [[decisions-index\|Decisions]] | Architecture decision records | Hand-written, one note per decision |
| [[brand-identity\|Brand identity]] | Name, palette, marks and voice | Hand-written draft |
| [[review-index\|Review]] | Items waiting on an owner decision | Hand-written checklists |
| [[roadmap\|Roadmap]] | Phases from inventory to installable image | Hand-written |
| [[ci-runner\|KVM CI runner]] | Runner limits, capability check and recovery | Hand-written |
| [[package-publishing\|Package publishing]] | Main-only uploads, signature checks and credential rotation | Hand-written |
| [[vault-conventions\|Vault conventions]] | Properties, links, views, templates and plugins | Hand-written |

## Waiting on review

![[docs.base#Needs review]]

## Open roadmap items

```dataview
TASK
FROM "docs"
WHERE !completed
GROUP BY file.link
```

## All notes

![[docs.base#All notes]]
