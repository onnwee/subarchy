#!/usr/bin/env python3
"""Build site/ from the page sources in tools/site/pages/.

Each source is an HTML fragment with a header comment:

    <!--
    title: Keys
    description: One sentence for search results.
    -->

The build wraps it in the shared head, header and footer, and in the docs
layout for pages under docs/. In the body it expands:

    [[keys]]                a docs page by its slug
    [[keys#windows|label]]  a section of a page, with a label
    [[TPM]]                 a glossary term (the id of its <dt>)
    {{Super+Shift+B}}       keyboard keys
    <!-- commands -->       the command tables, from commands.json

Links to other sites open in a new tab and say so to screen readers.

    tools/site/build.py           write site/
    tools/site/build.py --check   fail if site/ differs from the sources
    tools/site/build.py --commands FILE   replace commands.json with the
        output of `subcult commands --json` (FILE, or - for stdin)
"""
import hashlib
import html
import json
import pathlib
import re
import sys

HERE = pathlib.Path(__file__).resolve().parent
ROOT = HERE.parents[1]
SITE = ROOT / "site"
PAGES = HERE / "pages"
ORIGIN = "https://subarchy.subcult.tv"
REPO = "https://github.com/subculture-collective/subarchy"

# Docs pages in reading order: slug, sidebar label.
DOCS = [
    ("", "Overview"),
    ("install", "Install"),
    ("keys", "Keys"),
    ("commands", "Commands"),
    ("shell", "Shell aliases"),
    ("look", "Theme and fonts"),
    ("updates", "Updates and recovery"),
    ("glossary", "Glossary"),
    ("developers", "Developers"),
]

# Command groups on the commands page: heading, id, groups.
COMMAND_SECTIONS = [
    ("System and updates", "system", ["update", "channel", "system", "lock", "idle", "power"]),
    ("Look", "look", ["theme", "font", "cursor", "display", "screensaver"]),
    ("Apps", "apps", ["app", "capture", "clipboard", "calendar", "agent"]),
    ("Hardware", "hardware", ["hw", "gpu", "thermal", "disk", "secureboot", "setup", "dell", "ht3"]),
    ("Services", "services", ["docker", "tailscale", "shell"]),
]
# Site wording where a command's own summary does not suit the page.
SUMMARY_OVERRIDES = {
    "subcult display scale": "Set the focused display's scale, or step up or down through the preset scales",
}

THEME_SCRIPT = ('try{var t=localStorage.getItem("subarchy-theme");'
                'if(t==="light"||t==="dark")document.documentElement.setAttribute("data-theme",t)}catch(e){}')
OG_ALT = ("SUBARCHY in dripping green block letters above the line: "
          "An Arch Linux desktop from SUBCULT. In development.")
NEW_TAB = '<span class="sr"> (opens in a new tab)</span>'


class BuildError(Exception):
    pass


def asset_url(name):
    """/name?v=<content hash>: Cloudflare keeps CSS and JS in browsers for
    hours whatever the origin says, so a changed file needs a new URL."""
    digest = hashlib.sha256((SITE / name).read_bytes()).hexdigest()[:10]
    return f"/{name}?v={digest}"


def slugify(text):
    return re.sub(r"[^a-z0-9]+", "-", text.lower()).strip("-")


def read_page(path):
    text = path.read_text()
    m = re.match(r"<!--\n(.*?)\n-->\n", text, re.S)
    if not m:
        raise BuildError(f"{path}: no header comment")
    meta = dict(line.split(": ", 1) for line in m.group(1).splitlines())
    return meta, text[m.end():]


def docs_url(slug):
    return "/docs/" + (slug + "/" if slug else "")


def keys(spec):
    out = []
    for part in spec.split("+"):
        part = part.strip()
        if part.startswith("_") and part.endswith("_"):  # a placeholder such as _number_
            out.append(f"<em>{html.escape(part[1:-1])}</em>")
        else:
            out.append(f"<kbd>{html.escape(part)}</kbd>")
    return '<span class="keys">' + " + ".join(out) + "</span>"


def page_ids(body):
    return set(re.findall(r'\bid="([^"]+)"', body))


