#!/usr/bin/env python3
"""Report pins that have fallen behind upstream, in one issue (issue #290).

Pins checked: the vendored AUR packages under packaging/aur, Pult and linecast
(packaging/pult, packaging/linecast), and the Neovim starter commit and plugin
lock (packaging/subarchy-nvim). The script changes no pin. It writes one
issue, found by its fixed title:

  - something is behind and no open issue exists: open one;
  - something is behind and the open issue's text differs: update it;
  - nothing is behind and every check ran: close the open issue.

If a check could not run, the issue is left as it is, so an upstream outage
never closes a real report.

Usage: report-outdated-pins.py [--dry-run] [--root DIR]
  --dry-run  print the report and write no issue (upstream reads still run)
Environment: GH_TOKEN (the workflow's GITHUB_TOKEN) and GH_REPO (owner/name)
are needed to write the issue; GH_TOKEN also raises the API rate limit.
"""

import argparse
from datetime import datetime, timezone
import json
import os
from pathlib import Path
import re
import sys
import urllib.error
import urllib.parse
import urllib.request

TITLE = "Outdated pins"
MARKER = "<!-- report-outdated-pins -->"
AUR_RPC = "https://aur.archlinux.org/rpc/v5/info"
GITHUB = "https://api.github.com"

# lazy-lock.json names plugins, not repositories. A name missing here is
# reported as not checked instead of being skipped quietly.
NVIM_REPOS = {
    "LazyVim": "LazyVim/LazyVim",
    "blink.cmp": "Saghen/blink.cmp",
    "bufferline.nvim": "akinsho/bufferline.nvim",
    "catppuccin": "catppuccin/nvim",
    "conform.nvim": "stevearc/conform.nvim",
    "flash.nvim": "folke/flash.nvim",
    "friendly-snippets": "rafamadriz/friendly-snippets",
    "gitsigns.nvim": "lewis6991/gitsigns.nvim",
    "grug-far.nvim": "MagicDuck/grug-far.nvim",
    "lazy.nvim": "folke/lazy.nvim",
    "lazydev.nvim": "folke/lazydev.nvim",
    "lualine.nvim": "nvim-lualine/lualine.nvim",
    "mason-lspconfig.nvim": "mason-org/mason-lspconfig.nvim",
    "mason.nvim": "mason-org/mason.nvim",
    "mini.ai": "nvim-mini/mini.ai",
    "mini.icons": "nvim-mini/mini.icons",
    "mini.pairs": "nvim-mini/mini.pairs",
    "noice.nvim": "folke/noice.nvim",
    "nui.nvim": "MunifTanjim/nui.nvim",
    "nvim-lint": "mfussenegger/nvim-lint",
    "nvim-lspconfig": "neovim/nvim-lspconfig",
    "nvim-treesitter": "nvim-treesitter/nvim-treesitter",
    "nvim-treesitter-textobjects": "nvim-treesitter/nvim-treesitter-textobjects",
    "nvim-ts-autotag": "windwp/nvim-ts-autotag",
    "persistence.nvim": "folke/persistence.nvim",
    "plenary.nvim": "nvim-lua/plenary.nvim",
    "snacks.nvim": "folke/snacks.nvim",
    "todo-comments.nvim": "folke/todo-comments.nvim",
    "tokyonight.nvim": "folke/tokyonight.nvim",
    "trouble.nvim": "folke/trouble.nvim",
    "ts-comments.nvim": "folke/ts-comments.nvim",
    "which-key.nvim": "folke/which-key.nvim",
}
STARTER_REPO = "LazyVim/starter"
PULT_REPO = "subculture-collective/pult"
LINECAST_REPO = "ashuttl/linecast"
CHECK_ERRORS = (urllib.error.URLError, KeyError, ValueError, TimeoutError)


# ---- versions --------------------------------------------------------------

def vercmp(a, b):
    """Compare version strings like pacman's vercmp, simplified: runs of
    digits compare as numbers, a number is newer than letters, and a longer
    version with an equal prefix is newer unless its next part is letters
    (1.0rc1 is older than 1.0). Returns -1, 0 or 1."""
    sa = re.findall(r"[0-9]+|[A-Za-z]+", a)
    sb = re.findall(r"[0-9]+|[A-Za-z]+", b)
    for x, y in zip(sa, sb):
        if x == y:
            continue
        if x.isdigit() and y.isdigit():
            return 1 if int(x) > int(y) else -1
        if x.isdigit() != y.isdigit():
            return 1 if x.isdigit() else -1
        return 1 if x > y else -1
    if len(sa) == len(sb):
        return 0
    longer_is_a = len(sa) > len(sb)
    extra = (sa if longer_is_a else sb)[min(len(sa), len(sb))]
    longer_is_newer = extra.isdigit()
    if longer_is_a:
        return 1 if longer_is_newer else -1
    return -1 if longer_is_newer else 1


