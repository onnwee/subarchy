---
title: "ADR 0019: Firewall"
type: decision
status: accepted
adr: 19
created: 2026-11-06
updated: 2026-11-06
tags: [decision, adr, system, security]
aliases: [ADR 0019, S6, Firewall]
---

# ADR 0019: Firewall

Decision map item S6. Accepted 2026-11-06.

## Decision

**ufw** with **ufw-docker**: incoming denied and outgoing allowed by default,
and Docker-published ports filtered through ufw instead of bypassing it.

## Options considered

| Option | Why not chosen |
|---|---|
| firewalld | Network zones are useful, but more concepts and panels to build. |
| Plain nftables ruleset | Transparent, but every change is hand-edited or needs a new tool. |

## Borrowed from Omarchy

`install/config/firewall.sh`: default policies, LocalSend (`53317/tcp` and
`udp`), Docker DNS rules from private ranges to `172.17.0.1:53`, and the
`ufw-docker install` step.

## Consequences

- Rules for apps Subcarchy ships (LocalSend if kept, KDE Connect or similar)
  are added by those apps' install steps.
- No per-network zones: the same rules apply at home and on public Wi-Fi.

Related: [[decision-map|Decision map]] · [[0016-networking|ADR 0016]]
