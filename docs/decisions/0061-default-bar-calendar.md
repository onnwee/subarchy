---
title: "ADR 0061: Default bar and calendar"
type: decision
status: accepted
adr: 61
created: 2026-11-07
updated: 2026-11-07
tags: [decision, adr, shell]
aliases: [ADR 0061, Bar layout, Calendar]
---

# ADR 0061: Default bar and calendar

Accepted 2026-11-07.

## Decision

**The default bar is the owner's current bar on `sputnik`**, rebuilt with
Subarchy's own widgets and ports ([[0035-plugin-api|ADR 0035]]). Layout read
from `~/.config/omarchy/shell.json` on 2026-11-07:

| Section | Widgets, in order |
|---|---|
| Left | menu, workspaces, active window |
| Centre | status indicators, microphone, SomaFM radio, calendar, world clock (Elsewhen), system update, weather (Linecast) |
| Right | keyboard layout, Switchyard, n8n, Bitwarden, plugin manager (omaplug), downloads (otoru), auto wallpaper, agents usage, tray, audio, display, HT3 headphones, Bluetooth, network, notification centre, Dell power |

- Per monitor, as the multi-monitor bar does now: **Full** on the main
  screen and the laptop panel, **Minimal** on the others.
- Widgets tied to particular hardware or services show only when present:
  HT3 (the headphones), Dell power (a Dell), Switchyard and n8n (the owner's
  homelab services).

**Calendar**: the bar's calendar is a port of the `tmn73.calendar` plugin,
which already reads and writes **Google Calendar** and any **CalDAV**
server (iCloud, Nextcloud, Fastmail and others), and reads iCal feeds. Proton
Calendar is not reachable from other apps, so it is not a source.

## Consequences

- Every widget on this bar becomes part of the porting list: the Omarchy
  built-ins are rebuilt, the community and own plugins are ported
  ([[triage|Triage]]).
- The calendar's sync runs as a user timer; it is the bar's only scheduled
  network job besides the update check and weather.
- Google sync uses the Google Workspace CLI that the plugin depends on.

## Progress

- 2026-11-07: `subcult calendar sync` (issue #70) reads CalDAV collections
  (a calendar-query REPORT for the window) and iCal feeds from
  `~/.config/subcult/calendar.toml` into
  `~/.local/state/subcult/calendar/events.json`: yesterday to thirty days
  out, recurrences expanded (daily, weekly, monthly, yearly; COUNT, UNTIL,
  INTERVAL, EXDATE, overridden occurrences). CalDAV passwords come from the
  keyring (`secret-tool`, service `subcult-calendar`), never the config,
  which refuses a `password` field. The user timer runs every quarter hour;
  on battery a sync younger than an hour is kept. Google sync is still to
  come (#113).
- 2026-11-07: the bar's calendar widget (issue #90) shows the next event
  from that cache ("Standup 14:00", "Standup now", "Tomorrow Dentist 09:00")
  and opens a month panel with a mark on days that have events and the
  selected day's list. The cache file is watched; the label follows the
  shared minute clock; nothing polls.

Related: [[decision-map|Decision map]] · [[0036-shell-components|ADR 0036]] · [[0057-launcher|ADR 0057]]
