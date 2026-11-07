---
title: "ADR 0047: AI agent integration"
type: decision
status: accepted
adr: 47
created: 2026-11-06
updated: 2026-11-06
tags: [decision, adr, apps, ai]
aliases: [ADR 0047, A8, AI agents]
---

# ADR 0047: AI agent integration

Decision map item A8. Accepted 2026-11-06.

## Decision

Built into the base system, lighter than Omarchy:

- **Default agent**: a role in the app list
  ([[0044-default-apps|ADR 0044]]), set with the default picker, with a
  launcher command and keybinding.
- **Usage widget**: the bar widget showing usage, limits and pace per agent,
  ported to Subarchy's plugin API ([[0035-plugin-api|ADR 0035]]).
- **Agent skills** for Subarchy's own commands, generated from the CLI's
  `commands --json` ([[0046-distribution-cli|ADR 0046]]), so agents can
  operate the system.
- **Sign-in** stays with each tool (`claude`, `codex` and so on). Subarchy
  does not manage agent accounts.

## Options considered

| Option | Why not chosen |
|---|---|
| Full Omarchy parity | `omarchy agent account` (add, copy, exec, home, list, mode, remove, rename, state, transfer, use) plus 23 usage providers is a large surface to maintain. |
| Optional add-on | The owner uses agents daily; they belong in the base. |

## Borrowed from Omarchy

- The `omarchy.agents` bar widget and the `omarchy agent usage <provider>`
  readers for the providers the owner uses.
- `default/agents/skills/` (`omarchy`, `omarchy-app`, `diagnose-crash`) as
  models for Subarchy's skills.
- `omarchy default agent` and its launcher.

## Consequences

- Usage readers depend on each provider's local files or APIs and break when
  those change; each reader needs a test fixture.
- Agent CLIs install through mise or the app installer, not as system
  packages ([[0028-developer-toolchains|ADR 0028]]).
- Dictation (voxtype on `sputnik`) is a separate app-list role.
- Browser control comes from the Chromium extensions in
  [[0042-browser|ADR 0042]]; desktop control from Subarchy's MCP server in
  [[0059-agent-desktop-control|ADR 0059]].

Related: [[decision-map|Decision map]] · [[0046-distribution-cli|ADR 0046]] · [[0044-default-apps|ADR 0044]]
