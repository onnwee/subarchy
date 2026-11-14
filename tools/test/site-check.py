#!/usr/bin/env python3
"""Static checks for site/: what Lighthouse and the browser tests would catch
before a deploy, run without a browser.

- every page parses, has one h1, a lang, a title and a description
- every img has an alt attribute; every button has a name
- internal links and #anchors resolve to files and ids that exist
- no inline style attributes, and every inline script matches the CSP hash
  in deploy/nginx.conf
- each theme's text and accent colours meet WCAG AA contrast on its grounds
"""
import base64
import hashlib
import html.parser
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parents[2]
SITE = ROOT / "site"
PAGES = sorted(str(p.relative_to(SITE)) for p in SITE.rglob("*.html"))
errors = []


class Page(html.parser.HTMLParser):
    def __init__(self):
        super().__init__(convert_charrefs=True)
        self.ids, self.links, self.scripts = set(), [], []
        self.h1 = 0
        self.lang = self.title = self.desc = False
        self.img_no_alt = 0
        self.inline_style = 0
        self.buttons = []  # [has_name]
        self._script = None
        self._button = None
        self._title = False

    def handle_starttag(self, tag, attrs):
        a = dict(attrs)
        if "id" in a:
            self.ids.add(a["id"])
        if "style" in a:
            self.inline_style += 1
        if tag == "html" and a.get("lang"):
            self.lang = True
        if tag == "title":
            self._title = True
        if tag == "meta" and a.get("name") == "description" and a.get("content"):
            self.desc = True
        if tag == "h1":
            self.h1 += 1
        if tag == "img" and "alt" not in a:
            self.img_no_alt += 1
        if tag in ("a", "link") and a.get("href"):
            self.links.append(a["href"])
        if tag in ("img", "script") and a.get("src"):
            self.links.append(a["src"])
        if tag == "script" and not a.get("src"):
            self._script = ""
        if tag == "button":
            self._button = bool(a.get("aria-label")) or "data-theme-toggle" in a
            self.buttons.append(self._button)

    def handle_endtag(self, tag):
        if tag == "script" and self._script is not None:
            self.scripts.append(self._script)
            self._script = None
        if tag == "title":
            self._title = False
        if tag == "button" and self._button is not None:
            self.buttons[-1] = self._button
            self._button = None

    def handle_data(self, data):
        if self._script is not None:
            self._script += data
        if self._title and data.strip():
            self.title = True
        if self._button is not None and data.strip():
            self._button = True


def lum(hexcolour):
    rgb = [int(hexcolour[i:i + 2], 16) / 255 for i in (1, 3, 5)]
    lin = [c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4 for c in rgb]
    return 0.2126 * lin[0] + 0.7152 * lin[1] + 0.0722 * lin[2]


def contrast(a, b):
    la, lb = sorted((lum(a), lum(b)), reverse=True)
    return (la + 0.05) / (lb + 0.05)


nginx = (ROOT / "deploy/nginx.conf").read_text()
csp_hashes = set(re.findall(r"'sha256-([A-Za-z0-9+/=]+)'", nginx))
parsed = {}
for name in PAGES:
    p = Page()
    p.feed((SITE / name).read_text())
    parsed[name] = p
    for ok, what in [(p.lang, "html lang"), (p.title, "title"), (p.desc, "meta description")]:
        if not ok:
            errors.append(f"{name}: no {what}")
    if p.h1 != 1:
        errors.append(f"{name}: {p.h1} h1 elements, want 1")
    if p.img_no_alt:
        errors.append(f"{name}: {p.img_no_alt} img without alt")
    if p.inline_style:
        errors.append(f"{name}: {p.inline_style} inline style attributes; the CSP blocks them")
    if not all(p.buttons):
        errors.append(f"{name}: a button has no accessible name")
    for s in p.scripts:
        h = base64.b64encode(hashlib.sha256(s.encode()).digest()).decode()
        if h not in csp_hashes:
            errors.append(f"{name}: inline script hash {h} is not in the nginx CSP")

# Omarchy is named once, as the inspiration, on the landing page.
omarchy = {n: (SITE / n).read_text().count("Omarchy") for n in PAGES}
if sum(omarchy.values()) > 1 or omarchy.get("index.html", 0) > 1:
    errors.append(f"Omarchy is named more than once: {omarchy}")
for name in PAGES:
    for tag in re.findall(r'<a [^>]*target="_blank"[^>]*>', (SITE / name).read_text()):
        if 'rel="noopener"' not in tag:
            errors.append(f"{name}: new-tab link without rel=noopener: {tag}")
    for tag in re.findall(r'<a href="https?://(?!subarchy\.subcult\.tv)[^"]*"[^>]*>', (SITE / name).read_text()):
        if 'target="_blank"' not in tag:
            errors.append(f"{name}: outside link does not open a new tab: {tag}")

for name, p in parsed.items():
    base = (SITE / name).parent
    for href in p.links:
        if re.match(r"^[a-z]+:", href) or href.startswith("//"):
            continue
        if "/fonts/DankMono-" in href:  # licensed font, copied in at deploy time
            continue
        path, _, frag = href.partition("#")
        if not path:
            target = name
        else:
            f = (SITE / path.lstrip("/")) if path.startswith("/") else (base / path)
            if f.is_dir() or path.endswith("/"):
                f = f / "index.html"
            if not f.exists():
                errors.append(f"{name}: link {href} has no file")
                continue
            target = str(f.relative_to(SITE))
        if frag and target in parsed and frag not in parsed[target].ids:
            errors.append(f"{name}: link {href}: no id {frag!r} in {target}")

css = (SITE / "style.css").read_text()
themes = {
    "dark": dict(re.findall(r"--([a-z-]+):(#[0-9A-Fa-f]{6})", css.split("\n")[[i for i, l in enumerate(css.split("\n")) if l.startswith(":root{")][0]])),
    "light": dict(re.findall(r"--([a-z-]+):(#[0-9A-Fa-f]{6})", re.search(r':root\[data-theme="light"\]\{[^}]*\}', css).group(0))),
}
for theme, t in themes.items():
    for fg in ("text", "label", "link", "accent", "violet"):
        for bg in ("ground", "panel"):
            r = contrast(t[fg], t[bg])
            if r < 4.5:
                errors.append(f"{theme}: --{fg} on --{bg} is {r:.2f}:1, under 4.5:1")
    for fg, bg in (("action-text", "action"), ("ground", "accent")):
        r = contrast(t[fg], t[bg])
        if r < 4.5:
            errors.append(f"{theme}: --{fg} on --{bg} is {r:.2f}:1")

if errors:
    print("\n".join("site-check: " + e for e in errors))
    sys.exit(1)
print(f"site-check: ok ({len(PAGES)} pages)")
