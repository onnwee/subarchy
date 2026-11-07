---
title: "ADR 0035: Shell plugin API"
type: decision
status: accepted
adr: 35
created: 2026-11-06
updated: 2026-11-06
tags: [decision, adr, shell]
aliases: [ADR 0035, D2, Plugin API]
---

# ADR 0035: Shell plugin API

Decision map item D2. Accepted 2026-11-06.

## Decision

- Subarchy designs **its own plugin API** for the shell. It is not
  compatible with Omarchy's `manifest.json` (schemaVersion 1) API.
- Plugins worth keeping are **ported by hand**: the owner's plugins, the
  SUBCULT rice features that survive review, and selected community plugins.
- No third-party plugin loads unchanged at launch.

## Options considered

| Option | Why not chosen |
|---|---|
| Start from Omarchy's shell and keep its API | Community plugins would load for free, but Subarchy would inherit Omarchy's API shape and paths. |
| Own API with no plugins at launch | Loses features the owner relies on. |

## Consequences

- The API needs its own design record before shell code is written: manifest
  format, plugin kinds (bar widget, panel, overlay, service, menu), settings
  storage, IPC, permissions, versioning.
- Omarchy's API is still a reference: its kinds and its scoped settings writes
  solved real problems, including the service-access and settings-save fixes
  the owner patched on `sputnik`.
- Community plugin licences must be checked before porting; each port records
  its source and licence.
- [[triage|The triage]] becomes the porting list. Its "default" and
  "optional" rows need a port estimate.

Related: [[decision-map|Decision map]] · [[0034-shell-toolkit|ADR 0034]] · [[triage|Triage]]
