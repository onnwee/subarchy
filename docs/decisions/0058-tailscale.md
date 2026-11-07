---
title: "ADR 0058: Tailscale"
type: decision
status: accepted
adr: 58
created: 2026-11-07
updated: 2026-11-07
tags: [decision, adr, system, network]
aliases: [ADR 0058, S12, Tailscale, Taildrop]
---

# ADR 0058: Tailscale

Decision map item S12, added 2026-11-07. Accepted 2026-11-07.

## Decision

- **Tailscale** is preinstalled (`tailscale` from Arch's `extra`, 1.104.2 on
  2026-11-07). `tailscaled` is enabled; the user signs in when they want it.
- A **bar panel** shows status, lets the user switch exit nodes and browse
  machines, and copies addresses, as Omarchy's `omarchy.tailscale` panel does.
- **Taildrop**: files sent to the machine land in `~/Downloads`
  automatically, through a small user service.
- MagicDNS and Tailscale's split DNS stay on Tailscale's own link
  ([[0020-dns|ADR 0020]]).

## Options considered

| Option | Why not chosen |
|---|---|
| Not preinstalled | The owner's fleet uses Tailscale on every machine. |

## Borrowed from Omarchy

The `omarchy.tailscale` shell panel, `omarchy-tailscale-receive.service` and
its receive script (staging directory under Downloads), and the exit-node
pause during captive portal sign-in.

## Consequences

- `tailscaled` runs all the time once enabled; it is idle when not signed in.
  ([[0054-lightweight-battery-first|ADR 0054]] counts it.)
- The Taildrop receiver runs only while signed in.
- Firewall: Tailscale manages its own `tailscale0` interface. Omarchy's
  firewall script has no Tailscale rule; check whether ufw needs one when
  implementing ([[0019-firewall|ADR 0019]]).

Related: [[decision-map|Decision map]] · [[0020-dns|ADR 0020]] · [[0016-networking|ADR 0016]]
