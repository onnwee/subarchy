package calendar

import (
	"context"
	"errors"
	"fmt"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"
)

var chicago = func() *time.Location { l, _ := time.LoadLocation("America/Chicago"); return l }()

const feed = "BEGIN:VCALENDAR\r\nVERSION:2.0\r\nBEGIN:VEVENT\r\nUID:a@x\r\nSUMMARY:Stand-up with a very long\r\n  folded title\\, really\r\nDTSTART;TZID=Europe/Berlin:20261110T090000\r\nDTEND;TZID=Europe/Berlin:20261110T093000\r\nLOCATION:Room 1\r\nURL:https://meet.test/a\r\nEND:VEVENT\r\n" +
	"BEGIN:VEVENT\r\nUID:b@x\r\nSUMMARY:Holiday\r\nDTSTART;VALUE=DATE:20261112\r\nEND:VEVENT\r\n" +
	"BEGIN:VEVENT\r\nUID:c@x\r\nSUMMARY:Weekly\r\nDTSTART:20261103T160000Z\r\nDURATION:PT1H\r\nRRULE:FREQ=WEEKLY;BYDAY=TU,TH;COUNT=6\r\nEXDATE:20261112T160000Z\r\nEND:VEVENT\r\n" +
	"BEGIN:VEVENT\r\nUID:c@x\r\nRECURRENCE-ID:20261117T160000Z\r\nSUMMARY:Weekly (moved)\r\nDTSTART:20261117T170000Z\r\nDTEND:20261117T180000Z\r\nEND:VEVENT\r\n" +
	"BEGIN:VEVENT\r\nUID:d@x\r\nSUMMARY:No start\r\nEND:VEVENT\r\nEND:VCALENDAR\r\n"

func TestParseICS(t *testing.T) {
	events, err := parseICS(feed, chicago)
	if err != nil {
		t.Fatal(err)
	}
	if len(events) != 4 {
		t.Fatalf("got %d events: %+v", len(events), events)
	}
	a := events[0]
	if a.summary != "Stand-up with a very long folded title, really" || a.location != "Room 1" || a.url != "https://meet.test/a" {
		t.Errorf("folded summary and fields: %+v", a)
	}
	if got := a.start.In(chicago).Format("2006-01-02 15:04"); got != "2026-11-10 02:00" {
		t.Errorf("Berlin 09:00 in Chicago = %s", got)
	}
	if !events[1].allDay || events[1].end.Sub(events[1].start) != 24*time.Hour {
		t.Errorf("all-day: %+v", events[1])
	}
	if events[2].end.Sub(events[2].start) != time.Hour || events[2].rrule == "" || len(events[2].exdates) != 1 {
		t.Errorf("duration and rrule: %+v", events[2])
	}
}

func TestOccurrences(t *testing.T) {
	events, _ := parseICS(feed, chicago)
	now := time.Date(2026, 11, 7, 12, 0, 0, 0, chicago)
	occ := Occurrences("work", events, DefaultWindow(now))
	var weekly []string
	for _, e := range occ {
		if strings.HasPrefix(e.ID, "c@x") {
			weekly = append(weekly, e.Start.UTC().Format("01-02 15:04")+" "+e.Title)
		}
	}
	// COUNT=6 from Nov 3: Nov 3, 5, 10, 12, 17, 19; the 12th is an EXDATE, the
	// 17th is overridden by the moved one; Nov 3 and 5 are before the window.
	want := []string{"11-10 16:00 Weekly", "11-17 17:00 Weekly (moved)", "11-19 16:00 Weekly"}
	if strings.Join(weekly, "|") != strings.Join(want, "|") {
		t.Errorf("weekly = %v, want %v", weekly, want)
	}
	if occ[0].Title != "Stand-up with a very long folded title, really" || occ[len(occ)-1].Start.Before(occ[0].Start) {
		t.Errorf("order: %+v", occ)
	}
	for _, e := range occ {
		if e.Calendar != "work" || e.ID == "" {
			t.Errorf("calendar and id set: %+v", e)
		}
	}
}

func TestRecurrenceKinds(t *testing.T) {
	loc := chicago
	start := time.Date(2026, 1, 31, 9, 0, 0, 0, loc)
	w := Window{From: start.AddDate(0, 0, -1), To: start.AddDate(1, 0, 0)}
	cases := map[string]int{
		"FREQ=DAILY;COUNT=3":                          3,
		"FREQ=DAILY;INTERVAL=2;UNTIL=20260206T090000": 4,
		"FREQ=MONTHLY;COUNT=4":                        4,
		"FREQ=YEARLY;COUNT=2":                         1, // the second is a year on, past the window
		"FREQ=WEEKLY;INTERVAL=2;COUNT=3":              3,
		"FREQ=SECONDLY":                               1, // unsupported: the first only
	}
	for rule, want := range cases {
		e := vevent{uid: "r", summary: rule, start: start, end: start.Add(time.Hour), rrule: rule, exdates: map[string]bool{}}
		got := Occurrences("c", []vevent{e}, w)
		if len(got) != want {
			t.Errorf("%s: %d occurrences, want %d", rule, len(got), want)
		}
	}
}

