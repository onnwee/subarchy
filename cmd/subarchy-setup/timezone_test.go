package main

import (
	"bufio"
	"context"
	"errors"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strings"
	"testing"

	"git.subcult.tv/subculture-collective/subarchy/internal/setup"
)

// The first service to name a zone wins; a failed or empty one does not
// end the wait for the other.
func TestLookupZone(t *testing.T) {
	// A lookup that has its answer leaves the slower request running until
	// it is cancelled, so each lookup gets its own replies.
	answering := func(first, second string) func(context.Context, string) ([]byte, error) {
		replies := map[string]string{zoneServices[0].url: first, zoneServices[1].url: second}
		return func(_ context.Context, url string) ([]byte, error) {
			if r, ok := replies[url]; ok {
				return []byte(r), nil
			}
			return nil, errors.New("not asked for")
		}
	}
	got := lookupZone(answering(`{"error": true, "reason": "RateLimited"}`,
		`{"success": true, "timezone": {"id": "America/Chicago", "utc": "-06:00"}}`))
	if got != "America/Chicago" {
		t.Errorf("lookupZone = %q", got)
	}
	if got := lookupZone(answering(`{"ip": "192.0.2.1", "timezone": "Europe/Berlin"}`, `not json`)); got != "Europe/Berlin" {
		t.Errorf("lookupZone = %q", got)
	}
	failing := func(context.Context, string) ([]byte, error) { return nil, errors.New("offline") }
	if got := lookupZone(failing); got != "" {
		t.Errorf("lookupZone offline = %q", got)
	}
}

func TestHTTPGet(t *testing.T) {
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path == "/missing" {
			http.NotFound(w, r)
			return
		}
		w.Write([]byte(`{"timezone": "Europe/Oslo"}`))
	}))
	defer srv.Close()
	body, err := httpGet(context.Background(), srv.URL+"/json/")
	if err != nil || zoneIn(body, []string{"timezone"}) != "Europe/Oslo" {
		t.Errorf("httpGet = %q, %v", body, err)
	}
	if _, err := httpGet(context.Background(), srv.URL+"/missing"); err == nil {
		t.Error("a 404 counted as an answer")
	}
}

func TestZoneGuess(t *testing.T) {
	list := []string{"America/Chicago", "Europe/Berlin", "UTC"}
	asked, waited := 0, 0
	lookup := func(zone string) func() string {
		return func() string { asked++; return zone }
	}
	wait := func() { waited++ }

	// Online: the network's zone, asked once, with a page while it waits.
	g, a := &zoneGuess{}, setup.Answers{Timezone: "UTC", Locale: "de_DE.UTF-8"}
	if note := g.guess(&a, lookup("America/Chicago"), list, wait); a.Timezone != "America/Chicago" || !strings.Contains(note, "network") {
		t.Errorf("online: %q, %q", a.Timezone, note)
	}
	g.guess(&a, lookup("America/Chicago"), list, wait)
	if asked != 1 || waited != 1 {
		t.Errorf("asked the network %d times, waited %d", asked, waited)
	}

	// A zone the list does not have (an alias) is not used; the language's is.
	g, a = &zoneGuess{}, setup.Answers{Timezone: "UTC", Locale: "de_DE.UTF-8"}
	if note := g.guess(&a, lookup("US/Central"), list, wait); a.Timezone != "Europe/Berlin" || !strings.Contains(note, "language") {
		t.Errorf("alias: %q, %q", a.Timezone, note)
	}
	// Back to the language screen and English (US): no zone of its own, so UTC.
	a.Locale = "en_US.UTF-8"
	if note := g.guess(&a, nil, list, wait); a.Timezone != "UTC" || note != "" {
		t.Errorf("language changed: %q, %q", a.Timezone, note)
	}

	// Once the user has picked, nothing replaces it.
	g, a = &zoneGuess{picked: true}, setup.Answers{Timezone: "UTC", Locale: "de_DE.UTF-8"}
	if note := g.guess(&a, lookup("America/Chicago"), list, wait); a.Timezone != "UTC" || note != "" {
		t.Errorf("picked: %q, %q", a.Timezone, note)
	}
}

// The plain prompts offer the network's zone as the default.
func TestPlainTimeZoneGuess(t *testing.T) {
	e := testEnv(t)
	e.lookupZone = func() string { return "Europe/Berlin" }
	var out strings.Builder
	p := &prompter{in: bufio.NewReader(strings.NewReader(goodInputDefaultZone)), out: &out}
	p.secret = func() (string, error) {
		s, err := p.in.ReadString('\n')
		return strings.TrimRight(s, "\n"), err
	}
	a, err := collect(p, e, "file:///repo", "")
	if err != nil || a.Timezone != "Europe/Berlin" || !strings.Contains(out.String(), "Time zone [Europe/Berlin]") ||
		!strings.Contains(out.String(), "Looking up the time zone") {
		t.Errorf("zone %q, err %v:\n%s", a.Timezone, err, out.String())
	}

	// A file under zoneinfo that is not a zone is not offered, though
	// ValidTimezone would take it.
	os.WriteFile(filepath.Join(e.zoneinfo, "posixrules"), nil, 0o644)
	e.lookupZone = func() string { return "posixrules" }
	out.Reset()
	p.in = bufio.NewReader(strings.NewReader(goodInputDefaultZone))
	if a, err := collect(p, e, "file:///repo", ""); err != nil || a.Timezone != "UTC" || !strings.Contains(out.String(), "Time zone [UTC]") {
		t.Errorf("zone %q, err %v:\n%s", a.Timezone, err, out.String())
	}
}

// goodInput with Enter at the time zone question.
var goodInputDefaultZone = strings.TrimSuffix(goodInput, "Mars/Base\nEurope/Berlin\n") + "\n"