def wikilinks(body, slugs, glossary, ids_by_slug, where):
    def link(m):
        target, _, label = m.group(1).partition("|")
        page, _, anchor = target.partition("#")
        page = page.strip()
        key = slugify(page)
        if page == "" and anchor:
            href, text = "#" + anchor, label or anchor
        elif page.lower() in slugs or (page == "overview"):
            slug = "" if page == "overview" else page.lower()
            if anchor and anchor not in ids_by_slug[slug]:
                raise BuildError(f"{where}: [[{m.group(1)}]]: no id {anchor!r} on {slug or 'overview'}")
            href = docs_url(slug) + ("#" + anchor if anchor else "")
            text = label or dict(DOCS)[slug]
        elif key in glossary:
            href, text = "/docs/glossary/#" + key, label or page
        else:
            raise BuildError(f"{where}: [[{m.group(1)}]] matches no page or glossary term")
        return f'<a class="wl" href="{href}">{text}</a>'
    return re.sub(r"\[\[([^\]]+)\]\]", link, body)


def external(page_html):
    def fix(m):
        tag, rest, inner = m.group(1), m.group(2), m.group(3)
        if "target=" in tag:
            return m.group(0)
        return f'{tag} target="_blank" rel="noopener">{inner}{NEW_TAB}</a>'
    return re.sub(r'(<a href="https?://(?!subarchy\.subcult\.tv)[^"]*"([^>]*))>(.*?)</a>', fix, page_html, flags=re.S)


def commands_html():
    data = json.loads((HERE / "commands.json").read_text())["commands"]
    by_group = {}
    for c in data:
        by_group.setdefault(c["group"], []).append(c)
    listed = {g for _, _, groups in COMMAND_SECTIONS for g in groups}
    missing = sorted(set(by_group) - listed)
    if missing:
        raise BuildError(f"commands.json has groups no section lists: {missing}")
    out = []
    for title, sid, groups in COMMAND_SECTIONS:
        out.append(f'<h2 id="{sid}">{title}</h2>')
        out.append(f'<div class="scroll"><table class="commands"><caption>{title} commands</caption>'
                   '<thead><tr><th scope="col">Command</th><th scope="col">Does</th></tr></thead><tbody>')
        for g in groups:
            for c in by_group.get(g, []):
                route = html.escape(c["route"])
                args = f' <span class="args">{html.escape(c["args"])}</span>' if c.get("args") else ""
                summary = html.escape(SUMMARY_OVERRIDES.get(c["route"], c["summary"]))
                tags = ""
                if c.get("requires_sudo"):
                    tags += ' <span class="tag">sudo</span>'
                if c.get("dangerous"):
                    tags += ' <span class="tag">asks first</span>'
                out.append(f'<tr><th scope="row"><code>{route}</code>{args}</th><td>{summary}{tags}</td></tr>')
        out.append("</tbody></table></div>")
    return "\n".join(out)


def head(meta, path, docs):
    title, desc = meta["title"], meta["description"]
    url = ORIGIN + path
    lines = [
        "<!doctype html>", '<html lang="en">', "<head>", '<meta charset="utf-8">',
        '<meta name="viewport" content="width=device-width,initial-scale=1,viewport-fit=cover">',
        f"<title>{title}</title>",
        f'<meta name="description" content="{desc}">',
    ]
    if meta.get("robots"):
        lines.append(f'<meta name="robots" content="{meta["robots"]}">')
    else:
        lines.append(f'<link rel="canonical" href="{url}">')
    lines += [
        '<meta property="og:type" content="website">',
        f'<meta property="og:title" content="{title}">',
        f'<meta property="og:description" content="{desc}">',
        f'<meta property="og:url" content="{url}">',
        f'<meta property="og:image" content="{ORIGIN}/assets/og.png">',
        '<meta property="og:image:width" content="1200">',
        '<meta property="og:image:height" content="630">',
        f'<meta property="og:image:alt" content="{OG_ALT}">',
        '<meta name="twitter:card" content="summary_large_image">',
        '<meta name="theme-color" content="#100B19" media="(prefers-color-scheme: dark)">',
        '<meta name="theme-color" content="#F0ECE4" media="(prefers-color-scheme: light)">',
        '<link rel="icon" href="/assets/favicon.svg" type="image/svg+xml">',
        '<link rel="icon" href="/assets/favicon-32.png" sizes="32x32" type="image/png">',
        '<link rel="apple-touch-icon" href="/assets/apple-touch-icon.png">',
        '<link rel="preload" href="/fonts/DepartureMono-Regular.woff2" as="font" type="font/woff2" crossorigin>',
    ]
    if docs:
        for face in ("500-normal", "500-italic", "700-normal"):
            lines.append(f'<link rel="preload" href="/fonts/victor-mono-latin-{face}.woff2" as="font" type="font/woff2" crossorigin>')
    lines += [f'<link rel="stylesheet" href="{asset_url("style.css")}">', f"<script>{THEME_SCRIPT}</script>", "</head>"]
    return "\n".join(lines)