// A series that began years before the window still reaches it (review
// finding after the Epic A qualification): the cap counts kept starts.
func TestOldRecurrenceReachesWindow(t *testing.T) {
	loc := time.UTC
	w := Window{From: time.Date(2026, 11, 6, 0, 0, 0, 0, loc), To: time.Date(2026, 12, 7, 0, 0, 0, 0, loc)}
	cases := map[string]int{
		"FREQ=DAILY":                        31,
		"FREQ=WEEKLY;BYDAY=MO,TU,WE,TH,FR":  21,
		"FREQ=MONTHLY":                      1,
		"FREQ=YEARLY":                       0,
		"FREQ=DAILY;COUNT=10":               0, // ended in January 2023
		"FREQ=DAILY;UNTIL=20261110T000000Z": 4,
	}
	for rule, want := range cases {
		start := time.Date(2023, 1, 3, 9, 0, 0, 0, loc)
		e := vevent{uid: "old", summary: rule, start: start, end: start.Add(time.Hour), rrule: rule, exdates: map[string]bool{}}
		got := Occurrences("c", []vevent{e}, w)
		if len(got) != want {
			t.Errorf("%s: %d occurrences, want %d", rule, len(got), want)
		}
	}
	// A multi-day occurrence that straddles the window start is kept (and
	// the next one inside the window follows).
	start := time.Date(2026, 10, 1, 0, 0, 0, 0, loc)
	e := vevent{uid: "span", summary: "trip", start: start, end: start.AddDate(0, 0, 10), rrule: "FREQ=MONTHLY", exdates: map[string]bool{}}
	got := Occurrences("c", []vevent{e}, w)
	if len(got) != 2 || !got[0].Start.Equal(time.Date(2026, 11, 1, 0, 0, 0, 0, loc)) {
		t.Errorf("straddling: %+v", got)
	}
}

func TestParseDuration(t *testing.T) {
	for in, want := range map[string]time.Duration{"PT1H30M": 90 * time.Minute, "P1D": 24 * time.Hour, "P1W": 7 * 24 * time.Hour, "-PT15M": -15 * time.Minute, "PT45S": 45 * time.Second} {
		if got, ok := parseDuration(in); !ok || got != want {
			t.Errorf("%s = %v, %v", in, got, ok)
		}
	}
	if _, ok := parseDuration("1H"); ok {
		t.Error("no P prefix")
	}
}

func TestMultistatus(t *testing.T) {
	body := `<?xml version="1.0"?><D:multistatus xmlns:D="DAV:" xmlns:C="urn:ietf:params:xml:ns:caldav">
<D:response><D:href>/cal/1.ics</D:href><D:propstat><D:prop><C:calendar-data>BEGIN:VCALENDAR
BEGIN:VEVENT
UID:1
SUMMARY:One
DTSTART:20261110T100000Z
END:VEVENT
END:VCALENDAR</C:calendar-data></D:prop><D:status>HTTP/1.1 200 OK</D:status></D:propstat></D:response>
<D:response><D:href>/cal/2.ics</D:href><D:propstat><D:prop><C:calendar-data/></D:prop><D:status>HTTP/1.1 404 Not Found</D:status></D:propstat></D:response>
</D:multistatus>`
	texts, err := ParseMultistatus([]byte(body))
	if err != nil || len(texts) != 1 || !strings.Contains(texts[0], "SUMMARY:One") {
		t.Errorf("texts = %v, %v", texts, err)
	}
	if _, err := ParseMultistatus([]byte("not xml")); err == nil {
		t.Error("garbage must fail")
	}
}

