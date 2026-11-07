---
title: "ADR 0068: Shell plugin API v0"
type: decision
status: proposed
adr: 68
created: 2026-11-07
updated: 2026-11-07
tags: [decision, adr, shell]
aliases: [ADR 0068, Plugin API v0]
---

# ADR 0068: Shell plugin API v0

## Context

[[0035-plugin-api|ADR 0035]] says Subarchy designs its own shell plugin API
and records it before shell code is written. The first shell stage
([[shell-and-look-design|Shell and look design]]) needs about twenty widgets,
all written for Subarchy. v0 is the smallest API that
carries them and keeps the battery rules machine-readable
([[0054-lightweight-battery-first|ADR 0054]]).

## Options

| Option | Why not chosen |
|---|---|
| Omarchy's `manifest.json` schemaVersion 1 | Rejected in ADR 0035. |
| Design the full API first (all plugin kinds, permissions, user plugin folders) | Guesses at needs no widget has yet. |

## Proposed decision

- **Where plugins live**: only inside the shell tree,
  `/usr/share/subcult/shell/widgets/<id>/`. v0 loads nothing from user
  folders.
- **Folder**: `manifest.json`, `Widget.qml`, optional `Panel.qml`, optional
  `tests/`.
- **Manifest**:

```json
{
  "id": "subcult.weather",
  "name": "Weather",
  "version": "1.0.0",
  "api": 0,
  "kind": "bar-widget",
  "panel": true,
  "cost": {
    "timers": [
      { "name": "current", "ac": 900, "battery": 1800 },
      { "name": "forecast", "ac": 7200, "battery": 21600 }
    ],
    "network": ["api.open-meteo.com"]
  },
  "settings": { "location": "" }
}
```

  `kind` is `bar-widget` or `service` (a widget with no bar item, such as the
  notification daemon). `cost` lists
  every repeating timer in seconds and every host contacted; an empty
  `cost` means event-driven only. `settings` holds defaults.
- **Widget contract**: the shell sets `mode` (`full` or `minimal`), `screen`,
  `settings` (defaults merged with the user's bar config) and `shell`, which
  gives `theme`, `power`, `config` and the services. The widget emits
  `openPanel()`; the shell owns the popup and loads `Panel.qml` only while it
  is open.
- **Intervals**: widgets call `shell.power.interval(<timer name>)`, which
  returns the AC or battery value from the manifest. No hard-coded intervals.
- **Settings writes**: `shell.config.set(key, value)` writes only under the
  widget's own id in `~/.config/subcult/shell/bar.json`. This keeps the scoped
  write that fixed `sputnik`'s monitor-bar save bug.
- **IPC**: a widget that needs outside calls registers a Quickshell
  `IpcHandler` with target `subcult.<name>`; `qs ipc call` reaches it.
- **Versioning**: the shell loads only manifests whose `api` matches its own.
  Changing the contract raises the number and updates every in-tree widget in
  the same change.

## Consequences

- Plugin kinds beyond bar widgets and services, user plugin folders,
  permissions and a plugin manager wait for v1.
- CI can read every manifest's `cost` and fail a widget that adds a timer
  without battery values.

Related: [[0035-plugin-api|ADR 0035]] · [[0034-shell-toolkit|ADR 0034]] · [[shell-and-look-design|Shell and look design]] · [[decisions-index|Decisions]]
