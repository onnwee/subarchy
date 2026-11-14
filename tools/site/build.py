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

It also writes the plugins catalogue, /plugins/ and one page per shell
widget, from shell/widgets/index.json, default/shell/bar.json and the
wording in plugins.json.

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
WIDGET_INDEX = ROOT / "shell" / "widgets" / "index.json"
BAR_DEFAULTS = ROOT / "default" / "shell" / "bar.json"
SECTIONS = [("left", "left"), ("center", "centre"), ("right", "right")]
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

# Runs before the first paint, so a saved theme or a hidden docs sidebar does not flash.
THEME_SCRIPT = ('try{var r=document.documentElement,t=localStorage.getItem("subarchy-theme");'
                'if(t==="light"||t==="dark")r.setAttribute("data-theme",t);'
                'if(localStorage.getItem("subarchy-side")==="hidden")r.setAttribute("data-side","hidden")}catch(e){}')
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
             ("/docs/commands/", "commands", "commands"), ("/plugins/", "plugins", "plugins"),
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
    row = ['<a href="/docs/">Docs</a>', '<a href="/plugins/">Plugins</a>', '<a href="/docs/glossary/">Glossary</a>',
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
        '<div class="rail"><button type="button" class="side-toggle" data-side-toggle aria-controls="docs-side" hidden>hide</button>\n'
        '<nav class="side" id="docs-side" aria-label="Docs"><details class="toc"><summary>Docs pages</summary>'
        f'<ol>{"".join(items)}</ol></details></nav></div>\n'
        f'<main id="main">\n{crumbs}<h1>{meta["h1"]}</h1>\n{body.strip()}\n'
        f'<nav class="pager" aria-label="Previous and next page">{"".join(pager)}</nav>\n'
        f'<p class="edit"><a href="{REPO}/blob/main/{source}">Edit this page</a></p>\n'
        "</main>\n</div>\n")


def plugins_data():
    """The catalogue: each shell widget's manifest, where the default bar puts
    it, and the site's wording. Fails when the two sources disagree."""
    index = json.loads(WIDGET_INDEX.read_text())["widgets"]
    layout = json.loads(BAR_DEFAULTS.read_text())["layout"]
    site = json.loads((HERE / "plugins.json").read_text())
    cats = dict(site["categories"])
    words = site["plugins"]
    manifests = {w["dir"]: w["manifest"] for w in index.values()}
    unmatched = sorted(set(manifests) ^ set(words))
    if unmatched:
        raise BuildError(f"plugins.json and shell/widgets/index.json disagree about {unmatched}")
    order = [i for s, _ in SECTIONS for i in layout.get(s, [])]
    out = []
    for d, m in manifests.items():
        w = words[d]
        if w.get("hidden"):
            continue
        if w["category"] not in cats:
            raise BuildError(f"plugins.json: {d}: no category {w['category']!r}")
        if set(m.get("settings") or {}) != set(w["settings"]):
            raise BuildError(f"plugins.json: {d}: settings must describe {sorted(m.get('settings') or {})}")
        if not set(w.get("example") or {}) <= set(w["settings"]):
            raise BuildError(f"plugins.json: {d}: the example names a setting the manifest does not have")
        section = next((label for s, label in SECTIONS if m["id"] in layout.get(s, [])), None)
        out.append({"dir": d, "m": m, "w": w, "cat": cats[w["category"]], "section": section,
                    "minimal": m["id"] in layout.get("minimal", []),
                    "order": order.index(m["id"]) if section else len(order)})
    out.sort(key=lambda p: p["m"]["name"].lower())
    return out, site["categories"], layout


def duration(seconds):
    if seconds % 3600 == 0:
        return f"{seconds // 3600} h"
    if seconds % 60 == 0:
        return f"{seconds // 60} min"
    return f"{seconds} s"


def plugin_mark(name):
    return html.escape(name[:2].capitalize())


def plugin_card(p):
    m, cost = p["m"], p["m"].get("cost") or {}
    timers, hosts = cost.get("timers") or [], cost.get("network") or []
    name = html.escape(m["name"])
    tags = [p["cat"]] + (["panel"] if m.get("panel") else []) \
        + ([f"{len(hosts)} {'host' if len(hosts) == 1 else 'hosts'}"] if hosts else ["offline"]) \
        + (["timer" if len(timers) == 1 else "timers"] if timers else ["events only"])
    state = (f'<span class="tag on">in the bar</span>' if p["section"] else '<span class="tag">off by default</span>')
    text = " ".join([m["name"], m["id"], p["cat"], re.sub(r"<[^>]+>", "", p["w"]["summary"])]).lower()
    attrs = (f'data-cat="{p["w"]["category"]}" data-on="{1 if p["section"] else 0}" data-net="{1 if hosts else 0}" '
             f'data-timers="{1 if timers else 0}" data-order="{p["order"]}" data-text="{html.escape(text)}"')
    return (f'<li class="pcard" {attrs}><a href="/plugins/{p["dir"]}/">'
            f'<span class="pmark" aria-hidden="true">{plugin_mark(m["name"])}</span>'
            f'<span class="pbody"><span class="ptitle"><strong>{name}</strong>{state}</span>'
            f'<span class="pid">{html.escape(m["id"])} &middot; v{html.escape(m["version"])}</span>'
            f'<span class="psum">{p["w"]["summary"]}</span>'
            f'<span class="ptags">{"".join(f"<span>{html.escape(x)}</span>" for x in tags)}</span></span></a></li>')


