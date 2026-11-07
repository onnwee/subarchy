---
title: "App list"
type: review
status: draft
review: pending
created: 2026-11-06
updated: 2026-11-06
tags: [review, apps]
aliases: [Default apps list, App catalogue]
---

# App list

The owner's list of apps for Subcarchy. The installer and the default-app
picker read it ([[0044-default-apps|ADR 0044]]). Source material:
[[sputnik-apps|Apps on sputnik]] and Omarchy's base package list.

## Columns

| Column | Meaning |
|---|---|
| App | Display name |
| Role | Role it can fill, if any (see below); blank for apps without a role |
| Preinstalled | `yes` if every install gets it |
| Default | `yes` if it is the role's default; one per role |
| Source | `repo`, `aur` (rebuilt in Subcarchy's repo) or `flatpak` |
| Package | Package or Flatpak ID |
| Notes | Integration needs, licence, overlaps |

## Roles

Roles decided so far, with the default each ADR set. Add roles as needed.

| Role | Decided default |
|---|---|
| terminal | kitty ([[0040-terminal\|ADR 0040]]) |
| editor | Neovim with Subcarchy's LazyVim config ([[0045-editor\|ADR 0045]]) |
| browser | Zen ([[0042-browser\|ADR 0042]]) |
| file-manager | Dolphin ([[0043-file-manager\|ADR 0043]]) |
| terminal-file-manager | yazi ([[0043-file-manager\|ADR 0043]]) |

## Apps

| App | Role | Preinstalled | Default | Source | Package | Notes |
|---|---|---|---|---|---|---|
|  |  |  |  |  |  |  |

Related: [[0044-default-apps|ADR 0044]] · [[sputnik-apps|Apps on sputnik]]