func TestCacheRoundTrip(t *testing.T) {
	path := filepath.Join(t.TempDir(), "calendar", "events.json")
	empty, err := ReadCache(path)
	if err != nil || !empty.SyncedAt.IsZero() {
		t.Fatalf("missing cache: %+v, %v", empty, err)
	}
	now := time.Date(2026, 11, 7, 12, 0, 0, 0, chicago)
	c := Cache{SyncedAt: now, Window: DefaultWindow(now), Sources: []SourceResult{{Name: "work", OK: true, Events: 1}},
		Events: []Event{{ID: "a@x@2026", Calendar: "work", Title: "A", Start: now, End: now.Add(time.Hour)}}}
	if err := WriteCache(path, c); err != nil {
		t.Fatal(err)
	}
	back, err := ReadCache(path)
	if err != nil || back.Version != CacheVersion || len(back.Events) != 1 || !back.Events[0].Start.Equal(now) || back.Sources[0].Name != "work" {
		t.Errorf("round trip: %+v, %v", back, err)
	}
	if err := os.WriteFile(path, []byte(`{"version": 99}`), 0o644); err != nil {
		t.Fatal(err)
	}
	if old, err := ReadCache(path); err != nil || !old.SyncedAt.IsZero() {
		t.Errorf("an unknown version reads as empty: %+v, %v", old, err)
	}
}

func TestDue(t *testing.T) {
	now := time.Date(2026, 11, 7, 12, 0, 0, 0, chicago)
	fresh := Cache{SyncedAt: now.Add(-10 * time.Minute)}
	if Due(fresh, now, false, false) || Due(fresh, now, true, false) {
		t.Error("ten minutes old is fresh on AC and on battery")
	}
	stale := Cache{SyncedAt: now.Add(-20 * time.Minute)}
	if !Due(stale, now, false, false) || Due(stale, now, true, false) {
		t.Error("twenty minutes: due on AC, not on battery")
	}
	if !Due(Cache{SyncedAt: now.Add(-70 * time.Minute)}, now, true, false) {
		t.Error("over an hour: due on battery")
	}
	if !Due(fresh, now, true, true) || !Due(Cache{}, now, true, false) {
		t.Error("forced, or no cache yet")
	}
}

type fakeFetch struct {
	texts map[string][]string
	fail  map[string]error
	calls []string
}

func (f *fakeFetch) Fetch(_ context.Context, s Source, password string, _ Window) ([]string, error) {
	f.calls = append(f.calls, s.Name+":"+password)
	if err := f.fail[s.Name]; err != nil {
		return nil, err
	}
	return f.texts[s.Name], nil
}

type fakeSecrets map[string]string

func (f fakeSecrets) Password(name string) (string, error) {
	p, ok := f[name]
	if !ok {
		return "", errors.New("no password for " + name)
	}
	return p, nil
}

func TestSync(t *testing.T) {
	now := time.Date(2026, 11, 7, 12, 0, 0, 0, chicago)
	cfg := Config{Schema: 1, Sources: []Source{
		{Name: "work", Kind: "caldav", URL: "https://dav.test/cal/", User: "u"},
		{Name: "feed", Kind: "ical", URL: "https://x.test/f.ics"},
		{Name: "broken", Kind: "ical", URL: "https://x.test/b.ics"},
	}}
	prev := Cache{SyncedAt: now.Add(-time.Hour), Events: []Event{{ID: "old", Calendar: "broken", Title: "Kept", Start: now, End: now}}}
	f := &fakeFetch{texts: map[string][]string{"work": {feed}, "feed": {feed}}, fail: map[string]error{"broken": errors.New("HTTP 500")}}
	c := Sync(context.Background(), cfg, prev, now, f, fakeSecrets{"work": "pw"})
	if f.calls[0] != "work:pw" || f.calls[1] != "feed:" {
		t.Errorf("calls = %v: the caldav password comes from the keyring, an ical feed gets none", f.calls)
	}
	if len(c.Sources) != 3 || !c.Sources[0].OK || !c.Sources[1].OK || c.Sources[2].OK || !strings.Contains(c.Sources[2].Error, "HTTP 500") {
		t.Errorf("sources = %+v", c.Sources)
	}
	var kept, work int
	for _, e := range c.Events {
		switch e.Calendar {
		case "broken":
			kept++
		case "work":
			work++
		}
	}
	if kept != 1 || work == 0 || c.Sources[2].Events != 1 {
		t.Errorf("a failed source keeps its old events: kept=%d work=%d", kept, work)
	}
	for i := 1; i < len(c.Events); i++ {
		if c.Events[i].Start.Before(c.Events[i-1].Start) {
			t.Error("events are sorted by start")
		}
	}
	missing := Sync(context.Background(), Config{Sources: []Source{{Name: "nopw", Kind: "caldav", URL: "https://d.test/", User: "u"}}}, Cache{}, now, f, fakeSecrets{})
	if missing.Sources[0].OK || !strings.Contains(missing.Sources[0].Error, "no password") {
		t.Errorf("a missing keyring entry is reported: %+v", missing.Sources)
	}
}

