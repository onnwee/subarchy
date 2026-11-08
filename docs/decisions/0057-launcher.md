---
title: "ADR 0057: Launcher"
type: decision
status: accepted
adr: 57
created: 2026-11-07
updated: 2026-11-07
tags: [decision, adr, shell]
aliases: [ADR 0057, Launcher, Raycast]
---

# ADR 0057: Launcher

Accepted 2026-11-07. Refines the launcher in
[[0036-shell-components|ADR 0036]].

## Decision

A **Raycast-style launcher built into the Quickshell shell**
([[0034-shell-toolkit|ADR 0034]]), opened with Super+Space. No separate
launcher process or backend daemon.

### Search

- **Root search**: typing searches everything at once (apps, favorites,
  commands, quicklinks, snippets), shows an inline calculator answer, and
  falls back to web search when nothing matches.
- **Prefixes** jump to one source, kept from the owner's KVANT walker setup:

| Prefix | Source |
|---|---|
| `/` | List of sources |
| `.` | Files (searched with `fd` on demand, no index; [[0056-quality-of-life\|ADR 0056]]) |
| `:` | Symbols and emoji |
| `=` | Calculator (`libqalculate`; [[app-list\|App list]]) |
| `@` | Web search and quicklinks |
| `$` | Clipboard history |

- **Ranking**: pinned favorites first in their fixed order, then results by
  frecency (how often and how recently each was used). Usage history stays in
  a local file and can be cleared.
- **Home screen** (empty query): the favorites grid, like the KVANT
  "Favorite Apps" menu.

### Features

| Feature | What it does |
|---|---|
| Apps | Desktop entries, title-matched |
| Commands | Every `subcult` command from `subcult commands --json` ([[0046-distribution-cli\|ADR 0046]]); commands marked dangerous ask for confirmation first ([[rice-port-review\|rice port]]) |
| Search engines and quicklinks | Keywords such as `g`, `yt`, `gh`, `aur`, `wiki`, plus user-defined URLs with `{query}`; web search is the fallback |
| Script commands | A script with a small metadata header in `~/.config/subcult/commands/` appears as a command, with arguments. Any command can get an alias and a global hotkey |
| Snippets | Saved text to search and paste, with `{date}`, `{time}` and `{clipboard}` placeholders |
| Ask AI | Sends a typed question to the default agent CLI ([[0047-ai-agents\|ADR 0047]]) and shows the answer |
| Calculator | Inline answer in root search; units and conversions through libqalculate |
| Clipboard, emoji, files | As in [[0056-quality-of-life\|ADR 0056]] |
| Preview pane | Shows the selected file, clipboard entry or snippet, as the KVANT layout did |

### Configuration

Layered like everything else ([[0048-config-ownership|ADR 0048]]): defaults in
`/usr/share/subcult/default/launcher/`, user overrides in
`~/.config/subcult/launcher/` (favorites, quicklinks, snippets, aliases,
hotkeys). Script commands live in `~/.config/subcult/commands/`.

The script-command header also accepts **Raycast's `@raycast.*` keys**
(`title`, `mode`, `argument1` …), so existing Raycast script commands run
unchanged where they do not depend on macOS tools. This compatibility choice
was proposed by the agent and confirmed by the owner on 2026-11-07.

## Options considered

| Option | Why not chosen |
|---|---|
| walker with elephant (the owner's earlier setup) | Ready today, but elephant runs all the time and walker is a separate GTK window themed separately ([[0054-lightweight-battery-first\|ADR 0054]]). |
| Shell launcher on an elephant backend | Keeps the daemon. |
| Root search only, or prefixes only | The owner wanted both. |
| Favorites then match quality, no history | The owner preferred learned ranking. |

## Sources

- The owner's KVANT walker setup:
  `~/Documents/Archives/KVANT/walker-config.toml`, `walker-layout.xml`,
  `walker-preview.xml`, `walker.css`, and the elephant favorites menu backed up
  at `~/.local/state/omarchy/theme-sync/_home_onnwee_.config_elephant_menus_kvantfavorites.toml.bak`.
- Omarchy 4.5's `omarchy.menu` shell plugin (`Menu.qml`, `MenuModel.js`):
  command-backed providers and the hierarchical system menu.
- walker and elephant (AUR, 2.17.2 and 2.22.1 on 2026-11-07) as a feature
  reference for providers.

## Consequences

- The largest single piece of shell work after the bar. Start with apps,
  favorites, commands, calculator and web search; add files, clipboard,
  snippets, script commands and Ask AI after.
- Ask AI sends the typed text to the agent's provider; the launcher labels it
  as leaving the machine.
- Quicklink and web-search traffic goes through the browser and the DNS trust
  policy ([[0020-dns|ADR 0020]]); the launcher itself makes no network calls
  except Ask AI.
- No idle cost beyond the shell: the app list is cached and refreshed when
  desktop entries change; files are searched only when asked.

## Progress

- 2026-11-07: Super+Space opens the launcher in the shell with app search,
  the favorites grid and frecency ranking (issue #61). Commands, calculator,
  web search and the other sources follow in their own issues.
- 2026-11-07: root search includes the `subcult` commands (dangerous ones
  ask first), an inline `qalc` answer and `=`, and web search through `@`,
  quicklinks and the no-match fallback (issue #71). The default engine is
  DuckDuckGo, chosen by the agent; `quicklinks.json` changes it.

Related: [[decision-map|Decision map]] · [[0036-shell-components|ADR 0036]] · [[0056-quality-of-life|ADR 0056]] · [[0046-distribution-cli|ADR 0046]]
