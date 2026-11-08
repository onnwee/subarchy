package main

import (
	"bytes"
	"context"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"git.subcult.tv/subculture-collective/subarchy/internal/calendar"
)

type fakeFetch struct{ texts []string }

func (f fakeFetch) Fetch(context.Context, calendar.Source, string, calendar.Window) ([]string, error) {
	return f.texts, nil
}

type fakeSecrets struct{}

func (fakeSecrets) Password(string) (string, error) { return "pw", nil }

func harness(t *testing.T, config string) (*app, *bytes.Buffer, *bytes.Buffer, paths) {
	t.Helper()
	dir := t.TempDir()
	p := paths{config: filepath.Join(dir, "calendar.toml"), cache: filepath.Join(dir, "state", "events.json"), powerSupply: filepath.Join(dir, "ps")}
	if config != "" {
		os.WriteFile(p.config, []byte(config), 0o644)
	}
	out, errOut := &bytes.Buffer{}, &bytes.Buffer{}
	now := time.Date(2026, 11, 7, 12, 0, 0, 0, time.UTC)
	feed := "BEGIN:VCALENDAR\nBEGIN:VEVENT\nUID:1\nSUMMARY:Lunch\nDTSTART:20261108T120000Z\nDTEND:20261108T130000Z\nEND:VEVENT\nEND:VCALENDAR\n"
	a := &app{stdout: out, stderr: errOut, paths: func() (paths, error) { return p, nil }, fetch: fakeFetch{[]string{feed}}, secrets: fakeSecrets{}, now: func() time.Time { return now }}
	return a, out, errOut, p
}

func TestSyncListStatus(t *testing.T) {
	a, out, errOut, p := harness(t, "schema = 1\n[[source]]\nname = \"feed\"\nkind = \"ical\"\nurl = \"https://x.test/f.ics\"\n")
	if code := a.run([]string{"status"}); code != 0 || !strings.Contains(out.String(), "never synced") {
		t.Fatalf("status before: %d %q", code, out.String())
	}
	out.Reset()
	if code := a.run([]string{"sync"}); code != 0 || !strings.Contains(out.String(), "synced 1 events from 1 sources") {
		t.Fatalf("sync: %d %q %q", code, out.String(), errOut.String())
	}
	if _, err := os.Stat(p.cache); err != nil {
		t.Fatal("no cache written")
	}
	out.Reset()
	if code := a.run([]string{"sync"}); code != 0 || !strings.Contains(out.String(), "is fresh") {
		t.Errorf("a second sync within the interval is skipped: %d %q", code, out.String())
	}
	out.Reset()
	if code := a.run([]string{"sync", "--force"}); code != 0 || !strings.Contains(out.String(), "synced 1 events") {
		t.Errorf("--force syncs: %d %q", code, out.String())
	}
	out.Reset()
	if code := a.run([]string{"list"}); code != 0 || !strings.Contains(out.String(), "Lunch  [feed]") {
		t.Errorf("list: %d %q", code, out.String())
	}
	out.Reset()
	if code := a.run([]string{"list", "--json"}); code != 0 || !strings.Contains(out.String(), `"version": 1`) {
		t.Errorf("list --json: %d %q", code, out.String())
	}
	out.Reset()
	if code := a.run([]string{"status"}); code != 0 || !strings.Contains(out.String(), "feed: 1 events, ok") {
		t.Errorf("status: %d %q", code, out.String())
	}
}

func TestNoConfigAndErrors(t *testing.T) {
	a, out, errOut, _ := harness(t, "")
	if code := a.run([]string{"sync"}); code != 0 || !strings.Contains(out.String(), "no calendars configured") {
		t.Errorf("no config: %d %q", code, out.String())
	}
	a2, _, errOut2, _ := harness(t, "schema = 1\n[[source]]\nname = \"a\"\nkind = \"caldav\"\nurl = \"https://x\"\nuser = \"u\"\npassword = \"nope\"\n")
	if code := a2.run([]string{"sync"}); code != 1 || !strings.Contains(errOut2.String(), "keyring") {
		t.Errorf("a password in the config is refused: %d %q", code, errOut2.String())
	}
	if code := a.run([]string{"frob"}); code != 2 || !strings.Contains(errOut.String(), "unknown command") {
		t.Errorf("unknown: %d", code)
	}
	if code := a.run(nil); code != 2 {
		t.Errorf("usage: %d", code)
	}
}
