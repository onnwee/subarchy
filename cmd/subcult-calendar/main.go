// Command subcult-calendar serves `subcult calendar ...` (ADR 0061, plan 3):
// `calendar sync` reads the CalDAV and iCal sources in
// ~/.config/subcult/calendar.toml into ~/.local/state/subcult/calendar/
// events.json, which the calendar widget watches; a user timer runs it
// every quarter hour, and on battery a sync younger than an hour is kept.
// CalDAV passwords come from the keyring: `secret-tool store --label
// "Calendar work" service subcult-calendar source work`.
//
// calendar.toml:
//
//	schema = 1
//	[[source]]
//	name = "work"            # the keyring entry and the calendar's label
//	kind = "caldav"          # or "ical"
//	url = "https://dav.example/user/calendar/"
//	user = "me"              # omit for a public ical feed
//	[[source]]
//	name = "holidays"
//	kind = "ical"
//	url = "https://example.org/holidays.ics"
package main

import (
	"context"
	"encoding/json"
	"errors"
	"flag"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"time"

	"git.subcult.tv/subculture-collective/subarchy/internal/calendar"
	"git.subcult.tv/subculture-collective/subarchy/internal/dispatch"
)

var routes = []dispatch.Described{
	{Words: []string{"calendar", "sync"}, Metadata: dispatch.Metadata{
		Summary: "Sync the configured CalDAV and iCal calendars into the cache", Args: "[--force]",
		Examples: []string{"subcult calendar sync", "subcult calendar sync --force"}}},
	{Words: []string{"calendar", "list"}, Metadata: dispatch.Metadata{
		Summary: "Show the cached events", Args: "[--json]",
		Examples: []string{"subcult calendar list"}}},
	{Words: []string{"calendar", "status"}, Metadata: dispatch.Metadata{
		Summary:  "Show when the calendars last synced and how each source fared",
		Examples: []string{"subcult calendar status"}}},
}

type paths struct {
	config, cache, powerSupply string
}

func defaultPaths() (paths, error) {
	config, err := os.UserConfigDir()
	if err != nil {
		return paths{}, err
	}
	state := os.Getenv("XDG_STATE_HOME")
	if state == "" {
		home, err := os.UserHomeDir()
		if err != nil {
			return paths{}, err
		}
		state = filepath.Join(home, ".local", "state")
	}
	return paths{
		config:      filepath.Join(config, "subcult", "calendar.toml"),
		cache:       filepath.Join(state, "subcult", "calendar", "events.json"),
		powerSupply: "/sys/class/power_supply",
	}, nil
}

type app struct {
	stdout, stderr io.Writer
	paths          func() (paths, error)
	fetch          calendar.Fetcher
	secrets        calendar.Secrets
	now            func() time.Time
}

func (a *app) run(args []string) int {
	if len(args) == 1 && args[0] == dispatch.MetadataFlag {
		if err := json.NewEncoder(a.stdout).Encode(routes); err != nil {
			return 1
		}
		return 0
	}
	if len(args) == 0 {
		fmt.Fprintln(a.stderr, "Usage: subcult calendar sync [--force] | list [--json] | status")
		return 2
	}
	fs := flag.NewFlagSet("subcult calendar", flag.ContinueOnError)
	fs.SetOutput(a.stderr)
	force := fs.Bool("force", false, "sync even when the cache is fresh")
	asJSON := fs.Bool("json", false, "machine-readable output")
	if err := fs.Parse(args[1:]); err != nil {
		return 2
	}
	p, err := a.paths()
	if err != nil {
		return a.fail(err)
	}
	cache, err := calendar.ReadCache(p.cache)
	if err != nil {
		var pathErr *os.PathError
		if args[0] != "sync" || errors.As(err, &pathErr) {
			return a.fail(err)
		}
		fmt.Fprintf(a.stderr, "subcult calendar: ignoring corrupt cache: %v\n", err)
		cache = calendar.Cache{}
	}
	switch args[0] {
	case "sync":
		cfg, err := calendar.LoadConfig(p.config)
		if err != nil {
			return a.fail(err)
		}
		if len(cfg.Sources) == 0 {
			fmt.Fprintf(a.stdout, "no calendars configured in %s\n", p.config)
			return 0
		}
		now := a.now()
		onBattery := calendar.OnBattery(p.powerSupply)
		if !calendar.Due(cache, now, onBattery, *force) {
			fmt.Fprintf(a.stdout, "cache from %s is fresh%s\n", cache.SyncedAt.Format(time.Kitchen), map[bool]string{true: " (on battery: hourly)", false: ""}[onBattery])
			return 0
		}
		next := calendar.Sync(context.Background(), cfg, cache, now, a.fetch, a.secrets)
		if err := calendar.WriteCache(p.cache, next); err != nil {
			return a.fail(err)
		}
		failed := 0
		for _, s := range next.Sources {
			if !s.OK {
				failed++
				fmt.Fprintf(a.stderr, "subcult calendar: %s: %s\n", s.Name, s.Error)
			}
		}
		fmt.Fprintf(a.stdout, "synced %d events from %d sources\n", len(next.Events), len(next.Sources)-failed)
		if failed > 0 {
			return 1
		}
		return 0
	case "list":
		if *asJSON {
			enc := json.NewEncoder(a.stdout)
			enc.SetIndent("", "  ")
			if err := enc.Encode(cache); err != nil {
				return 1
			}
			return 0
		}
		for _, e := range cache.Events {
			when := e.Start.Format("Mon 02 Jan 15:04")
			if e.AllDay {
				when = e.Start.Format("Mon 02 Jan") + " (all day)"
			}
			fmt.Fprintf(a.stdout, "%s  %s  [%s]\n", when, e.Title, e.Calendar)
		}
		return 0
	case "status":
		if cache.SyncedAt.IsZero() {
			fmt.Fprintln(a.stdout, "never synced")
			return 0
		}
		fmt.Fprintf(a.stdout, "synced %s, %d events\n", cache.SyncedAt.Format(time.RFC3339), len(cache.Events))
		for _, s := range cache.Sources {
			state := "ok"
			if !s.OK {
				state = "failed: " + s.Error
			}
			fmt.Fprintf(a.stdout, "  %s: %d events, %s\n", s.Name, s.Events, state)
		}
		return 0
	}
	fmt.Fprintf(a.stderr, "subcult calendar: unknown command %q\n", args[0])
	return 2
}

func (a *app) fail(err error) int {
	fmt.Fprintf(a.stderr, "subcult calendar: %v\n", err)
	return 1
}

func main() {
	a := &app{stdout: os.Stdout, stderr: os.Stderr, paths: defaultPaths, fetch: calendar.HTTPFetcher{}, secrets: calendar.KeyringSecrets{}, now: time.Now}
	os.Exit(a.run(os.Args[1:]))
}
