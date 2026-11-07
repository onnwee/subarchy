---
title: "ADR 0059: Agent desktop control"
type: decision
status: accepted
adr: 59
created: 2026-11-07
updated: 2026-11-07
tags: [decision, adr, ai, security]
aliases: [ADR 0059, Computer use, Desktop MCP]
---

# ADR 0059: Agent desktop control

Accepted 2026-11-07. Extends [[0047-ai-agents|ADR 0047]].

## Context

On 2026-11-07 neither vendor offered desktop control on Linux:

- Claude Desktop for Linux (beta since mid-2026) lists computer use as
  "coming soon".
- OpenAI's ChatGPT/Codex desktop app for Linux (preview since August 2026):
  an OpenAI spokesperson said computer use outside its in-app browser will
  not be available on Linux.

Browser control is covered by the Chromium extensions in
[[0042-browser|ADR 0042]]. Desktop control needs Subarchy's own piece.

## Decision

- Subarchy ships its **own MCP server, written in Go**
  ([[0046-distribution-cli|ADR 0046]]), that gives agents control of the
  desktop. Claude Code, Codex and OpenCode all speak MCP, so one server
  serves all three; Subarchy registers it in each agent's user config at
  install.
- **Scope: the whole desktop, always available** (owner's choice). No
  per-session enabling.
- Tools the server exposes, built on what Subarchy already ships:

| Capability | Built on |
|---|---|
| Screenshot of a monitor, window or region | `grim` |
| List, focus, move, resize, close windows; switch workspaces | `hyprctl` and Hyprland's IPC socket, which give exact geometry rather than guessing from pixels |
| Type text and key combinations | `wtype` |
| Move, click, scroll, drag the mouse | `ydotool` and its `ydotoold` daemon |
| Read and write the clipboard | `wl-clipboard` |
| Read an app's UI elements (buttons, fields, labels) | AT-SPI accessibility tree (`at-spi2-core`) |
| Launch apps and run `subcult` commands | the launcher's command index ([[0057-launcher\|ADR 0057]]) |

- Two safeguards that do not limit availability, proposed by the agent and
  easy to drop:
  - a bar indicator while an agent is controlling the desktop, using the
    privacy indicator from the [[rice-port-review|rice port]];
  - control pauses while the screen is locked, so an agent cannot type into
    the lock screen.

## Options considered

| Option | Why not chosen |
|---|---|
| Community Wayland computer-use server | Less control; Subarchy's needs Hyprland-specific window data. |
| Wait for official support | Neither vendor has a Linux date for native-app control. |
| Agent confined to its own workspace, off by default | Owner preferred whole-desktop, always available. |

## Consequences

- **Any agent with this server can do anything the user can do**: read the
  screen including private windows, type into any app, click through
  dialogs. Agent permission prompts (Claude Code and Codex approval modes)
  are the remaining guard.
- `ydotoold` runs all the time and needs write access to `/dev/uinput`
  (root-owned, mode `0660` with ACLs on `sputnik`). Whatever can reach its
  socket can inject keyboard and mouse input as the user; the socket is
  restricted to the user.
- Mouse actions move the real cursor and share focus with the user while an
  agent works.
- Screenshots go to the agent's model provider; the indicator shows when that
  can happen.
- Packages: `ydotool`, `grim`, `wtype`, `wl-clipboard`, `at-spi2-core` (all
  in Arch's repositories). Apps need accessibility enabled for the AT-SPI
  tree to be useful.

Related: [[decision-map|Decision map]] · [[0047-ai-agents|ADR 0047]] · [[0042-browser|ADR 0042]] · [[0054-lightweight-battery-first|ADR 0054]]
