package calendar

import (
	"context"
	"encoding/json"
	"errors"
	"net/http"
	"net/http/httptest"
	"os/exec"
	"strings"
	"testing"
	"time"
)

func TestGooglePagesAndOccurrences(t *testing.T) {
	now := time.Date(2026, 11, 7, 12, 0, 0, 0, chicago)
	w := DefaultWindow(now)
	pages := []string{
		`{"items":[],"nextPageToken":"second"}`,
		`{"timeZone":"Europe/Berlin","nextPageToken":"third","items":[
		{"id":"series_20261110T080000Z","summary":"Stand-up","start":{"dateTime":"2026-11-10T09:00:00+01:00"},"end":{"dateTime":"2026-11-10T09:30:00+01:00"},"location":"Room 1","htmlLink":"https://calendar.google.com/event?eid=fixture"},
		{"id":"floating","summary":"Local to calendar","start":{"dateTime":"2026-11-11T09:00:00"},"end":{"dateTime":"2026-11-11T10:00:00"}},
		{"id":"cancelled","status":"cancelled"}]}`,
		`{"items":[
		{"id":"holiday","summary":"Holiday","start":{"date":"2026-11-12"},"end":{"date":"2026-11-14"}},
		{"id":"outside","start":{"date":"2027-01-01"},"end":{"date":"2027-01-02"}}]}`,
	}
	calls := 0
	f := GoogleFetcher{run: func(ctx context.Context, args ...string) ([]byte, error) {
		deadline, ok := ctx.Deadline()
		if !ok || time.Until(deadline) > 30*time.Second {
			t.Error("gws must have a bounded deadline")
		}
		if len(args) != 7 || strings.Join(args[:4], " ") != "calendar events list --params" || strings.Join(args[5:], " ") != "--format json" {
			t.Fatalf("unexpected command arguments: %q", args)
		}
		var p map[string]any
		if err := json.Unmarshal([]byte(args[4]), &p); err != nil {
			t.Fatal(err)
		}
		if p["calendarId"] != `team"; $(touch /tmp/never)@group.calendar.google.com` || p["singleEvents"] != true || p["orderBy"] != "startTime" || p["timeMin"] != w.From.UTC().Format(time.RFC3339) || p["timeMax"] != w.To.UTC().Format(time.RFC3339) {
			t.Errorf("request must use the source and cache window: %+v", p)
		}
		if want := []any{nil, "second", "third"}[calls]; p["pageToken"] != want {
			t.Errorf("page %d token = %v, want %v", calls, p["pageToken"], want)
		}
		body := pages[calls]
		calls++
		return []byte(body), nil
	}}
	events, err := f.Fetch(context.Background(), Source{Name: "work", Calendar: `team"; $(touch /tmp/never)@group.calendar.google.com`}, "", w)
	if err != nil || calls != 3 || len(events) != 3 {
		t.Fatalf("events=%+v calls=%d err=%v", events, calls, err)
	}
	if e := events[0]; e.ID != "google/series_20261110T080000Z" || e.Calendar != "work" || e.Title != "Stand-up" || e.Start.Format("2006-01-02 15:04") != "2026-11-10 02:00" || e.End.Sub(e.Start) != 30*time.Minute || e.Location != "Room 1" || e.URL != "https://calendar.google.com/event?eid=fixture" {
		t.Errorf("timed occurrence: %+v", e)
	}
	if e := events[1]; e.Start.Hour() != 2 || e.Start.Location() != chicago {
		t.Errorf("calendar timezone converted to local time: %+v", e)
	}
	if e := events[2]; !e.AllDay || e.Start.Format(time.DateOnly) != "2026-11-12" || e.End.Format(time.DateOnly) != "2026-11-14" || e.Start.Location() != chicago {
		t.Errorf("all-day dates keep the exclusive end in local time: %+v", e)
	}
}

