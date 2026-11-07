#!/usr/bin/env python3
"""Check the Obsidian notes in docs/ against docs/vault-conventions.md.

- note names are unique across the vault
- every wikilink and embed resolves to exactly one file, and heading or view
  targets exist
- every note has frontmatter with title, type, status and tags, using the
  allowed values
- relative Markdown links in README files resolve

Exits 1 when any check fails. Standard library only.
"""

from __future__ import annotations

import re
import sys
from collections import defaultdict
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
DOCS = ROOT / "docs"
TYPES = {"index", "inventory", "decision", "brand", "review", "plan", "guide"}
STATUSES = {"active", "draft", "proposed", "accepted", "rejected", "superseded", "generated"}
REQUIRED = ("title", "type", "status", "tags")
WIKILINK = re.compile(r"(!?)\[\[([^\]|]+?)(?:\\?\|[^\]]*)?\]\]")
MDLINK = re.compile(r"\[[^\]]*\]\(([^)\s#]+)(#[^)]*)?\)")
FENCE = re.compile(r"^```.*?^```", re.S | re.M)


def frontmatter(text: str) -> dict[str, str] | None:
    if not text.startswith("---\n"):
        return None
    end = text.find("\n---\n", 4)
    if end < 0:
        return None
    props = {}
    for line in text[4:end].splitlines():
        if ":" in line and not line.startswith((" ", "-")):
            key, _, value = line.partition(":")
            props[key.strip()] = value.strip()
    return props


def headings(text: str) -> set[str]:
    return {m.group(1).strip() for m in re.finditer(r"^#{1,6} (.+)$", FENCE.sub("", text), re.M)}


def base_views(text: str) -> set[str]:
    return {m.group(1).strip().strip('"') for m in re.finditer(r"^\s+name: (.+)$", text, re.M)}


def main() -> int:
    errors: list[str] = []
    files = [p for p in DOCS.rglob("*") if p.suffix in (".md", ".base")]
    by_name: dict[str, list[Path]] = defaultdict(list)
    for p in files:
        by_name[p.stem if p.suffix == ".md" else p.name].append(p)
    for name, paths in by_name.items():
        if len(paths) > 1:
            errors.append(f"duplicate note name {name}: {', '.join(str(p.relative_to(ROOT)) for p in paths)}")

    templates = DOCS / "templates"
    for note in (p for p in files if p.suffix == ".md"):
        rel = note.relative_to(ROOT)
        text = note.read_text()
        props = frontmatter(text)
        if props is None:
            errors.append(f"{rel}: missing or unterminated frontmatter")
        elif not note.is_relative_to(templates):
            for key in REQUIRED:
                if not props.get(key):
                    errors.append(f"{rel}: property '{key}' missing or empty")
            if props.get("type") and props["type"] not in TYPES:
                errors.append(f"{rel}: type '{props['type']}' not in {sorted(TYPES)}")
            if props.get("status") and props["status"] not in STATUSES:
                errors.append(f"{rel}: status '{props['status']}' not in {sorted(STATUSES)}")
        for m in WIKILINK.finditer(FENCE.sub("", text)):
            target = m.group(2)
            name, _, sub = target.partition("#")
            if not name:  # same-note heading link
                if sub not in headings(text):
                    errors.append(f"{rel}: heading '#{sub}' not found in this note")
                continue
            hits = by_name.get(name) or by_name.get(Path(name).name)
            if not hits:
                errors.append(f"{rel}: [[{target}]] does not resolve")
            elif len(hits) > 1:
                errors.append(f"{rel}: [[{target}]] is ambiguous")
            elif sub:
                dest = hits[0].read_text()
                found = base_views(dest) if hits[0].suffix == ".base" else headings(dest)
                if sub not in found:
                    errors.append(f"{rel}: [[{target}]] names a heading or view that does not exist")

    for readme in ROOT.glob("**/README.md"):
        if ".git" in readme.parts or readme.is_relative_to(DOCS):
            continue
        for m in MDLINK.finditer(readme.read_text()):
            target = m.group(1)
            if target.startswith(("http:", "https:", "mailto:")):
                continue
            if not (readme.parent / target).exists():
                errors.append(f"{readme.relative_to(ROOT)}: link to {target} does not resolve")
    for readme in DOCS.rglob("README.md"):
        errors.append(f"{readme.relative_to(ROOT)}: name index notes after their folder, not README")

    notes = sum(1 for p in files if p.suffix == ".md")
    for e in errors:
        print(e)
    print(f"{notes} notes, {len(files) - notes} views, {len(errors)} problems")
    return 1 if errors else 0


if __name__ == "__main__":
    sys.exit(main())
