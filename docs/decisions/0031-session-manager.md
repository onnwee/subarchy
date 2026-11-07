---
title: "ADR 0031: Session manager"
type: decision
status: accepted
adr: 31
created: 2026-11-06
updated: 2026-11-06
tags: [decision, adr, session]
aliases: [ADR 0031, L3, uwsm]
---

# ADR 0031: Session manager

Decision map item L3. Accepted 2026-11-06.

## Decision

**uwsm** runs the compositor as a systemd user session. Desktop services
(shell, power switcher, dock and workspace watcher, idle) are user units bound
to `graphical-session.target`; launched apps run as scoped units through
`uwsm app`.

## Options considered

| Option | Why not chosen |
|---|---|
| Compositor started directly | User services cannot reliably start and stop with the session. |

## Borrowed from Omarchy

`default/uwsm/default` and `default/uwsm/env.d/` for session environment, and
Omarchy's launch wrappers that start apps through `uwsm app`.

## Consequences

- Session environment variables (GPU offload in
  [[0006-gpu-drivers|ADR 0006]], theme, input method) are set through uwsm's
  environment files rather than compositor config where possible.
- Services ship as systemd user units ([[0015-init-system|ADR 0015]]).

Related: [[decision-map|Decision map]] · [[0030-login-manager|ADR 0030]] · [[0032-compositor|ADR 0032]]