def plugins_index(plugins, categories):
    on = sum(1 for p in plugins if p["section"])
    cat_buttons = "".join(f'<button type="button" data-cat="{c}" aria-pressed="false">{html.escape(label)}</button>'
                          for c, label in categories)
    return f"""<main id="main" class="wrap plugins">
<p class="crumbs"><a href="/">Subarchy</a> / Plugins</p>
<h1>Plugins</h1>
<p class="lede">Every part of Subarchy's bar is a plugin: a small program with its own manifest, which states every timer it runs and every server it contacts. <strong>{len(plugins)} plugins</strong> ship with the shell; {on} are in the bar from the start and the other {len(plugins) - on} wait until you add them.</p>
<div class="ptools" hidden>
<div class="psearch"><label for="psearch">Search plugins</label><input id="psearch" type="search" autocomplete="off" spellcheck="false" placeholder="name, id or what it does"><kbd aria-hidden="true">/</kbd></div>
<div class="pchips" role="group" aria-label="Category"><button type="button" data-cat="" aria-pressed="true">All</button>{cat_buttons}</div>
<div class="prow">
<label>Show <select id="pstate"><option value="">all plugins</option><option value="1">in the bar by default</option><option value="0">off by default</option></select></label>
<label><input type="checkbox" id="poffline"> offline only</label>
<label><input type="checkbox" id="pevents"> no timers</label>
<label class="psort">Sort <select id="psort"><option value="name">A&ndash;Z</option><option value="bar">bar order</option><option value="cat">category</option></select></label>
</div>
<p class="pcount" id="pcount" aria-live="polite"></p>
</div>
<ul class="pgrid">
{chr(10).join(plugin_card(p) for p in plugins)}
</ul>
<div class="pnone" hidden><p>No plugin matches.</p><button type="button" data-pclear>Clear the search and filters</button></div>
<section class="pmore" aria-labelledby="more"><h2 id="more">Make your own</h2>
<p>A plugin is a folder in the shell's source with a <code>manifest.json</code> and a <code>Widget.qml</code>. [[developers#plugins|Writing a plugin]] covers the contract; new plugins arrive as pull requests.</p></section>
</main>
"""


