---
title: "ADR 0041: Interactive shell and prompt"
type: decision
status: accepted
adr: 41
created: 2026-11-06
updated: 2026-11-06
tags: [decision, adr, apps]
aliases: [ADR 0041, A2, zsh]
---

# ADR 0041: Interactive shell and prompt

Decision map item A2. Accepted 2026-11-06.

## Decision

- **bash** stays the login shell and the shell for system scripts.
- **zsh** is the interactive shell in terminals, with the **starship**
  prompt and **atuin** shell history.

## Options considered

| Option | Why not chosen |
|---|---|
| bash with starship (Omarchy) | Fewer interactive features. |
| fish | Not POSIX; pasted bash snippets sometimes fail. |

## Borrowed

- The owner's Estate Config shared zsh layer and the guarded bash-to-zsh
  handoff, as on `sputnik` (Machinum host briefing, 2026-10-13).
- Omarchy's `config/starship.toml` and `default/bash` as the bash baseline.

## Consequences

- Terminals start zsh; scripts use `#!/usr/bin/env bash`.
- atuin history sync is off by default; it would send history to a server.
- Shell integration for theme and context features ships for zsh and bash.

Related: [[decision-map|Decision map]] · [[0040-terminal|ADR 0040]]
