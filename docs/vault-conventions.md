---
title: "Vault conventions"
type: guide
status: active
created: 2026-11-06
updated: 2026-11-06
tags: [guide, obsidian]
aliases: [Obsidian setup, Frontmatter guide]
---

# Vault conventions

The repository root is an Obsidian vault. Open it with **Open folder as
vault**, then run the plugin installer once (see [[#Plugins]]).

## Where notes live

All notes are under `docs/`. Obsidian hides the build folders (`bin/`,
`config/`, `shell/` and the rest) and `tools/` through *Excluded files* in
`.obsidian/app.json`, so code does not crowd search or the graph. The root
`README.md` and the build-folder READMEs are written for the Git forge and use
ordinary Markdown links.

## Links

- Use wikilinks between notes: `[[branding-surfaces]]`, or
  `[[branding-surfaces|Branding surfaces]]` for display text.
- Inside a table, escape the pipe: `[[triage\|Triage]]`.
- Link to a heading with its text: `[[local-packages#mise tools (63)|list]]`.
- Every note name is unique, so a bare name always resolves. Index notes are
  named for their folder (`inventory-index`, `decisions-index`,
  `review-index`), not `README`. Generated notes carry an `omarchy-` or
  `local-` prefix.
- End each note with a `Related:` line naming the notes it builds on. Those
  links feed backlinks and the graph.
- Obsidian rewrites links on rename (`alwaysUpdateLinks`).

The Git forge does not render wikilinks; they show as raw double-bracket text there. Read
the notes in Obsidian, or follow the root `README.md` on the forge.

## Properties

Every note starts with YAML frontmatter. Types are fixed in
`.obsidian/types.json`.

| Property | Type | Used on | Values |
|---|---|---|---|
| `title` | text | all | Human title; matches the H1 |
| `type` | text | all | `index`, `inventory`, `decision`, `brand`, `review`, `plan`, `guide` |
| `status` | text | all | `active`, `draft`, `proposed`, `accepted`, `rejected`, `superseded`, `generated` |
| `review` | text | review notes | `pending`, `done` |
| `adr` | number | decisions | ADR number |
| `host`, `observed` | text, date | inventory | Machine and date the facts were observed |
| `scope`, `source` | text | generated inventory | `omarchy` or `local`; the command or path read |
| `created`, `updated` | date | hand-written notes | ISO dates; update `updated` when content changes |
| `tags` | tags | all | YAML list, lowercase |
| `aliases` | aliases | where useful | Other names the note answers to in search and links |

Generated notes get their properties from `tools/inventory/collect.py`. Edit
the script, not the notes.

## Views

Bases (a core plugin) turns properties into tables. The view files are in
`docs/views/` and are embedded in index notes:

| View file | Views | Embedded in |
|---|---|---|
| `docs.base` | *Needs review* (status `draft` or `proposed`, or `review: pending`), *All notes* grouped by type | [[home]], [[review-index]] |
| `decisions.base` | ADRs by number with status | [[decisions-index]] |
| `inventory.base` | Inventory notes grouped by status, with scope, date and source | [[inventory-index]] |

## Templates

The core Templates plugin reads `docs/templates/`:

- [[adr-template]]: a new decision record. Replace `NNNN` and set `adr`.
- [[note-template]]: any other note.

New notes are created in `docs/` by default.

## Plugins

Core plugins in use: Bases, Properties, Templates, Backlinks, Outgoing links,
Graph, Outline, Bookmarks, Tags, Canvas.

Three community plugins, all ones already used in the SUBCULT and Machinum
vaults:

| Plugin | Version | Licence | Why |
|---|---|---|---|
| Homepage (`homepage`) | 4.5.0 | MIT | Opens [[home]] when the vault starts |
| Dataview (`dataview`) | 0.5.68 | MIT | Lists open roadmap tasks on [[home]]; Bases cannot query tasks |
| Advanced Tables (`table-editor-obsidian`) | 0.23.2 | GPL-3.0 | Most notes are tables; it formats and navigates them |

Plugin code is not committed, to keep third-party code out of the
repository ([[0053-licence|ADR 0053]]). Install the pinned releases:

```bash
python3 tools/obsidian/install-plugins.py          # download and verify
python3 tools/obsidian/install-plugins.py --check  # verify only
```

The script downloads each file from the plugin's GitHub release and checks it
against the SHA-256 in `tools/obsidian/plugins.json`. Then enable community
plugins in Obsidian if it asks. If Obsidian later updates a plugin itself, it
rewrites `main.js`, and `--check` reports it as modified; update the pin or
rerun the installer.

Plugin settings that matter are committed: `homepage/data.json`. Other
plugin settings, `workspace.json` and `graph.json` stay local
(`.gitignore`).

Related: [[home|Docs home]] · [[inventory-index|Inventory]]