def plugin_page(p, prev, nxt, layout):
    m, w = p["m"], p["w"]
    cost = m.get("cost") or {}
    timers, hosts, settings = cost.get("timers") or [], cost.get("network") or [], m.get("settings") or {}
    name, pid = html.escape(m["name"]), html.escape(m["id"])
    about = "\n".join(f"<p>{x}</p>" for x in w["about"])
    if p["section"]:
        where = f'in the <strong>{p["section"]}</strong> section' + (", and on minimal bars" if p["minimal"] else "")
        turn = (f"<p>It is in the bar from the start, {where}. To move or remove it, click the SUBCULT mark at the left "
                "of the bar, open <strong>Bar layout</strong> in Settings, edit the list and apply.</p>")
    else:
        right = layout.get("right", []) + [m["id"]]
        example = json.dumps({"layout": {"right": right}}, indent=1)
        turn = (f"<p>It is off by default. Click the SUBCULT mark at the left of the bar, open <strong>Bar layout</strong> "
                f"in Settings, add <code>{pid}</code> to a section and apply.</p>\n"
                "<p>Or list it in <code>~/.config/subcult/shell/bar.json</code>. A section you set there replaces the "
                "default list for that section, so give the whole list:</p>\n"
                f"<pre>{html.escape(example)}</pre>")
    if settings:
        rows = "".join(f'<tr><th scope="row"><code>{html.escape(k)}</code></th><td><code>{html.escape(json.dumps(v))}</code></td>'
                       f"<td>{w['settings'][k]}</td></tr>" for k, v in settings.items())
        k0, v0 = next(((k, v) for k, v in settings.items() if v not in ("", [], {})), next(iter(settings.items())))
        sample = json.dumps({"widgets": {m["id"]: w.get("example") or {k0: v0}}}, indent=1)
        sets = (f'<div class="scroll"><table><caption class="sr">{name} settings</caption><thead><tr><th scope="col">Setting</th>'
                f'<th scope="col">Default</th><th scope="col">Means</th></tr></thead><tbody>{rows}</tbody></table></div>\n'
                f"<p>Set them under the plugin's id in <code>~/.config/subcult/shell/bar.json</code>:</p>\n<pre>{html.escape(sample)}</pre>")
    else:
        sets = "<p>None. It works as it is.</p>"
    if timers:
        rows = "".join(f'<tr><th scope="row">{html.escape(t["name"])}</th><td>every {duration(t["ac"])}</td>'
                       f'<td>every {duration(t["battery"])}</td></tr>' for t in timers)
        tcost = (f'<div class="scroll"><table><caption class="sr">{name} timers</caption><thead><tr><th scope="col">Timer</th>'
                 f'<th scope="col">On mains</th><th scope="col">On battery</th></tr></thead><tbody>{rows}</tbody></table></div>')
    else:
        tcost = "<p><strong>No timers.</strong> It wakes only when something it follows changes.</p>"
    if hosts:
        ncost = (f"<p>It contacts {len(hosts)} {'server' if len(hosts) == 1 else 'servers'}:</p>\n"
                 '<ul class="plain hosts">' + "".join(f"<li><code>{html.escape(h)}</code></li>" for h in hosts) + "</ul>")
    else:
        ncost = "<p><strong>No network.</strong> It contacts no servers.</p>"
    facts = [("Id", f"<code>{pid}</code>"), ("Version", html.escape(m["version"])), ("Plugin API", str(m["api"])),
             ("Kind", html.escape(m["kind"])), ("Category", html.escape(p["cat"])),
             ("Default", f'in the bar, {p["section"]}' if p["section"] else "off"),
             ("Panel", "yes" if m.get("panel") else "no"), ("Timers", str(len(timers)) if timers else "none"),
             ("Network", f"{len(hosts)} {'host' if len(hosts) == 1 else 'hosts'}" if hosts else "none"),
             ("Source", f'<a href="{REPO}/tree/main/shell/widgets/{p["dir"]}">shell/widgets/{p["dir"]}</a>')]
    dl = "".join(f"<dt>{k}</dt><dd>{v}</dd>" for k, v in facts)
    pager = ""
    if prev:
        pager += f'<a class="prev" href="/plugins/{prev["dir"]}/" rel="prev"><span>Previous</span>{html.escape(prev["m"]["name"])}</a>'
    if nxt:
        pager += f'<a class="next" href="/plugins/{nxt["dir"]}/" rel="next"><span>Next</span>{html.escape(nxt["m"]["name"])}</a>'
    manifest = html.escape((WIDGET_INDEX.parent / p["dir"] / "manifest.json").read_text().rstrip())
    return f"""<main id="main" class="wrap plugin">
<p class="crumbs"><a href="/plugins/">Plugins</a> / {name}</p>
<div class="phero"><span class="pmark" aria-hidden="true">{plugin_mark(m["name"])}</span><div><h1>{name}</h1><p class="lede">{w["summary"]}</p></div></div>
<div class="pcols">
<div class="pmain">
{about}
<h2 id="turn-on">{"In the bar" if p["section"] else "Turn it on"}</h2>
{turn}
<h2 id="settings">Settings</h2>
{sets}
<h2 id="cost">Cost</h2>
{tcost}
{ncost}
<h2 id="manifest">Manifest</h2>
<pre>{manifest}</pre>
</div>
<aside class="pfacts" aria-label="About this plugin"><dl>{dl}</dl></aside>
</div>
<nav class="pager" aria-label="Previous and next plugin">{pager}</nav>
</main>
"""


def build():
    sources = {}
    for s, _ in DOCS:
        sources[("docs", s)] = read_page(PAGES / "docs" / f"{s or 'index'}.html")
    sources[("home", "")] = read_page(PAGES / "home.html")
    sources[("404", "")] = read_page(PAGES / "404.html")
    plugins, categories, layout = plugins_data()
    sources[("plugins", "")] = ({
        "title": "Plugins · Subarchy",
        "description": f"Browse the {len(plugins)} plugins of Subarchy's bar: what each does, its battery and network cost, its settings and how to turn it on.",
    }, plugins_index(plugins, categories))
    for i, p in enumerate(plugins):
        sources[("plugins", p["dir"])] = ({
            "title": f'{p["m"]["name"]} · Subarchy plugins',
            "description": re.sub(r"<[^>]+>", "", f'{p["m"]["name"]}, a Subarchy bar plugin: {p["w"]["summary"]}'),
        }, plugin_page(p, plugins[i - 1] if i else None, plugins[i + 1] if i + 1 < len(plugins) else None, layout))

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
        elif kind == "plugins":
            path = "/plugins/" + (s + "/" if s else "")
            page = head(meta, path, True) + "\n<body>\n" + header("plugins") + "\n" + body.strip() + "\n" + footer()
            target = SITE / path.lstrip("/") / "index.html"
        elif kind == "home":
            page = head(meta, "/", False) + "\n<body>\n" + header("") + "\n" + body.strip() + "\n" + footer()
            target = SITE / "index.html"
        else:
            page = (head(meta, "/404.html", False) + "\n<body>\n" + header("") + "\n" + body.strip() + "\n"
                    + footer(support=False))
            target = SITE / "404.html"
        out[target] = external(page)
    urls = ["/"] + [docs_url(s) for s, _ in DOCS] + ["/plugins/"] + [f'/plugins/{p["dir"]}/' for p in plugins]
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
