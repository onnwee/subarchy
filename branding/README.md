# branding

The SUBCULT brand assets Subarchy's screens are built from (ADR 0052, issue
#62): marks and lockups, the studio's production logo set and tokens, the
brand fonts, and the seven poster-press backgrounds. [Branding
surfaces](../docs/inventory/branding-surfaces.md) lists every Omarchy location
these replace; `os-release.in` is the identity file the package installs.

Approved by the owner on 2026-11-08: pull the assets from the SUBCULT theme
installed on `sputnik` and from the studio repository, as they are. Nothing
here is Omarchy's: the Omarchy-derived Plymouth script and ASCII logo on
`sputnik` were left behind, and Subarchy's splash, greeter and screensaver
art are built from these files (issues #73, #96, #121).

| Folder | What | Source |
|---|---|---|
| `marks/` | The outlined SUBCULT marks and lockups (primary, dark, compact, mono) and the fisheye circle logo | `subcult-omarchy-rice` `theme/brand/`, commit `05a7b50` (2026-10-05); the same files are installed as `~/.config/omarchy/themes/subcult/brand/` |
| `studio/mark-master.svg` | The owner-authored master mark: filled S and underscore, outlined C, tilted green block, registration lines and terminal square. Preserve geometry, overlap and layer order | `subcult-studio` `branding/2026-10-01-packs/references/subcult-mark-master.svg`, commit `1259191` (2026-10-01) |
| `studio/logos/` | The production set rendered from the master: lockups and marks in primary, dark, light and mono, each editable and outlined (22 SVGs; the PNG exports stay in the studio) | `subcult-studio` `branding/2026-10-01-packs/brands/subcult/logos/` |
| `studio/tokens.json`, `tokens.css`, `GUIDE.md`, `alt-text.md` | Colour roles (base `#8b5cf6`, text `#100b19`, accent `#00ff88`, secondary `#f0ece4`), type (Oswald display, Space Grotesk body, JetBrains Mono labels), spacing, clear space and the usage rules | `subcult-studio` `branding/2026-10-01-packs/brands/subcult/` |
| `fonts/` | Oswald, Space Grotesk and JetBrains Mono with their SIL Open Font License texts | `subcult-omarchy-rice` `theme/brand/fonts/` (the studio copies are Git LFS pointers) |
| `backgrounds/` | Seven 2560×1440 poster-press wallpapers rendered from the marks, with `ARTWORK.md` (composition and provenance) and `backgrounds.sha256` | `~/.config/omarchy/themes/subcult/backgrounds/` on `sputnik`, the rice's `scripts/build-wallpapers` output |

The marks, logos and backgrounds are SUBCULT's own work. The fonts are
redistributed under the OFL files beside them. Check the backgrounds with
`cd branding/backgrounds && sha256sum --check backgrounds.sha256`.

The palette Theme Tender ships for Subarchy (`default/theme/palette.json`,
subcult-minimal) keeps these roles: violet, ink, acid and paper.
