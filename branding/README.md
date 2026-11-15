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

`marks/subarchy-wordmark-dark.svg` is the SUBARCHY wordmark from the
Subarchy brand pack (`subcult-tv` `studio/brands/subarchy/logos/wordmark-dark.svg`
at `e9a9edf`, SHA-256 `07f37478…a955`), drawn from the owner's ANSI art.

On 2026-11-15 the owner selected the Bloody SUBCULT treatment for the
login and session lock screens, with an ASCII clock and the website's typography.
`marks/subcult-wordmark-dark.svg` is the unchanged selected Studio export,
from `subcult-tv` `studio/brands/subarchy/logos/subcult-dark.svg` at
`efb1adb39d60843fb32537ba6c09fca1ffe17a46`, SHA-256
`7feae64445be82b5550d48d5485f0e61db87a270c2f2bf7ff30f69a1c3193e19`.
The login and lock screens' Departure Mono font is the existing
`site/fonts/DepartureMono-Regular.woff2`; packaging includes its adjacent
OFL text. The font's SHA-256 is
`5b4fed1daa90708aa9c6ee1190abca9dc22164a1c1def0020386e46b61038cfb`,
matching the live website's font on that date.

The system screens show art sets (ADR 0052) that
`tools/branding/screens.sh` builds during packaging into
`/usr/share/subcult/screens/`: `subarchy` (the wordmark, at whole-pixel
sizes) and `subcult` (the mark at boot, the Bloody wordmark at login and
lock). By default the boot splash uses
`subarchy`, and the greeter and lock use their `subcult` art. Both wordmarks are rendered in whole cells and centred on their
canvas. The original SVGs and their geometry stay unchanged.

The palette Theme Tender ships for Subarchy (`default/theme/palette.json`,
subcult-minimal) keeps these roles: violet, ink, acid and paper.
