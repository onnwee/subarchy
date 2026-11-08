package agentusage

import (
	"os"
	"path/filepath"
	"testing"
	"time"
)

var now = time.Date(2026, 11, 8, 15, 0, 0, 0, time.UTC)

func write(t *testing.T, path, content string, mod time.Time) {
	t.Helper()
	if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(path, []byte(content), 0o644); err != nil {
		t.Fatal(err)
	}
	if err := os.Chtimes(path, mod, mod); err != nil {
		t.Fatal(err)
	}
}

func claudeLine(ts, id string, in, cacheRead, out int) string {
	return `{"type":"assistant","timestamp":"` + ts + `","message":{"id":"` + id + `","role":"assistant","usage":{"input_tokens":` + itoa(in) +
		`,"cache_creation_input_tokens":0,"cache_read_input_tokens":` + itoa(cacheRead) + `,"output_tokens":` + itoa(out) + `}}}` + "\n"
}

func codexLine(ts string, in, out int, limits bool) string {
	rl := "null"
	if limits {
		rl = `{"primary":{"used_percent":42.5,"window_minutes":300,"resets_at":1794200000},"secondary":{"used_percent":12,"window_minutes":10080,"resets_at":1794600000},"plan_type":"pro"}`
	}
	return `{"timestamp":"` + ts + `","type":"event_msg","payload":{"type":"token_count","info":{"last_token_usage":{"input_tokens":` + itoa(in) +
		`,"cached_input_tokens":0,"output_tokens":` + itoa(out) + `}},"rate_limits":` + rl + `}}` + "\n"
}

func itoa(n int) string {
	b := []byte{}
	if n == 0 {
		return "0"
	}
	for n > 0 {
		b = append([]byte{byte('0' + n%10)}, b...)
		n /= 10
	}
	return string(b)
}

func home(t *testing.T) string {
	t.Helper()
	h := t.TempDir()
	// Claude: a session today with a message repeated over two content blocks,
	// one yesterday, and a stale file outside the week.
	write(t, filepath.Join(h, ".claude", "projects", "-home-pat-work", "a.jsonl"),
		`{"type":"user","timestamp":"2026-11-08T14:30:00Z","message":{"role":"user","content":"hi"}}`+"\n"+
			claudeLine("2026-11-08T14:30:05Z", "msg_1", 10, 1000, 200)+
			claudeLine("2026-11-08T14:30:05Z", "msg_1", 10, 1000, 200)+
			claudeLine("2026-11-08T13:50:00Z", "msg_0", 5, 500, 100)+
			"not json\n",
		now.Add(-time.Minute))
	write(t, filepath.Join(h, ".claude", "projects", "-home-pat-work", "b.jsonl"),
		claudeLine("2026-11-07T10:00:00Z", "msg_2", 1, 2000, 300), now.Add(-29*time.Hour))
	write(t, filepath.Join(h, ".claude", "projects", "-home-pat-old", "c.jsonl"),
		claudeLine("2026-10-20T10:00:00Z", "msg_3", 1, 9000, 900), now.Add(-19*24*time.Hour))
	// Codex: one rollout today with limits, one from 3 days ago without.
	write(t, filepath.Join(h, ".codex", "sessions", "2026", "11", "08", "rollout-2026-11-08T14-00-00-x.jsonl"),
		`{"timestamp":"2026-11-08T14:00:00Z","type":"session_meta","payload":{"id":"x"}}`+"\n"+
			codexLine("2026-11-08T13:55:00Z", 3000, 400, false)+
			codexLine("2026-11-08T14:40:00Z", 2000, 300, true),
		now.Add(-time.Minute))
	write(t, filepath.Join(h, ".codex", "sessions", "2026", "11", "05", "rollout-2026-11-05T09-00-00-y.jsonl"),
		codexLine("2026-11-05T09:10:00Z", 7000, 700, false), now.Add(-3*24*time.Hour))
	return h
}