def header(current):
    items = [("/docs/", "docs", "docs"), ("/docs/keys/", "keys", "keys"),
             ("/docs/commands/", "commands", "commands"),
             (REPO, "git", None), ("https://subcult.tv/support", "support", None)]
    cur = ' aria-current="page"'
    links = "".join(f'<a href="{href}"{cur if key and key == current else ""}>{label}</a>'
                    for href, label, key in items)
    return ('<a class="skip" href="#main">Skip to content</a>\n'
            '<header class="top"><div class="wrap nav">\n'
            '<a class="home" href="/" aria-label="Subarchy home"><img class="dark-only" src="/assets/mark-clean-dark.svg" alt="" width="200" height="140">'
            '<img class="light-only" src="/assets/mark-clean-light.svg" alt="" width="200" height="140"><span>subarchy</span></a>\n'
            f'<nav class="links" aria-label="Main">{links}</nav>\n'
            '<button type="button" data-theme-toggle hidden>paper</button>\n'
            "</div></header>")


def footer(support=True):
    row = ['<a href="/docs/">Docs</a>', '<a href="/docs/glossary/">Glossary</a>',
           f'<a href="{REPO}">Source</a>', f'<a href="{REPO}/issues">Issues</a>']
    if support:
        row.append('<a href="https://subcult.tv/support">Support SUBCULT</a>')
    row.append('<a href="https://subcult.tv">subcult.tv</a>')
    return ('<footer><div class="wrap">\n'
            f'<div class="row">{"".join(row)}</div>\n'
            "<p>Subarchy is free software under GPL-3.0-or-later. Set in Departure Mono (OFL); "
            "the docs text in Victor Mono (OFL).</p>\n"
            f'</div></footer>\n<script src="{asset_url("app.js")}" defer></script>\n</body>\n</html>\n')


def docs_layout(slug, meta, body):
    sections = re.findall(r'<h2 id="([^"]+)">(.*?)</h2>', body)
    items = []
    for s, label in DOCS:
        cur = ' aria-current="page"' if s == slug else ""
        sub = ""
        if s == slug and sections:
            sub = '<ol class="sections">' + "".join(
                f'<li><a href="#{i}">{re.sub(r"<[^>]+>", "", t)}</a></li>' for i, t in sections) + "</ol>"
        items.append(f'<li><a href="{docs_url(s)}"{cur}>{label}</a>{sub}</li>')
    i = [s for s, _ in DOCS].index(slug)
    pager = []
    if i > 0:
        s, label = DOCS[i - 1]
        pager.append(f'<a class="prev" href="{docs_url(s)}" rel="prev"><span>Previous</span>{label}</a>')
    if i < len(DOCS) - 1:
        s, label = DOCS[i + 1]
        pager.append(f'<a class="next" href="{docs_url(s)}" rel="next"><span>Next</span>{label}</a>')
    crumbs = "" if not slug else f'<p class="crumbs"><a href="/docs/">Docs</a> / {dict(DOCS)[slug]}</p>\n'
    source = f"tools/site/pages/docs/{slug or 'index'}.html"
    return (
        '<div class="wrap docs">\n'
        '<nav class="side" aria-label="Docs"><details class="toc"><summary>Docs pages</summary>'
        f'<ol>{"".join(items)}</ol></details></nav>\n'
        f'<main id="main">\n{crumbs}<h1>{meta["h1"]}</h1>\n{body.strip()}\n'
        f'<nav class="pager" aria-label="Previous and next page">{"".join(pager)}</nav>\n'
        f'<p class="edit"><a href="{REPO}/blob/main/{source}">Edit this page</a></p>\n'
        "</main>\n</div>\n")


