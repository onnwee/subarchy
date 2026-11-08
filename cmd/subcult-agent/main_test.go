package main

import (
	"bytes"
	"encoding/json"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"git.subcult.tv/subculture-collective/subarchy/internal/dispatch"
)

var now = time.Date(2026, 11, 8, 15, 0, 0, 0, time.UTC)

func TestUsage(t *testing.T) {
	home := t.TempDir()
	p := filepath.Join(home, ".codex", "sessions", "2026", "11", "08", "rollout-x.jsonl")
	if err := os.MkdirAll(filepath.Dir(p), 0o755); err != nil {
		t.Fatal(err)
	}
	line := `{"timestamp":"2026-11-08T14:40:00Z","type":"event_msg","payload":{"type":"token_count","info":{"last_token_usage":{"input_tokens":2000,"output_tokens":300}},"rate_limits":{"primary":{"used_percent":42.5,"window_minutes":300,"resets_at":1794200000},"plan_type":"pro"}}}` + "\n"
	if err := os.WriteFile(p, []byte(line), 0o644); err != nil {
		t.Fatal(err)
	}
	if err := os.Chtimes(p, now, now); err != nil {
		t.Fatal(err)
	}
	cache := filepath.Join(home, "c.json")
	var out, errOut bytes.Buffer
	if code := run([]string{"usage", "--json", "--home", home, "--cache", cache}, &out, &errOut, now); code != 0 {
		t.Fatalf("exit %d: %s", code, errOut.String())
	}
	var r struct {
		Agents []struct {
			ID    string `json:"id"`
			Found bool   `json:"found"`
			Today struct {
				Total int `json:"total"`
			} `json:"today"`
			Limits []struct {
				UsedPercent float64 `json:"usedPercent"`
			} `json:"limits"`
		} `json:"agents"`
	}
	if err := json.Unmarshal(out.Bytes(), &r); err != nil || len(r.Agents) != 2 {
		t.Fatalf("json: %s %v", out.String(), err)
	}
	if r.Agents[0].ID != "claude" || r.Agents[0].Found || r.Agents[1].ID != "codex" || !r.Agents[1].Found ||
		r.Agents[1].Today.Total != 2300 || len(r.Agents[1].Limits) != 1 || r.Agents[1].Limits[0].UsedPercent != 42.5 {
		t.Errorf("report: %s", out.String())
	}
	if _, err := os.Stat(cache); err != nil {
		t.Errorf("cache not written: %v", err)
	}
	out.Reset()
	if code := run([]string{"usage", "--home", home, "--cache", cache}, &out, &errOut, now); code != 0 {
		t.Fatalf("exit %d: %s", code, errOut.String())
	}
	text := out.String()
	if !strings.Contains(text, "Claude Code  not set up") || !strings.Contains(text, "Codex        today 2.3k (300 out)  week 2.3k  pace 2.3k/h  primary 42%") {
		t.Errorf("table:\n%s", text)
	}
}

func TestUsageAndMetadata(t *testing.T) {
	var out, errOut bytes.Buffer
	if code := run(nil, &out, &errOut, now); code != 2 || !strings.Contains(errOut.String(), "Usage") {
		t.Errorf("no args: %d %s", code, errOut.String())
	}
	out.Reset()
	if code := run([]string{dispatch.MetadataFlag}, &out, &errOut, now); code != 0 {
		t.Fatalf("metadata: %d", code)
	}
	var described []dispatch.Described
	if err := json.Unmarshal(out.Bytes(), &described); err != nil || len(described) != 1 || described[0].Words[1] != "usage" {
		t.Errorf("metadata: %s %v", out.String(), err)
	}
	if tokens(999) != "999" || tokens(1234) != "1.2k" || tokens(2345678) != "2.3M" || tokens(3456789012) != "3.5G" {
		t.Error("tokens formatting")
	}
}
