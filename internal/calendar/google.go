package calendar

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"os/exec"
	"time"
)

// SourceFetcher routes Google calendars through gws and other sources through HTTP.
type SourceFetcher struct {
	HTTP   HTTPFetcher
	Google GoogleFetcher
}

func (f SourceFetcher) Fetch(ctx context.Context, s Source, password string, w Window) ([]Event, error) {
	if s.Kind == "google" {
		return f.Google.Fetch(ctx, s, password, w)
	}
	return f.HTTP.Fetch(ctx, s, password, w)
}

// GoogleFetcher uses the Google Workspace CLI's existing sign-in. It never
// starts authentication or reads credentials itself.
type GoogleFetcher struct {
	run func(context.Context, ...string) ([]byte, error)
}

type googleDate struct {
	Date     string `json:"date"`
	DateTime string `json:"dateTime"`
	TimeZone string `json:"timeZone"`
}

type googleEvent struct {
	ID       string     `json:"id"`
	Status   string     `json:"status"`
	Summary  string     `json:"summary"`
	Start    googleDate `json:"start"`
	End      googleDate `json:"end"`
	Location string     `json:"location"`
	HTMLLink string     `json:"htmlLink"`
}

func (f GoogleFetcher) Fetch(ctx context.Context, s Source, _ string, w Window) ([]Event, error) {
	ctx, cancel := context.WithTimeout(ctx, 30*time.Second)
	defer cancel()
	run := f.run
	if run == nil {
		run = func(ctx context.Context, args ...string) ([]byte, error) {
			return exec.CommandContext(ctx, "gws", args...).Output()
		}
	}
	id := s.Calendar
	if id == "" {
		id = "primary"
	}
	params := map[string]any{
		"calendarId": id, "timeMin": w.From.UTC().Format(time.RFC3339),
		"timeMax": w.To.UTC().Format(time.RFC3339), "singleEvents": true,
		"orderBy": "startTime", "maxResults": 250,
		"fields": "items(id,status,summary,start,end,location,htmlLink),nextPageToken,timeZone",
	}
	var events []Event
	seen := map[string]bool{}
	for {
		encoded, err := json.Marshal(params)
		if err != nil {
			return nil, err
		}
		body, err := run(ctx, "calendar", "events", "list", "--params", string(encoded), "--format", "json")
		if ctx.Err() != nil {
			return nil, fmt.Errorf("gws calendar: %w", ctx.Err())
		}
		if errors.Is(err, exec.ErrNotFound) {
			return nil, errors.New("gws is missing; install the Google Workspace CLI and run gws auth login -s calendar")
		}
		if err != nil {
			// stderr can contain account data. Keep it out of the cache and journal.
			return nil, errors.New("gws calendar failed; check gws auth login -s calendar and calendar access")
		}
		var page *struct {
			Items         []googleEvent   `json:"items"`
			NextPageToken string          `json:"nextPageToken"`
			TimeZone      string          `json:"timeZone"`
			Error         json.RawMessage `json:"error"`
		}
		if err := json.Unmarshal(body, &page); err != nil || page == nil {
			return nil, errors.New("gws calendar returned invalid JSON")
		}
		if len(page.Error) > 0 && string(page.Error) != "null" {
			return nil, errors.New("Google Calendar request failed; check gws authentication and calendar access")
		}
		for _, item := range page.Items {
			if item.Status == "cancelled" {
				continue
			}
			start, allDay, err := item.Start.parse(page.TimeZone, w.From.Location())
			if err != nil {
				return nil, err
			}
			end, endAllDay, err := item.End.parse(page.TimeZone, w.From.Location())
			if err != nil {
				return nil, err
			}
			if item.ID == "" || allDay != endAllDay || !end.After(start) {
				return nil, errors.New("Google Calendar event has an invalid ID or time range")
			}
			if end.After(w.From) && start.Before(w.To) {
				events = append(events, Event{
					ID: "google/" + item.ID, Calendar: s.Name, Title: item.Summary,
					Start: start, End: end, AllDay: allDay, Location: item.Location, URL: item.HTMLLink,
				})
			}
		}
		if page.NextPageToken == "" {
			return events, nil
		}
		if seen[page.NextPageToken] {
			return nil, errors.New("Google Calendar repeated a page token")
		}
		seen[page.NextPageToken] = true
		params["pageToken"] = page.NextPageToken
	}
}

func (d googleDate) parse(calendarZone string, local *time.Location) (time.Time, bool, error) {
	if d.Date != "" && d.DateTime == "" {
		t, err := time.ParseInLocation(time.DateOnly, d.Date, local)
		if err == nil {
			return t, true, nil
		}
	}
	if d.DateTime != "" && d.Date == "" {
		if t, err := time.Parse(time.RFC3339, d.DateTime); err == nil {
			return t.In(local), false, nil
		}
		zone := d.TimeZone
		if zone == "" {
			zone = calendarZone
		}
		if loc, err := time.LoadLocation(zone); zone != "" && err == nil {
			if t, err := time.ParseInLocation("2006-01-02T15:04:05", d.DateTime, loc); err == nil {
				return t.In(local), false, nil
			}
		}
	}
	return time.Time{}, false, errors.New("Google Calendar event has an invalid date or time")
}
