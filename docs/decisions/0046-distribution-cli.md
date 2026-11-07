---
title: "ADR 0046: Distribution CLI"
type: decision
status: accepted
adr: 46
created: 2026-11-06
updated: 2026-11-06
tags: [decision, adr, apps, cli]
aliases: [ADR 0046, A7, CLI]
---

# ADR 0046: Distribution CLI

Decision map item A7. Accepted 2026-11-06.

## Decision

**Shape.** One dispatcher command, named after the product (R4), routes
`<name> <group> <action>` to individual commands, for example
`<name> theme set`, `<name> default browser`, `<name> app install`. Every
command carries metadata (summary, arguments, examples) that the dispatcher
reads for `--help`, `<name> commands`, and `<name> commands --json`, which
shell menus and AI agents use.

**Languages.**

- **Bash** for thin glue: wrappers around system tools, launchers, toggles,
  and commands borrowed from Omarchy.
- **Go** for stateful or complex logic: the app list and installer
  ([[0044-default-apps|ADR 0044]]), the DNS trust policy
  ([[0020-dns|ADR 0020]]), migrations and the update command
  ([[0026-update-model|ADR 0026]]), theme rendering
  ([[0037-theming|ADR 0037]]) and hardware detection
  ([[0005-firmware|ADR 0005]]).

## Options considered

| Option | Why not chosen |
|---|---|
| Separate commands with no dispatcher | Harder to discover and document. |
| Bash only (Omarchy) | Fragile for the stateful features above. |
| Go only | Every borrowed Omarchy script would be rewritten. |

## Borrowed from Omarchy

The dispatcher design (`/usr/bin/omarchy`, 1,169 lines in 4.5.0) and the
metadata comment format at the top of each script:

```bash
# omarchy:summary=Apply an Omarchy theme
# omarchy:args=<theme-name>
# omarchy:examples=omarchy theme list | omarchy theme set "Tokyo Night"
```

Subcarchy uses the same idea under its own prefix, and the Go binary reports
the same fields for its subcommands so the dispatcher lists both alike.

## Consequences

- CI runs `shellcheck` and `bats` on Bash commands and `go test` on the Go
  code.
- A rule decides where a command lives: if it keeps state, parses structured
  data, or needs tests beyond a smoke test, it is Go.
- Hidden commands (Omarchy hides 131 of 556) are marked in metadata.

Related: [[decision-map|Decision map]] · [[0044-default-apps|ADR 0044]] · [[0047-ai-agents|ADR 0047]]
