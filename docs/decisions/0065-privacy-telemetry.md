---
title: "ADR 0065: Privacy and telemetry"
type: decision
status: accepted
adr: 65
created: 2026-11-07
updated: 2026-11-07
tags: [decision, adr, privacy]
aliases: [ADR 0065, Telemetry]
---

# ADR 0065: Privacy and telemetry

Accepted 2026-11-07.

## Decision

Subarchy itself sends **nothing** off the machine unless the user acts:

- no usage telemetry, no install pings, no crash uploads;
- crash reports stay local and go to an agent only when the user clicks
  "diagnose" ([[0056-quality-of-life|ADR 0056]]);
- network calls Subarchy makes on its own are limited to the update check,
  package downloads, time and time-zone lookups, weather and calendar sync,
  each listed in the user manual ([[0067-user-manual|ADR 0067]]).

Apps the user installs or signs into (browsers, agents, Proton, Tailscale)
follow their own policies.

Related: [[decision-map|Decision map]] · [[0057-launcher|ADR 0057]] · [[0059-agent-desktop-control|ADR 0059]]
