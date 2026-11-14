# site

The Subarchy landing page and user docs, as static HTML with no backend.
The canonical address is <https://subarchy.subcult.tv>; the files in
[deploy/](../deploy/) serve it.

The HTML pages are generated. Edit the sources in
[tools/site/pages/](../tools/site/pages/), then run
`python3 tools/site/build.py`, which writes the pages and `sitemap.xml` here.
`style.css`, `app.js`, `assets/` and `fonts/` are edited in place. The
pages link `style.css` and `app.js` with a hash of their contents
(`?v=…`), because Cloudflare keeps those two in browsers for hours: run the
build after editing either, and `make verify` fails until you do.

## Preview

```sh
python3 -m http.server 18791 --bind 127.0.0.1 --directory site
```

Open `http://127.0.0.1:18791/` and `/docs/`; the error page needs the
container in [deploy/](../deploy/). The pages follow the system's
light or dark setting; the button in the header switches between ink and
paper and remembers the choice.

## Keeping it accurate

Every fact on these pages comes from the repository. Change the page when
the source changes.

The docs describe Subarchy as released: a downloaded ISO installed on a
real machine, with the behaviour the accepted decision records set out. They
do not track what is still unfinished. The landing page's "Where it stands"
table and the [roadmap](../docs/roadmap.md) say what is checked today; how
to build the ISO before there is a download is on the Developers page.

| On the page | Source |
|---|---|
| What the installer puts on the disk, the status table, the make targets | [README.md](../README.md) |
| The packages `make iso` needs in `build/repo` first | [tools/iso/build.sh](../tools/iso/build.sh), [packaging/aur/build.sh](../packaging/aur/build.sh) |
| What the installer asks, the time zone guess, the log path | [install/README.md](../install/README.md) |
| Download, USB stick, Secure Boot off to boot | the release plan in [marketing-packet](../docs/marketing/marketing-packet.md), [ADR 0012](../docs/decisions/0012-secure-boot.md) |
| Secure Boot and TPM unlock steps | `bin/subcult-secureboot-setup`, `bin/subcult-disk-tpm`, [ADR 0010](../docs/decisions/0010-disk-encryption.md) |
| What `subcult update` does, factory reset | [ADR 0026](../docs/decisions/0026-update-model.md), [ADR 0056](../docs/decisions/0056-quality-of-life.md) |
| Lock screen crash recovery | [ADR 0070](../docs/decisions/0070-lock-crash-recovery.md) |
| What Pult themes, the offline manual | issues #77 and #78, [ADR 0067](../docs/decisions/0067-user-manual.md) |
| Unattended install keys | the header of [install/subarchy-install](../install/subarchy-install) |
| Default keys | [default/hypr/bindings.lua](../default/hypr/bindings.lua) |
| Launcher prefixes and files | the Launcher section of [shell/README.md](../shell/README.md) |
| The command tables | `tools/site/commands.json`, from `subcult commands --json`; refresh it with `make site-commands` |
| Shell aliases, functions and keys | [default/shell/](../default/shell/) `aliases.sh`, `functions.sh` and `zshrc` |
| Switching themes | `pult help`, and the Pult profile in [default/theme/subarchy.toml](../default/theme/subarchy.toml) |
| Widget names and the count of 27 | the folders in [shell/widgets/](../shell/widgets/) |
| Bar and palette paths | [shell-and-look-design](../docs/plans/shell-and-look-design.md) |

## Plugins pages

`/plugins/` and one page per shell widget are generated too. The facts come
from the code: name, id, version, kind, panel, timers, servers and default
settings from each `shell/widgets/*/manifest.json` (through
`shell/widgets/index.json`), and whether and where the widget is in the bar
from `default/shell/bar.json`. Only the wording is the site's own, in
[tools/site/plugins.json](../tools/site/plugins.json): a category, a
one-line summary, a paragraph or two, one line per setting, and an optional
`example` for the settings snippet, for a plugin that stays hidden until a
setting is filled in. The build
stops when a widget has no entry there or a setting is not described, so a
new or changed widget fails `make verify` until its page is written and the
site rebuilt. `"hidden": true` leaves an entry out (`dell-power`, an alias
of Battery).

## Brand

The wordmark, the SA_ marks, the icons, `assets/og.png` and the tokens in
`style.css` come from `studio/brands/subarchy` in `subcult-tv`. The wordmark
is the owner's ANSI art, drawn as SVG rectangles so it does not depend on a
font. Departure Mono 1.500 is in `fonts/` with its SIL Open Font License
text; it sets the headings, navigation, code and the landing page.

The docs prose is set in Victor Mono 1.5.6, also under the OFL
(`fonts/victormono-OFL.txt`), for its cursive italics. The files are the
Latin subset from fontsource 5.3.0: medium (500) for text and italics, bold
(700) for `<strong>`.

## Writing the docs

The docs are a reference: short pages, tables, one idea per line. Depth
belongs on the Developers page or in the repository, not on the general
pages. Name Omarchy only once, as the inspiration on the landing page;
`site-check.py` enforces it.

In a page source, the build expands:

| Write | Becomes |
|---|---|
| `[[keys]]`, `[[keys#launcher\|label]]` | A link to a docs page or one of its sections |
| `[[TPM]]` | A link to that glossary entry (`<dt id="tpm">`) |
| `{{Super+Shift+B}}`, `{{Super+_arrow_}}` | Keyboard keys; `_word_` is a placeholder, not a key |
| `<!-- commands -->` | The command tables |

A wikilink that matches no page or glossary term stops the build. Links to
other sites get `target="_blank"`, `rel="noopener"` and a hidden "(opens in
a new tab)".

## Formatting

Docs prose uses the classes in `style.css`:

- `<strong>` and `<em>` are coloured (acid and violet); Victor Mono also sets
  them bold and in cursive italics. Departure Mono has no bold or italic, so on the
  landing page they are colour only.
- Callouts, in the manner of Obsidian's: `<div class="callout note|tip|warning">`
  with a first `<p class="ct" data-mark="...">` title.
- `<ol class="steps">` for numbered steps, `<kbd>` for keys, `<blockquote>`
  for a sentence that should stand out.

On wide screens the docs sidebar can be hidden with its `« hide` button; the
choice is kept in `localStorage` (`subarchy-side`) and applied by the inline
script before the first paint, so changing that script means a new CSP hash
in [deploy/nginx.conf](../deploy/nginx.conf) (`site-check.py` checks it).
While hidden, hovering or tabbing to the `»` button floats the pages over the
text, and Escape puts them away. Native scroll bars are hidden everywhere;
`app.js` draws a 2px accent stroke for the page and for each scrolling box.

## Checks

`make verify` runs `tools/site/build.py --check` (the pages match their
sources) and `tools/test/site-check.py`: links and anchors, alt text,
button names, one `h1` per page, no inline styles, the CSP hash of the inline
theme script, new-tab links, the single Omarchy mention, and WCAG AA
contrast for both themes. Lighthouse and the
keyboard and mouse tests need a browser; run them against the container
described in [deploy/](../deploy/).

The support block follows SUBCULT's site guidelines: one block on the
landing page and a quiet footer link, both to `https://subcult.tv/support`,
no prices, and no ask on the error page.