func TestScan(t *testing.T) {
	h := home(t)
	cache := LoadCache(filepath.Join(h, "cache.json"))
	r := Scan(h, &cache, now)
	if len(r.Agents) != 2 {
		t.Fatalf("agents: %+v", r.Agents)
	}
	c, x := r.Agents[0], r.Agents[1]
	if c.ID != "claude" || !c.Found || x.ID != "codex" || !x.Found {
		t.Errorf("ids: %+v %+v", c, x)
	}
	// Claude today: msg_1 once (1010 in, 200 out) + msg_0 (505 in, 100 out).
	if c.Today != (Window{Input: 1515, Output: 300, Total: 1815}) {
		t.Errorf("claude today: %+v", c.Today)
	}
	if c.Week != (Window{Input: 1515 + 2001, Output: 600, Total: 1815 + 2301}) {
		t.Errorf("claude week: %+v", c.Week)
	}
	// Pace: the 13:50 bucket is 70 minutes old; only msg_1 counts.
	if c.PaceHour != 1210 || c.Sessions != 1 || !c.LastActive.Equal(time.Date(2026, 11, 8, 14, 30, 5, 0, time.UTC)) {
		t.Errorf("claude pace %d sessions %d last %v", c.PaceHour, c.Sessions, c.LastActive)
	}
	if len(c.Limits) != 0 {
		t.Errorf("claude has no limits on disk: %+v", c.Limits)
	}
	if x.Today != (Window{Input: 5000, Output: 700, Total: 5700}) || x.Week.Total != 5700+7700 {
		t.Errorf("codex: today %+v week %+v", x.Today, x.Week)
	}
	if x.PaceHour != 2300 {
		t.Errorf("codex pace: %d (the 13:55 response falls in the 13:50 bucket, outside the hour)", x.PaceHour)
	}
	if len(x.Limits) != 2 || x.Limits[0].Name != "primary" || x.Limits[0].UsedPercent != 42.5 || x.Limits[0].WindowMinutes != 300 ||
		!x.Limits[0].ResetsAt.Equal(time.Unix(1794200000, 0)) || x.Limits[1].UsedPercent != 12 || x.Plan != "pro" {
		t.Errorf("codex limits: %+v plan %q", x.Limits, x.Plan)
	}
	if len(cache.Files) != 4 {
		t.Errorf("cache holds %d files, want the 4 within the week", len(cache.Files))
	}
}

func TestCacheReuseAndInvalidation(t *testing.T) {
	h := home(t)
	path := filepath.Join(h, "cache.json")
	cache := LoadCache(path)
	first := Scan(h, &cache, now)
	if err := cache.Save(path); err != nil {
		t.Fatal(err)
	}
	// Make a cached file unreadable: an unchanged size and mtime must still answer from the cache.
	a := filepath.Join(h, ".claude", "projects", "-home-pat-work", "a.jsonl")
	st, _ := os.Stat(a)
	if err := os.WriteFile(a, []byte(string(make([]byte, st.Size()))), 0o644); err != nil {
		t.Fatal(err)
	}
	if err := os.Chtimes(a, st.ModTime(), st.ModTime()); err != nil {
		t.Fatal(err)
	}
	cache = LoadCache(path)
	again := Scan(h, &cache, now)
	if again.Agents[0].Today != first.Agents[0].Today {
		t.Errorf("an unchanged file was re-read: %+v vs %+v", again.Agents[0].Today, first.Agents[0].Today)
	}
	// A grown file is re-read.
	write(t, a, claudeLine("2026-11-08T14:55:00Z", "msg_9", 100, 0, 50), now)
	again = Scan(h, &cache, now)
	if again.Agents[0].Today != (Window{Input: 100, Output: 50, Total: 150}) {
		t.Errorf("a changed file kept its cache: %+v", again.Agents[0].Today)
	}
	// A file gone from disk leaves the cache.
	if err := os.Remove(a); err != nil {
		t.Fatal(err)
	}
	Scan(h, &cache, now)
	if _, ok := cache.Files[a]; ok {
		t.Error("a removed file stayed in the cache")
	}
	if LoadCache(filepath.Join(h, "missing.json")).Files == nil {
		t.Error("a missing cache is not empty")
	}
}

func TestNoProviders(t *testing.T) {
	cache := LoadCache("")
	r := Scan(t.TempDir(), &cache, now)
	for _, a := range r.Agents {
		if a.Found || a.Week.Total != 0 || a.Limits == nil {
			t.Errorf("empty home: %+v", a)
		}
	}
}

func TestParseRejects(t *testing.T) {
	for _, line := range []string{"", "{", `{"type":"user","message":{"usage":{}}}`, `{"type":"assistant","timestamp":"bad","message":{"usage":{}}}`} {
		if _, _, _, _, _, ok := parseClaude(line); ok {
			t.Errorf("claude accepted %q", line)
		}
	}
	for _, line := range []string{"", `{"type":"event_msg","payload":{"type":"token_count"}}`, `{"timestamp":"2026-11-08T14:00:00Z","type":"response_item","payload":{"type":"token_count"}}`} {
		if _, _, _, _, _, ok := parseCodex(line); ok {
			t.Errorf("codex accepted %q", line)
		}
	}
}
