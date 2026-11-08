// Package agentusage reads what the coding agents on this machine used, from
// their own local files (ADR 0047; stage 3 agents widget, issue #92). Two
// providers: Claude Code (~/.claude/projects/*/*.jsonl, one line per message
// with its token usage) and Codex (~/.codex/sessions/**/rollout-*.jsonl,
// token_count events with the account's rate limits). Nothing on the
// network: limits are what the provider last wrote to disk.
//
// A scan reads the files changed in the last week, in ten-minute buckets;
// a cache keyed by path, size and modification time keeps the buckets of
// files that have not changed, so a refresh reads only the sessions still
// running.
package agentusage

import (
	"bufio"
	"encoding/json"
	"io/fs"
	"os"
	"path/filepath"
	"sort"
	"strings"
	"time"
)

// Window is a token count over a period.
type Window struct {
	Input  int `json:"input"`
	Output int `json:"output"`
	Total  int `json:"total"`
}

func (w *Window) add(in, out int) {
	w.Input += in
	w.Output += out
	w.Total += in + out
}

// Limit is one rate-limit window a provider reports.
type Limit struct {
	Name          string    `json:"name"`
	UsedPercent   float64   `json:"usedPercent"`
	WindowMinutes int       `json:"windowMinutes"`
	ResetsAt      time.Time `json:"resetsAt"`
}

// Agent is one provider's record.
type Agent struct {
	ID         string    `json:"id"`
	Name       string    `json:"name"`
	Found      bool      `json:"found"` // the provider's files exist
	Today      Window    `json:"today"`
	Week       Window    `json:"week"`
	PaceHour   int       `json:"paceHour"` // tokens in the last hour
	LastActive time.Time `json:"lastActive"`
	Sessions   int       `json:"sessions"` // files active today
	Limits     []Limit   `json:"limits"`
	Plan       string    `json:"plan,omitempty"`
}

// Report is the whole answer.
type Report struct {
	ScannedAt time.Time `json:"scannedAt"`
	Agents    []Agent   `json:"agents"`
}

const bucketLen = 10 * time.Minute
const keep = 7 * 24 * time.Hour

type bucket struct {
	At     time.Time `json:"at"`
	Input  int       `json:"input"`
	Output int       `json:"output"`
}

type fileSummary struct {
	Size    int64     `json:"size"`
	ModTime time.Time `json:"modTime"`
	Buckets []bucket  `json:"buckets"`
	Last    time.Time `json:"last"`
	Limits  []Limit   `json:"limits,omitempty"`
	LimitAt time.Time `json:"limitAt,omitempty"`
	Plan    string    `json:"plan,omitempty"`
}

// Cache is the per-file memory between scans.
type Cache struct {
	Files map[string]fileSummary `json:"files"`
}

// LoadCache reads a cache file; a missing or broken one is empty.
func LoadCache(path string) Cache {
	c := Cache{Files: map[string]fileSummary{}}
	b, err := os.ReadFile(path)
	if err != nil {
		return c
	}
	if json.Unmarshal(b, &c) != nil || c.Files == nil {
		c.Files = map[string]fileSummary{}
	}
	return c
}

// Save writes the cache, dropping files no longer scanned.
func (c Cache) Save(path string) error {
	if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
		return err
	}
	b, err := json.Marshal(c)
	if err != nil {
		return err
	}
	return os.WriteFile(path, b, 0o600)
}

type provider struct {
	id, name string
	dir      func(home string) string
	match    func(path string) bool
	parse    func(line string) (at time.Time, in, out int, limits []Limit, plan string, ok bool)
}

var providers = []provider{
	{
		id: "claude", name: "Claude Code",
		dir:   func(home string) string { return filepath.Join(home, ".claude", "projects") },
		match: func(p string) bool { return strings.HasSuffix(p, ".jsonl") },
		parse: parseClaude,
	},
	{
		id: "codex", name: "Codex",
		dir:   func(home string) string { return filepath.Join(home, ".codex", "sessions") },
		match: func(p string) bool { return strings.HasSuffix(p, ".jsonl") },
		parse: parseCodex,
	},
}

// Scan reads every provider under home, using and updating the cache.
func Scan(home string, cache *Cache, now time.Time) Report {
	r := Report{ScannedAt: now}
	seen := map[string]bool{}
	for _, p := range providers {
		a := Agent{ID: p.id, Name: p.name}
		root := p.dir(home)
		if st, err := os.Stat(root); err == nil && st.IsDir() {
			a.Found = true
		}
		var limitAt time.Time
		dayStart := time.Date(now.Year(), now.Month(), now.Day(), 0, 0, 0, 0, now.Location())
		_ = filepath.WalkDir(root, func(path string, d fs.DirEntry, err error) error {
			if err != nil || d.IsDir() || !p.match(path) {
				return nil
			}
			info, err := d.Info()
			if err != nil || now.Sub(info.ModTime()) > keep {
				return nil
			}
			seen[path] = true
			fsum, ok := cache.Files[path]
			if !ok || fsum.Size != info.Size() || !fsum.ModTime.Equal(info.ModTime()) {
				fsum = summarize(path, info, p.parse)
				cache.Files[path] = fsum
			}
			active := false
			for _, b := range fsum.Buckets {
				if now.Sub(b.At) > keep {
					continue
				}
				a.Week.add(b.Input, b.Output)
				if !b.At.Before(dayStart) {
					a.Today.add(b.Input, b.Output)
					active = true
				}
				if now.Sub(b.At) < time.Hour {
					a.PaceHour += b.Input + b.Output
				}
			}
			if active {
				a.Sessions++
			}
			if fsum.Last.After(a.LastActive) {
				a.LastActive = fsum.Last
			}
			if len(fsum.Limits) > 0 && fsum.LimitAt.After(limitAt) {
				limitAt = fsum.LimitAt
				a.Limits = fsum.Limits
				a.Plan = fsum.Plan
			}
			return nil
		})
		if a.Limits == nil {
			a.Limits = []Limit{}
		}
		r.Agents = append(r.Agents, a)
	}
	for path := range cache.Files {
		if !seen[path] {
			delete(cache.Files, path)
		}
	}
	return r
}

