---
title: "Subarchy documentation"
type: index
status: active
created: 2026-11-06
updated: 2026-11-08
tags: [index]
aliases: [Docs home, Home]
---

# Subarchy documentation

Subarchy is a planned SUBCULT-branded distribution built from Omarchy. These
notes describe the state observed on `sputnik` on 2026-11-06 with Omarchy
4.5.0-3. Treat counts as that snapshot; rerun
`python3 tools/inventory/collect.py` for current numbers.

## Sections

| Section | Contents | Edited by |
|---|---|---|
| [[inventory-index\|Inventory]] | What exists today: upstream Omarchy and the additions on `sputnik` | Hand-written summaries; `generated/` is script output |
| [[decisions-index\|Decisions]] | Architecture decision records | Hand-written, one note per decision |
| [[brand-identity\|Brand identity]] | Name, palette, marks and voice | Hand-written draft |
| [[review-index\|Review]] | Items waiting on an owner decision | Hand-written checklists |
| [[roadmap\|Roadmap]] | Phases from inventory to installable image | Hand-written |
| [[ci-runner\|KVM CI runner]] | Runner limits, capability check and recovery | Hand-written |
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