func TestLoadConfig(t *testing.T) {
	dir := t.TempDir()
	path := filepath.Join(dir, "calendar.toml")
	if c, err := LoadConfig(path); err != nil || len(c.Sources) != 0 {
		t.Errorf("missing file is empty: %+v, %v", c, err)
	}
	good := "schema = 1\n[[source]]\nname = \"work\"\nkind = \"caldav\"\nurl = \"https://dav.test/u/cal/\"\nuser = \"me\"\n[[source]]\nname = \"feed\"\nkind = \"ical\"\nurl = \"https://x.test/f.ics\"\n"
	os.WriteFile(path, []byte(good), 0o644)
	c, err := LoadConfig(path)
	if err != nil || len(c.Sources) != 2 || c.Sources[0].User != "me" {
		t.Errorf("good config: %+v, %v", c, err)
	}
	for name, bad := range map[string]string{
		"schema":    "schema = 2\n",
		"kind":      "schema = 1\n[[source]]\nname = \"a\"\nkind = \"gcal\"\nurl = \"https://x\"\n",
		"url":       "schema = 1\n[[source]]\nname = \"a\"\nkind = \"ical\"\nurl = \"ftp://x\"\n",
		"user":      "schema = 1\n[[source]]\nname = \"a\"\nkind = \"caldav\"\nurl = \"https://x\"\n",
		"duplicate": "schema = 1\n[[source]]\nname = \"a\"\nkind = \"ical\"\nurl = \"https://x\"\n[[source]]\nname = \"a\"\nkind = \"ical\"\nurl = \"https://y\"\n",
		"password":  "schema = 1\n[[source]]\nname = \"a\"\nkind = \"caldav\"\nurl = \"https://x\"\nuser = \"u\"\npassword = \"nope\"\n",
	} {
		os.WriteFile(path, []byte(bad), 0o644)
		if _, err := LoadConfig(path); err == nil {
			t.Errorf("%s: must fail", name)
		}
	}
}

func TestOnBattery(t *testing.T) {
	ps := t.TempDir()
	put := func(dev, name, content string) {
		os.MkdirAll(filepath.Join(ps, dev), 0o755)
		os.WriteFile(filepath.Join(ps, dev, name), []byte(content+"\n"), 0o644)
	}
	put("AC", "type", "Mains")
	put("AC", "online", "1")
	put("BAT0", "type", "Battery")
	if OnBattery(ps) {
		t.Error("mains online is AC")
	}
	put("AC", "online", "0")
	if !OnBattery(ps) {
		t.Error("mains offline with a battery is battery")
	}
	desktop := t.TempDir()
	if OnBattery(desktop) {
		t.Error("no battery is AC")
	}
	// A wireless mouse reports its own battery; the desktop it is paired
	// with has no mains device at all.
	ps = t.TempDir()
	put("hidpp_battery_0", "type", "Battery")
	put("hidpp_battery_0", "scope", "Device")
	put("hidpp_battery_0", "status", "Discharging")
	if OnBattery(ps) {
		t.Error("a peripheral's battery is not the machine's")
	}
}

func TestDurationPropertyOrder(t *testing.T) {
	start := "DTSTART:20261108T120000Z\n"
	for _, properties := range []string{
		start + "DURATION:PT1H\n",
		"DURATION:PT1H\n" + start,
		"DURATION:PT2H\n" + start + "DTEND:20261108T130000Z\n",
		"DTEND:20261108T130000Z\nDURATION:PT2H\n" + start,
	} {
		t.Run(properties, func(t *testing.T) {
			events, err := parseICS("BEGIN:VEVENT\nUID:order\n"+properties+"END:VEVENT\n", time.UTC)
			if err != nil || len(events) != 1 {
				t.Fatalf("parse: %+v %v", events, err)
			}
			if got := events[0].end.Sub(events[0].start); got != time.Hour {
				t.Fatalf("duration: got %v, want 1h", got)
			}
		})
	}
}

func TestAuthenticatedICalSync(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		user, password, ok := r.BasicAuth()
		if !ok || user != "reader" || password != "feed-password" {
			w.WriteHeader(http.StatusUnauthorized)
			return
		}
		fmt.Fprint(w, "BEGIN:VEVENT\nUID:protected\nDTSTART:20261108T120000Z\nDURATION:PT1H\nEND:VEVENT\n")
	}))
	defer server.Close()
	cfg := Config{Sources: []Source{{Name: "private-feed", Kind: "ical", URL: server.URL, User: "reader"}}}
	now := time.Date(2026, 11, 8, 10, 0, 0, 0, time.UTC)
	cache := Sync(context.Background(), cfg, Cache{}, now, HTTPFetcher{Client: server.Client()}, fakeSecrets{"private-feed": "feed-password"})
	if len(cache.Events) != 1 || !cache.Sources[0].OK {
		t.Fatalf("protected feed did not sync: %+v", cache)
	}
}
