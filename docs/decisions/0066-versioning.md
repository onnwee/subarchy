---
title: "ADR 0066: Versioning"
type: decision
status: accepted
adr: 66
created: 2026-11-07
updated: 2026-11-20
tags: [decision, adr, delivery]
aliases: [ADR 0066, Versions]
---

# ADR 0066: Versioning

Accepted 2026-11-07.

## Decision

Subarchy uses semantic versions **starting at `0.0.0`**. Release cadence and
what a release contains are deferred; the owner does not need them yet.

## Consequences

`os-release` carries `VERSION_ID` from this scheme
([[0052-name-identity|ADR 0052]]); migrations are ordered by timestamp, not
by version ([[0026-update-model|ADR 0026]]).

## Progress

**2026-11-20 (#278).** The version stays `0.0.0`. A release build is now
told from a development build by its build identity, not by a new version:
the release built from tag `v0.0.0` reports `0.0.0` in `subcult --version`
and os-release's `VERSION`, with `BUILD_ID=v0.0.0`; a main build reports
`0.0.0+dev.<commits>.g<commit>` (semantic-version build metadata).
`VERSION_ID` stays `0.0.0`. Details:
[[package-publishing#Versions and retries|Package publishing]].

Related: [[decision-map|Decision map]] · [[0026-update-model|ADR 0026]]