def split_aur_version(version):
    """'[epoch:]pkgver-pkgrel' -> (epoch, pkgver)."""
    epoch, _, rest = version.rsplit("-", 1)[0].rpartition(":")
    return int(epoch or 0), rest


def aur_newer(local_epoch, local_ver, upstream):
    epoch, ver = split_aur_version(upstream)
    if epoch != local_epoch:
        return epoch > local_epoch
    return vercmp(ver, local_ver) > 0


# ---- local pins ------------------------------------------------------------

def read_assignments(path):
    """Top-level NAME=value lines of a PKGBUILD, with ${x} and $x expanded
    from earlier lines. Enough for pkgver, epoch, _starter and _commit."""
    values = {}
    for line in Path(path).read_text().splitlines():
        m = re.match(r"^([A-Za-z_][A-Za-z0-9_]*)=(.*?)\s*(?:#.*)?$", line)
        if not m:
            continue
        name, raw = m.groups()
        raw = raw.strip().strip("\"'")
        if raw.startswith("("):
            continue
        raw = re.sub(r"\$\{(\w+)\}|\$(\w+)",
                     lambda k: values.get(k.group(1) or k.group(2), ""), raw)
        values.setdefault(name, raw)
    return values


def aur_pins(root):
    pins = {}
    for pkgbuild in sorted(Path(root, "packaging/aur").glob("*/PKGBUILD")):
        v = read_assignments(pkgbuild)
        pins[pkgbuild.parent.name] = (int(v.get("epoch") or 0), v.get("pkgver", ""))
    return pins


# ---- upstream reads --------------------------------------------------------

def http_get(url, token=None):
    """GET url and return parsed JSON. Replaced in tests."""
    headers = {"Accept": "application/vnd.github+json", "User-Agent": "subarchy-pin-report"}
    if token and url.startswith(GITHUB):
        headers["Authorization"] = f"Bearer {token}"
    with urllib.request.urlopen(urllib.request.Request(url, headers=headers), timeout=30) as r:
        return json.load(r)


def check_aur(pins, get):
    """-> (behind rows, problems). A row is (name, pinned, upstream)."""
    query = "&".join("arg[]=" + urllib.parse.quote(n) for n in pins)
    found = {r["Name"]: r["Version"] for r in get(f"{AUR_RPC}?{query}").get("results", [])}
    behind, problems = [], []
    for name, (epoch, ver) in pins.items():
        if name not in found:
            problems.append(f"`{name}`: not found in the AUR")
        elif not ver:
            problems.append(f"`{name}`: no pkgver in its PKGBUILD")
        elif aur_newer(epoch, ver, found[name]):
            behind.append((name, ver, split_aur_version(found[name])[1]))
    return behind, problems


def latest_release(repo, get):
    """Newest release tag without a leading v; falls back to tags."""
    try:
        return get(f"{GITHUB}/repos/{repo}/releases/latest")["tag_name"].lstrip("v")
    except urllib.error.HTTPError as error:
        if error.code != 404:
            raise
    best = None
    for tag in get(f"{GITHUB}/repos/{repo}/tags?per_page=30"):
        v = tag["name"].lstrip("v")
        if re.match(r"^\d", v) and (best is None or vercmp(v, best) > 0):
            best = v
    return best


def commits_behind(repo, commit, branch, get):
    """How many commits `branch` has beyond `commit`."""
    return int(get(f"{GITHUB}/repos/{repo}/compare/{commit}...{branch}")["ahead_by"])


# ---- report ----------------------------------------------------------------