func summarize(path string, info fs.FileInfo, parse func(string) (time.Time, int, int, []Limit, string, bool)) fileSummary {
	s := fileSummary{Size: info.Size(), ModTime: info.ModTime()}
	claudeIDs = map[string]bool{}
	f, err := os.Open(path)
	if err != nil {
		return s
	}
	defer f.Close()
	buckets := map[time.Time]*bucket{}
	sc := bufio.NewScanner(f)
	sc.Buffer(make([]byte, 1024*1024), 64*1024*1024)
	for sc.Scan() {
		at, in, out, limits, plan, ok := parse(sc.Text())
		if !ok {
			continue
		}
		if in+out > 0 {
			k := at.Truncate(bucketLen)
			b := buckets[k]
			if b == nil {
				b = &bucket{At: k}
				buckets[k] = b
			}
			b.Input += in
			b.Output += out
		}
		if at.After(s.Last) {
			s.Last = at
		}
		if len(limits) > 0 && !at.Before(s.LimitAt) {
			s.Limits, s.LimitAt, s.Plan = limits, at, plan
		}
	}
	for _, b := range buckets {
		s.Buckets = append(s.Buckets, *b)
	}
	sort.Slice(s.Buckets, func(i, j int) bool { return s.Buckets[i].At.Before(s.Buckets[j].At) })
	return s
}

// Claude Code writes one line per message; an assistant message's usage
// repeats on every content block, all with the same message id, so each
// file counts a message id once (the first line carries the usage).
func parseClaude(line string) (time.Time, int, int, []Limit, string, bool) {
	if !strings.Contains(line, `"usage"`) || !strings.Contains(line, `"assistant"`) {
		return time.Time{}, 0, 0, nil, "", false
	}
	var d struct {
		Type      string `json:"type"`
		Timestamp string `json:"timestamp"`
		Message   struct {
			ID    string `json:"id"`
			Usage struct {
				Input         int `json:"input_tokens"`
				CacheCreation int `json:"cache_creation_input_tokens"`
				CacheRead     int `json:"cache_read_input_tokens"`
				Output        int `json:"output_tokens"`
			} `json:"usage"`
		} `json:"message"`
	}
	if json.Unmarshal([]byte(line), &d) != nil || d.Type != "assistant" {
		return time.Time{}, 0, 0, nil, "", false
	}
	at, err := time.Parse(time.RFC3339Nano, d.Timestamp)
	if err != nil {
		return time.Time{}, 0, 0, nil, "", false
	}
	if d.Message.ID != "" && claudeSeen(d.Message.ID) {
		return at, 0, 0, nil, "", true
	}
	u := d.Message.Usage
	return at, u.Input + u.CacheCreation + u.CacheRead, u.Output, nil, "", true
}

// Message ids seen in the file being summarized; reset per file.
var claudeIDs = map[string]bool{}

func claudeSeen(id string) bool {
	if claudeIDs[id] {
		return true
	}
	claudeIDs[id] = true
	return false
}

// Codex writes a token_count event per response with the tokens of that
// response and the account's rate limits as of then.
func parseCodex(line string) (time.Time, int, int, []Limit, string, bool) {
	if !strings.Contains(line, `"token_count"`) {
		return time.Time{}, 0, 0, nil, "", false
	}
	var d struct {
		Type      string `json:"type"`
		Timestamp string `json:"timestamp"`
		Payload   struct {
			Type string `json:"type"`
			Info *struct {
				Last struct {
					Input  int `json:"input_tokens"`
					Output int `json:"output_tokens"`
				} `json:"last_token_usage"`
			} `json:"info"`
			RateLimits *struct {
				Primary   *codexLimit `json:"primary"`
				Secondary *codexLimit `json:"secondary"`
				PlanType  string      `json:"plan_type"`
			} `json:"rate_limits"`
		} `json:"payload"`
	}
	if json.Unmarshal([]byte(line), &d) != nil || d.Type != "event_msg" || d.Payload.Type != "token_count" {
		return time.Time{}, 0, 0, nil, "", false
	}
	at, err := time.Parse(time.RFC3339Nano, d.Timestamp)
	if err != nil {
		return time.Time{}, 0, 0, nil, "", false
	}
	var in, out int
	if d.Payload.Info != nil {
		in, out = d.Payload.Info.Last.Input, d.Payload.Info.Last.Output
	}
	var limits []Limit
	var plan string
	if rl := d.Payload.RateLimits; rl != nil {
		plan = rl.PlanType
		if rl.Primary != nil {
			limits = append(limits, rl.Primary.limit("primary"))
		}
		if rl.Secondary != nil {
			limits = append(limits, rl.Secondary.limit("secondary"))
		}
	}
	return at, in, out, limits, plan, true
}

type codexLimit struct {
	UsedPercent   float64 `json:"used_percent"`
	WindowMinutes int     `json:"window_minutes"`
	ResetsAt      int64   `json:"resets_at"`
}

func (c codexLimit) limit(name string) Limit {
	l := Limit{Name: name, UsedPercent: c.UsedPercent, WindowMinutes: c.WindowMinutes}
	if c.ResetsAt > 0 {
		l.ResetsAt = time.Unix(c.ResetsAt, 0).UTC()
	}
	return l
}