func TestGoogleFailuresKeepPreviousCache(t *testing.T) {
	now := time.Date(2026, 11, 7, 12, 0, 0, 0, chicago)
	previous := Cache{Events: []Event{{ID: "old", Calendar: "google", Title: "Kept", Start: now, End: now.Add(time.Hour)}}}
	for name, tc := range map[string]struct {
		body string
		err  error
		want string
	}{
		"invalid JSON":    {`private account output`, nil, "invalid JSON"},
		"null":            {`null`, nil, "invalid JSON"},
		"API error":       {`{"error":{"code":401,"message":"private account output"}}`, nil, "authentication"},
		"command failed":  {"private account output", errors.New("private account output"), "gws calendar failed"},
		"missing command": {"", exec.ErrNotFound, "gws is missing"},
		"invalid event":   {`{"items":[{"id":"broken","start":{"dateTime":"private account output"}}]}`, nil, "invalid date"},
		"invalid range":   {`{"items":[{"id":"broken","start":{"date":"2026-11-10"},"end":{"date":"2026-11-09"}}]}`, nil, "time range"},
	} {
		t.Run(name, func(t *testing.T) {
			f := SourceFetcher{Google: GoogleFetcher{run: func(_ context.Context, args ...string) ([]byte, error) {
				var p map[string]any
				if err := json.Unmarshal([]byte(args[4]), &p); err != nil || p["calendarId"] != "primary" {
					t.Fatalf("default calendar: %v %v", p, err)
				}
				return []byte(tc.body), tc.err
			}}}
			// A Google source must not ask the CalDAV keyring for a password.
			cache := Sync(context.Background(), Config{Sources: []Source{{Name: "google", Kind: "google"}}}, previous, now, f, nil)
			if len(cache.Events) != 1 || cache.Events[0].ID != "old" || cache.Sources[0].OK || !strings.Contains(cache.Sources[0].Error, tc.want) || strings.Contains(cache.Sources[0].Error, "private account output") {
				t.Errorf("failed source should retain events and report a safe error: %+v", cache)
			}
		})
	}
}

func TestGoogleIncompletePagesAndCancellation(t *testing.T) {
	w := DefaultWindow(time.Now())
	for _, failSecond := range []bool{false, true} {
		calls := 0
		f := GoogleFetcher{run: func(_ context.Context, _ ...string) ([]byte, error) {
			calls++
			if failSecond && calls == 2 {
				return nil, errors.New("network failed")
			}
			return []byte(`{"items":[],"nextPageToken":"same"}`), nil
		}}
		if events, err := f.Fetch(context.Background(), Source{}, "", w); err == nil || events != nil || calls != 2 {
			t.Errorf("partial result must fail, calls=%d events=%v err=%v", calls, events, err)
		}
	}
	ctx, cancel := context.WithCancel(context.Background())
	f := GoogleFetcher{run: func(ctx context.Context, _ ...string) ([]byte, error) {
		cancel()
		<-ctx.Done()
		return nil, errors.New("killed")
	}}
	if _, err := f.Fetch(ctx, Source{}, "", w); !errors.Is(err, context.Canceled) {
		t.Errorf("cancellation: %v", err)
	}
}

func TestSourceFetcherMixedCalendars(t *testing.T) {
	now := time.Date(2026, 11, 7, 12, 0, 0, 0, chicago)
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.Method != http.MethodGet {
			t.Errorf("iCal request method: %s", r.Method)
		}
		_, _ = w.Write([]byte(feed))
	}))
	defer server.Close()
	f := SourceFetcher{Google: GoogleFetcher{run: func(_ context.Context, _ ...string) ([]byte, error) {
		return []byte(`{"items":[{"id":"g","summary":"Google event","start":{"date":"2026-11-11"},"end":{"date":"2026-11-12"}}]}`), nil
	}}}
	cache := Sync(context.Background(), Config{Sources: []Source{
		{Name: "feed", Kind: "ical", URL: server.URL}, {Name: "google", Kind: "google"},
	}}, Cache{}, now, f, nil)
	if len(cache.Sources) != 2 || !cache.Sources[0].OK || !cache.Sources[1].OK || cache.Sources[0].Events == 0 || cache.Sources[1].Events != 1 {
		t.Fatalf("mixed source cache: %+v", cache)
	}
	for i := 1; i < len(cache.Events); i++ {
		if cache.Events[i].Start.Before(cache.Events[i-1].Start) {
			t.Error("mixed events must be sorted")
		}
	}
}

func TestGoogleMissingExecutable(t *testing.T) {
	t.Setenv("PATH", t.TempDir())
	_, err := (GoogleFetcher{}).Fetch(context.Background(), Source{}, "", DefaultWindow(time.Now()))
	if err == nil || !strings.Contains(err.Error(), "gws is missing") {
		t.Errorf("missing gws: %v", err)
	}
}