def collect(root, get):
    """-> (sections, problems). sections maps a heading to (pin, pinned, upstream) rows."""
    root = Path(root)
    sections, problems = {}, []

    def guarded(label, fn):
        try:
            return fn()
        except CHECK_ERRORS as error:
            problems.append(f"{label}: could not check ({type(error).__name__}: {error})")
            return None

    result = guarded("AUR packages", lambda: check_aur(aur_pins(root), get))
    if result:
        sections["Vendored AUR packages (packaging/aur)"] = [
            (f"`{n}`", pinned, up) for n, pinned, up in result[0]]
        problems += result[1]

    pult = read_assignments(root / "packaging/pult/PKGBUILD")
    pult_base = pult.get("pkgver", "").split(".r")[0]
    release = guarded("Pult", lambda: latest_release(PULT_REPO, get))
    if release and vercmp(release, pult_base) > 0:
        sections["Pult (packaging/pult)"] = [
            ("`pult`", f"{pult_base} + commit {pult.get('_commit', '?')[:7]}", release)]

    linecast = read_assignments(root / "packaging/linecast/PKGBUILD")
    release = guarded("linecast", lambda: latest_release(LINECAST_REPO, get))
    if release and vercmp(release, linecast.get("pkgver", "0")) > 0:
        sections["linecast (packaging/linecast)"] = [
            ("`linecast`", linecast.get("pkgver", "?"), release)]

    nvim = root / "packaging/subarchy-nvim"
    rows = []
    starter = read_assignments(nvim / "PKGBUILD").get("_starter")
    if starter:
        n = guarded("LazyVim starter", lambda: commits_behind(STARTER_REPO, starter, "main", get))
        if n:
            rows.append(("`LazyVim/starter`", starter[:7], f"{n} commit(s) ahead on main"))
    for name, entry in json.loads((nvim / "lazy-lock.json").read_text()).items():
        repo = NVIM_REPOS.get(name)
        if repo is None:
            problems.append(f"`{name}`: no repository known; add it to NVIM_REPOS in this script")
            continue
        n = guarded(name, lambda: commits_behind(repo, entry["commit"], entry["branch"], get))
        if n:
            rows.append((f"`{name}`", entry["commit"][:7], f"{n} commit(s) ahead on {entry['branch']}"))
    if rows:
        sections["Neovim starter and plugin lock (packaging/subarchy-nvim)"] = rows
    return sections, problems


def render(sections, problems, today):
    total = sum(len(rows) for rows in sections.values())
    lines = [MARKER, "",
             f"{total} pinned item(s) are behind upstream as of {today}. "
             "This issue is rewritten each week; no pin was changed.", ""]
    for heading, rows in sections.items():
        if rows:
            lines += [f"### {heading}", "", "| Pin | Pinned | Upstream |", "|---|---|---|"]
            lines += [f"| {a} | {b} | {c} |" for a, b, c in rows] + [""]
    if problems:
        lines += ["### Not checked", ""] + [f"- {p}" for p in problems] + [""]
    lines += ["To update a pin, review the upstream change and follow the steps in "
              "`packaging/README.md` and `packaging/aur/README.md`.", "",
              "Written by `.github/workflows/outdated-pins.yml`; it closes this issue "
              "when nothing is behind."]
    return "\n".join(lines)


# ---- issue -----------------------------------------------------------------

def api(method, path, token, body=None):
    request = urllib.request.Request(
        f"{GITHUB}{path}", method=method,
        data=None if body is None else json.dumps(body).encode(),
        headers={"Accept": "application/vnd.github+json", "Authorization": f"Bearer {token}",
                 "User-Agent": "subarchy-pin-report", "Content-Type": "application/json"})
    with urllib.request.urlopen(request, timeout=30) as response:
        return json.load(response)


def sync_issue(repo, token, body, behind, complete, call=api):
    """Create, update or close the one report issue. Returns a summary line."""
    issues = call("GET", f"/repos/{repo}/issues?state=open&per_page=100", token)
    existing = next((i for i in issues if "pull_request" not in i and i["title"] == TITLE), None)
    if behind:
        if existing is None:
            made = call("POST", f"/repos/{repo}/issues", token, {"title": TITLE, "body": body})
            return f"opened #{made['number']}"
        if existing["body"] != body:
            call("PATCH", f"/repos/{repo}/issues/{existing['number']}", token, {"body": body})
            return f"updated #{existing['number']}"
        return f"#{existing['number']} already current"
    if existing is None:
        return "nothing behind and no open issue"
    if not complete:
        return f"#{existing['number']} left open: some checks did not run"
    number = existing["number"]
    call("POST", f"/repos/{repo}/issues/{number}/comments", token,
         {"body": "Nothing is behind upstream now; closing."})
    call("PATCH", f"/repos/{repo}/issues/{number}", token, {"state": "closed"})
    return f"closed #{number}"


def main(argv=None, get=None, call=api, now=None):
    parser = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    parser.add_argument("--dry-run", action="store_true")
    parser.add_argument("--root", default=str(Path(__file__).parents[2]))
    args = parser.parse_args(argv)
    token, repo = os.environ.get("GH_TOKEN"), os.environ.get("GH_REPO")
    sections, problems = collect(args.root, get or (lambda url: http_get(url, token)))
    behind = sum(len(rows) for rows in sections.values())
    today = (now or datetime.now(timezone.utc)).strftime("%Y-%m-%d")
    body = render(sections, problems, today)
    print(body if behind or problems else "Nothing is behind upstream.")
    if args.dry_run:
        print("\n(dry run: no issue written)")
        return 0
    if not token or not repo:
        print("GH_TOKEN and GH_REPO are required to write the issue", file=sys.stderr)
        return 2
    print(sync_issue(repo, token, body, behind, not problems, call))
    return 0


if __name__ == "__main__":
    sys.exit(main())