def build():
    sources = {}
    for s, _ in DOCS:
        sources[("docs", s)] = read_page(PAGES / "docs" / f"{s or 'index'}.html")
    sources[("home", "")] = read_page(PAGES / "home.html")
    sources[("404", "")] = read_page(PAGES / "404.html")

    for (kind, s), (meta, body) in list(sources.items()):
        if "<!-- commands -->" in body:
            sources[(kind, s)] = (meta, body.replace("<!-- commands -->", commands_html()))
    meta, body = sources[("docs", "glossary")]
    first = {}
    for gid, term in re.findall(r'<dt id="([^"]+)">(.*?)</dt>', body):
        first.setdefault(term[0].upper(), gid)
    letters = "".join(f'<a href="#{gid}">{ch}</a>' for ch, gid in sorted(first.items()))
    sources[("docs", "glossary")] = (meta, body.replace("<!-- letters -->", letters))
    glossary = page_ids(body)
    ids_by_slug = {s: page_ids(sources[("docs", s)][1]) for s, _ in DOCS}
    slugs = {s for s, _ in DOCS if s}

    out = {}
    for (kind, s), (meta, body) in sources.items():
        where = f"{kind}/{s or 'index'}"
        body = re.sub(r"\{\{([^}]+)\}\}", lambda m: keys(m.group(1)), body)
        body = wikilinks(body, slugs, glossary, ids_by_slug, where)
        if kind == "docs":
            path = docs_url(s)
            page = (head(meta, path, True) + "\n<body>\n" + header(meta.get("nav", "docs")) + "\n"
                    + docs_layout(s, meta, body) + footer())
            target = SITE / ("docs/" + (s + "/" if s else "")) / "index.html"
        elif kind == "home":
            page = head(meta, "/", False) + "\n<body>\n" + header("") + "\n" + body.strip() + "\n" + footer()
            target = SITE / "index.html"
        else:
            page = (head(meta, "/404.html", False) + "\n<body>\n" + header("") + "\n" + body.strip() + "\n"
                    + footer(support=False))
            target = SITE / "404.html"
        out[target] = external(page)
    urls = ["/"] + [docs_url(s) for s, _ in DOCS]
    out[SITE / "sitemap.xml"] = ('<?xml version="1.0" encoding="UTF-8"?>\n'
                                 '<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">\n'
                                 + "".join(f"  <url><loc>{ORIGIN}{u}</loc></url>\n" for u in urls)
                                 + "</urlset>\n")
    return out


def main(argv):
    if argv[:1] == ["--commands"]:
        src = sys.stdin if argv[1] == "-" else open(argv[1])
        data = json.load(src)["commands"]
        keep = ["route", "group", "args", "summary", "examples", "requires_sudo", "dangerous"]
        out = [{k: c.get(k) for k in keep} for c in data if not c.get("hidden")]
        (HERE / "commands.json").write_text(json.dumps(
            {"_source": "subcult commands --json; refresh with make site-commands", "commands": out}, indent=1) + "\n")
        print(f"commands.json: {len(out)} commands")
        return 0
    try:
        pages = build()
    except BuildError as e:
        print(f"site build: {e}", file=sys.stderr)
        return 1
    if argv[:1] == ["--check"]:
        stale = [str(p.relative_to(ROOT)) for p, text in pages.items()
                 if not p.exists() or p.read_text() != text]
        if stale:
            print("site build: out of date, run tools/site/build.py: " + ", ".join(stale), file=sys.stderr)
            return 1
        print(f"site build: ok ({len(pages)} files)")
        return 0
    for p, text in pages.items():
        p.parent.mkdir(parents=True, exist_ok=True)
        p.write_text(text)
    print(f"site build: wrote {len(pages)} files")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
