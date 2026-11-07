---
title: "ADR 0017: Audio"
type: decision
status: accepted
adr: 17
created: 2026-11-06
updated: 2026-11-06
tags: [decision, adr, system, audio]
aliases: [ADR 0017, S4, Audio]
---

# ADR 0017: Audio

Decision map item S4. Accepted 2026-11-06.

## Decision

- **PipeWire** with **WirePlumber** as the session manager.
- Compatibility layers on every install: `pipewire-pulse`, `pipewire-alsa`
  and **`pipewire-jack`**, so JACK apps such as Ardour and Guitarix run
  without a separate JACK server.
- **Realtime scheduling** for the desktop user through the
  `realtime-privileges` package (`realtime` group), so audio apps get low
  latency without setup.

## Options considered

| Option | Why not chosen |
|---|---|
| PipeWire desktop defaults only | Music and pro-audio apps would need extra setup. |

## Consequences

- Any process the user runs can request realtime priority within the group's
  limits. A runaway realtime process can make the desktop unresponsive; the
  limits in `realtime-privileges` bound this.
- `sputnik` already has `realtime-privileges` and the owner in the `realtime`
  group.

Related: [[decision-map|Decision map]] · [[0015-init-system|ADR 0015]]
