package calendar

import (
	"context"
	"fmt"
	"os/exec"
	"sort"
	"strings"
	"time"
)

// Secrets looks a CalDAV password up by source name.
type Secrets interface {
	Password(name string) (string, error)
}

// KeyringSecrets reads `secret-tool lookup service subcult-calendar source
// <name>`: the password the user stored with
// `secret-tool store --label "Calendar <name>" service subcult-calendar source <name>`.
type KeyringSecrets struct{}

// Password reads the source's password from the keyring.
func (KeyringSecrets) Password(name string) (string, error) {
	out, err := exec.Command("secret-tool", "lookup", "service", "subcult-calendar", "source", name).Output()
	if err != nil {
		return "", fmt.Errorf("no password for %q in the keyring (secret-tool store --label 'Calendar %s' service subcult-calendar source %s)", name, name, name)
	}
	return strings.TrimRight(string(out), "\n"), nil
}

// Intervals: on AC the timer's quarter hour is the sync interval; on
// battery a sync younger than an hour is kept (ADR 0054).
const (
	IntervalAC      = 15 * time.Minute
	IntervalBattery = 60 * time.Minute
)

// Due reports whether a sync should run now: always when forced or when no
// cache exists, else when the cache is older than the interval for the
// power source.
func Due(c Cache, now time.Time, onBattery, force bool) bool {
	if force || c.SyncedAt.IsZero() {
		return true
	}
	interval := IntervalAC
	if onBattery {
		interval = IntervalBattery
	}
	return now.Sub(c.SyncedAt) >= interval
}

// Sync fetches every source into a fresh cache. A source that fails keeps
// the events it had in the previous cache and reports its error; the
// others are replaced.
func Sync(ctx context.Context, cfg Config, prev Cache, now time.Time, fetch Fetcher, secrets Secrets) Cache {
	w := DefaultWindow(now)
	next := Cache{SyncedAt: now, Window: w}
	kept := map[string][]Event{}
	for _, e := range prev.Events {
		kept[e.Calendar] = append(kept[e.Calendar], e)
	}
	for _, s := range cfg.Sources {
		res := SourceResult{Name: s.Name}
		password := ""
		var err error
		if s.Kind == "caldav" {
			password, err = secrets.Password(s.Name)
		}
		var texts []string
		if err == nil {
			texts, err = fetch.Fetch(ctx, s, password, w)
		}
		var events []Event
		if err == nil {
			for _, t := range texts {
				ves, perr := parseICS(t, now.Location())
				if perr != nil {
					err = perr
					break
				}
				events = append(events, Occurrences(s.Name, ves, w)...)
			}
		}
		if err != nil {
			res.Error = err.Error()
			events = kept[s.Name]
		} else {
			res.OK = true
		}
		res.Events = len(events)
		next.Sources = append(next.Sources, res)
		next.Events = append(next.Events, events...)
	}
	sort.Slice(next.Events, func(i, j int) bool {
		if next.Events[i].Start.Equal(next.Events[j].Start) {
			return next.Events[i].ID < next.Events[j].ID
		}
		return next.Events[i].Start.Before(next.Events[j].Start)
	})
	return next
}
