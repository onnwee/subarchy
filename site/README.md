# site

The Subarchy landing page and user docs, as static HTML with no build step
and no backend. The canonical address is <https://subarchy.subcult.tv>; the
files in [deploy/](../deploy/) serve it.

## Preview

```sh
python3 -m http.server 18791 --bind 127.0.0.1 --directory site
```

Open `http://127.0.0.1:18791/` and `/docs/`. The pages follow the system's
light or dark setting; the button in the header switches between ink and
paper and remembers the choice.

## Keeping it accurate

Every fact on these pages comes from the repository. Change the page when
the source changes.

| On the page | Source |
|---|---|
| What the installer puts on the disk, the status table, the make targets | [README.md](../README.md) |
| The packages `make iso` needs in `build/repo` first | [tools/iso/build.sh](../tools/iso/build.sh), [packaging/aur/build.sh](../packaging/aur/build.sh) |
| What the installer asks, the time zone guess, the log path | [install/README.md](../install/README.md) |
| Unattended install keys | the header of [install/subarchy-install](../install/subarchy-install) |
| Default keys | [default/hypr/bindings.lua](../default/hypr/bindings.lua) |
| Command summaries and examples | the `subcult:summary` and `subcult:examples` headers in [bin/](../bin/) and the commands in [cmd/](../cmd/) |
| Switching themes | `pult help`, and the Pult profile in [default/theme/subarchy.toml](../default/theme/subarchy.toml) |
| Widget names and the count of 27 | the folders in [shell/widgets/](../shell/widgets/) |
| Bar and palette paths | [shell-and-look-design](../docs/plans/shell-and-look-design.md) |

## Brand

The wordmark, the SA_ marks, the icons, `assets/og.png` and the tokens in
`style.css` come from `studio/brands/subarchy` in `subcult-tv`. The wordmark
is the owner's ANSI art, drawn as SVG rectangles so it does not depend on a
font. Departure Mono 1.500 is in `fonts/` with its SIL Open Font License
text; it sets the headings, navigation, code and the landing page.

The docs prose is set in Dank Mono, which the owner licenses from its
author. Its licence forbids redistribution, so the three `.woff2` files are
not in git (`.gitignore` excludes `site/fonts/DankMono-*`); the deploy copies
them in from the owner's licensed copy. Without them the docs fall back to
Departure Mono, so a local preview still works.

## Formatting

Docs prose uses the classes in `style.css`:

- `<strong>` and `<em>` are coloured (acid and violet); Dank Mono also sets
  them bold and italic. Departure Mono has no bold or italic, so on the
  landing page they are colour only.
- Callouts, in the manner of Obsidian's: `<div class="callout note|tip|warning">`
  with a first `<p class="ct" data-mark="...">` title.
- `<ol class="steps">` for numbered steps, `<kbd>` for keys, `<blockquote>`
  for a sentence that should stand out.

## Checks

`make verify` runs `tools/test/site-check.py`: links and anchors, alt text,
button names, one `h1` per page, no inline styles, the CSP hash of the inline
theme script, and WCAG AA contrast for both themes. Lighthouse and the
keyboard and mouse tests need a browser; run them against the container
described in [deploy/](../deploy/).

The support block follows SUBCULT's site guidelines: one block on the
landing page and a quiet footer link, both to `https://subcult.tv/support`,
no prices, and no ask on the error page.
