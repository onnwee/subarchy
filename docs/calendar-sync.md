---
title: "Calendar sync"
type: guide
status: active
created: 2026-11-14
updated: 2026-11-14
tags: [guide, calendar, shell]
aliases: [Google Calendar setup]
---

# Calendar sync

`subcult calendar sync` fills the calendar widget's local cache from CalDAV,
iCal feeds and Google Calendar. Configure sources in
`~/.config/subcult/calendar.toml`; each source needs a unique name. The name
is the calendar label in the cache and widget.

## Google Calendar

Install the [Google Workspace CLI (`gws`)](https://github.com/googleworkspace/cli#installation)
using its installation instructions. Make the binary available in
`/usr/local/bin` or `/usr/bin` so both your terminal and the systemd user
timer can find it. Subarchy does not bundle `gws`.

Complete the CLI's [OAuth setup](https://github.com/googleworkspace/cli#authentication)
on the desktop where the calendar runs, then sign in for Calendar:

```sh
gws auth login -s calendar
```

The sign-in is interactive. The sync timer never opens a browser or starts
sign-in. Credentials stay with `gws`; do not put a password, token, `user`
or `url` in a Google source.

```toml
schema = 1

[[source]]
name = "google"
kind = "google"
calendar = "primary"
```

`calendar` is optional and defaults to `primary`. For another calendar, use
its ID from Google Calendar's **Settings → Integrate calendar → Calendar ID**.
Add another source with a different name for each additional calendar.
Then run:

```sh
subcult calendar sync --force
subcult calendar status
subcult calendar list
```

The cache covers yesterday through thirty days ahead. Google expands
recurring events in that window; the sync reads every result page, keeps
timed events in the desktop's local time and keeps all-day dates with an
exclusive end date. Cancelled events are omitted. The widget reads the same
cache as other sources, with no additional network polling.

If `gws` is missing, sign-in expires, a calendar is inaccessible or a page
fails, sync exits with an error and keeps that source's previous events.
`subcult calendar status` shows the failure. Raw `gws` output is not copied
to the cache's error field or the timer's journal; use the CLI directly to
diagnose account access. Each Google source has a thirty-second deadline
across all pages.

## CalDAV and iCal

These can share the config with Google sources:

```toml
[[source]]
name = "work"
kind = "caldav"
url = "https://dav.example/user/calendar/"
user = "me"

[[source]]
name = "holidays"
kind = "ical"
url = "https://example.org/holidays.ics"
```

Store the CalDAV password in the keyring:

```sh
secret-tool store --label "Calendar work" service subcult-calendar source work
```

An authenticated iCal feed can also specify `user` and use the keyring
entry under its source name. Public feeds need neither.

## Timer and verification

`subcult-calendar-sync.timer` runs every fifteen minutes. On battery, a
cache younger than an hour is kept; `--force` bypasses that interval. The
cache is `~/.local/state/subcult/calendar/events.json` (or under
`$XDG_STATE_HOME` when set).

The Google adapter is covered by fixtures for paging, event times, mixed
sources and failed syncs. The owner's signed-in Google account still needs
the checkpoint in [issue #89](https://github.com/subculture-collective/subarchy/issues/89).

Related: [[0061-default-bar-calendar|ADR 0061]] · [[0054-lightweight-battery-first|ADR 0054]]
