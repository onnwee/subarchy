# Subcarchy

Subcarchy is a planned SUBCULT-branded desktop distribution built from
[Omarchy](https://omarchy.org/) (Arch Linux and Hyprland). "Subcarchy" is the
working name taken from this repository; it is not a settled brand.

The repository is at the inventory stage. Nothing here builds or installs yet.
The documents under [`docs/`](docs/home.md) record what Omarchy 4.5.0 ships,
what has been added on top of it on the `sputnik` laptop, and the decisions that
need review before any build work starts.

## Start here

| Document | What it covers |
|---|---|
| [Inventory overview](docs/inventory/inventory-index.md) | Counts, sources and how to regenerate the inventory |
| [Omarchy component map](docs/inventory/omarchy-overview.md) | What upstream Omarchy is made of |
| [Local additions](docs/inventory/local-additions.md) | Plugins, themes, tools and services added beyond Omarchy |
| [SUBCULT rice](docs/inventory/subcult-rice.md) | The existing `subcult-omarchy-rice` 2.0.0 overlay |
| [Branding surfaces](docs/inventory/branding-surfaces.md) | Every place the Omarchy name and logo appear |
| [ADR 0001: fork strategy](docs/decisions/0001-fork-strategy.md) | Fork, overlay or rebuild (proposed) |
| [Review checklist](docs/review/review-index.md) | Keep, replace or drop decisions waiting on the owner |
| [Roadmap](docs/roadmap.md) | Phases from inventory to an installable image |

## Repository layout

The top-level directories mirror Omarchy's packaged tree
(`/usr/share/omarchy`), so upstream files can be compared or merged path for
path. Each one holds only a README until build work starts.

```text
applications/  default desktop entries and web apps      (Omarchy: applications/)
bin/           subcarchy-* commands                       (Omarchy: /usr/bin/omarchy-*)
branding/      logos, os-release, Plymouth, SDDM, Limine  (Omarchy: logo.*, icon.*, etc-overrides/, default/plymouth)
config/        user config templates copied to ~/.config (Omarchy: config/)
default/       system defaults sourced at runtime        (Omarchy: default/)
install/       installer scripts and package lists        (Omarchy: install/)
iso/           image builder configuration                (Omarchy: separate ISO builder)
migrations/    upgrade migrations                         (Omarchy: migrations/)
packaging/     PKGBUILDs and the pacman repository        (Omarchy: pkgs.omarchy.org)
shell/         Quickshell plugins and shell code          (Omarchy: shell/)
themes/        themes                                     (Omarchy: themes/)
tools/         inventory collector and Obsidian plugin installer
docs/          Obsidian notes: inventory, decisions, brand, review
```

## Reading in Obsidian

The repository root is an Obsidian vault. Notes in `docs/` use frontmatter
properties and wikilinks, which this forge shows as plain text, so Obsidian is
the better reader for them.

```bash
python3 tools/obsidian/install-plugins.py   # pinned, hash-checked plugins
```

Then open the folder with **Open folder as vault**. The vault opens on
`docs/home.md`. [Vault conventions](docs/vault-conventions.md) covers the
properties, link rules, Bases views, templates and the three community plugins.

## Regenerating the inventory

Run on an Omarchy machine:

```bash
python3 tools/inventory/collect.py
```

It rewrites `docs/inventory/generated/` from the live system. See
[the inventory index](docs/inventory/inventory-index.md) for what it reads and what it
leaves out.

## Licence

GPL-3.0-or-later; see [LICENSE](LICENSE) and
[ADR 0053](docs/decisions/0053-licence.md). Code borrowed from Omarchy (MIT)
and the LazyVim starter (Apache-2.0) keeps its original licence notices.
