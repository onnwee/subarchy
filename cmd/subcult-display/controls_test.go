package main

import (
	"encoding/json"
	"io"
	"os"
	"path/filepath"
	"strings"
	"testing"

	"git.subcult.tv/subculture-collective/subarchy/internal/display"
)

func lidHarness(t *testing.T) (*app, *fakeHypr) {
	t.Helper()
	a, h, _, _ := harness(t)
	a.lidFile = filepath.Join(t.TempDir(), "display-lid.json")
	return a, h
}

func TestLidKeepsOnlyExternalDisplaysAndRestoresPanel(t *testing.T) {
	a, h := lidHarness(t)
	if code := a.run([]string{"lid", "closed"}); code != 0 || len(h.evals) != 1 || h.evals[0] != `hl.monitor({ output = "eDP-1", disabled = true })` {
		t.Fatalf("close: %d %v", code, h.evals)
	}
	before, err := os.ReadFile(a.lidFile)
	if err != nil {
		t.Fatal(err)
	}
	ms, _ := display.ParseMonitors([]byte(dockJSON))
	ms[0].Disabled, ms[0].Width, ms[0].Height, ms[0].Scale = true, 0, 0, 0
	raw, err := json.Marshal(ms)
	if err != nil {
		t.Fatal(err)
	}
	h.monitors = string(raw)
	if code := a.run([]string{"lid", "closed"}); code != 0 || len(h.evals) != 1 {
		t.Fatalf("duplicate close: %d %v", code, h.evals)
	}
	after, err := os.ReadFile(a.lidFile)
	if err != nil || string(before) != string(after) {
		t.Fatal("duplicate close overwrote the snapshot", err)
	}
	if code := a.run([]string{"lid", "open"}); code != 0 || len(h.evals) != 2 {
		t.Fatalf("open: %d %v", code, h.evals)
	}
	if got := h.evals[1]; !strings.Contains(got, `scale = 1.6`) || !strings.Contains(got, `position = "4480x0"`) || !strings.Contains(got, `mode = "3456x2160@60.001"`) {
		t.Errorf("panel layout was not restored: %s", got)
	}
	if len(h.dispatch) != 1 || !strings.Contains(h.dispatch[0], `workspace = "2", monitor = "eDP-1"`) {
		t.Errorf("panel workspace was not restored: %v", h.dispatch)
	}
	if _, err := os.Stat(a.lidFile); !os.IsNotExist(err) {
		t.Errorf("snapshot not removed after restoration: %v", err)
	}
}

func TestLidNeverDisablesTheOnlyUsableDisplay(t *testing.T) {
	a, h := lidHarness(t)
	h.monitors = laptopJSON
	if code := a.run([]string{"lid", "closed"}); code != 0 || len(h.evals) != 0 {
		t.Fatalf("undocked close disabled the panel: %d %v", code, h.evals)
	}
	if _, err := os.Stat(a.lidFile); !os.IsNotExist(err) {
		t.Errorf("undocked close saved a snapshot: %v", err)
	}
}

func TestWatchRestoresPanelWhenDockUnpluggedWhileClosed(t *testing.T) {
	a, h := lidHarness(t)
	if code := a.run([]string{"lid", "closed"}); code != 0 {
		t.Fatal("close failed")
	}
	h.evals = nil
	a.lidClosed = func() (bool, error) { return true, nil }
	h.monitors = strings.Replace(laptopJSON, `"disabled":false`, `"disabled":true`, 1)
	a.events = func() (io.ReadCloser, error) { return io.NopCloser(strings.NewReader("monitorremoved>>DP-3\n")), nil }
	if code := a.run([]string{"watch"}); code != 0 || len(h.evals) != 1 || !strings.Contains(h.evals[0], `scale = 1.6`) {
		t.Fatalf("unplug failed to recover panel without a saved dock profile: %d %v", code, h.evals)
	}
}

func TestScaleChangesOnlyFocusedOutput(t *testing.T) {
	for _, value := range []string{"up", "down", "1.6"} {
		t.Run(value, func(t *testing.T) {
			a, h := lidHarness(t)
			h.monitors = strings.Replace(dockJSON, `"id":0`, `"focused":true,"id":0`, 1)
			if code := a.run([]string{"scale", value}); code != 0 || len(h.evals) != 1 || !strings.Contains(h.evals[0], `output = "eDP-1"`) {
				t.Fatalf("scale: %d %v", code, h.evals)
			}
			want := "scale = 1.6"
			if value == "up" {
				want = "scale = 2"
			} else if value == "down" {
				want = "scale = 1.333333"
			}
			if !strings.Contains(h.evals[0], want) || len(h.dispatch) != 0 {
				t.Errorf("unexpected scale steps: %v %v", h.evals, h.dispatch)
			}
			saved, err := display.Load(a.store)
			if err != nil || len(saved.Profiles) != 1 || len(saved.Profiles[0].Monitors) != 2 || saved.Profiles[0].Monitors[1].Scale != 1 {
				t.Errorf("layout not saved or external scale changed: %+v %v", saved, err)
			}
		})
	}
}

func TestScaleErrorsDoNotChangeDisplays(t *testing.T) {
	for _, value := range []string{"NaN", "Inf", "0", "4.1", "bad"} {
		t.Run(value, func(t *testing.T) {
			a, h := lidHarness(t)
			h.monitors = strings.Replace(laptopJSON, `"id":0`, `"focused":true,"id":0`, 1)
			if code := a.run([]string{"scale", value}); code != 1 || len(h.evals) != 0 {
				t.Fatalf("invalid scale changed displays: %d %v", code, h.evals)
			}
		})
	}
}

func TestExternalScaleDoesNotPersistClosedLid(t *testing.T) {
	a, h := lidHarness(t)
	if code := a.run([]string{"lid", "closed"}); code != 0 {
		t.Fatal("close failed")
	}
	ms, err := display.ParseMonitors([]byte(dockJSON))
	if err != nil {
		t.Fatal(err)
	}
	ms[0].Disabled, ms[0].Width, ms[0].Height = true, 0, 0
	ms[1].Focused = true
	raw, err := json.Marshal(ms)
	if err != nil {
		t.Fatal(err)
	}
	h.monitors = string(raw)
	h.workspaces = strings.Replace(wsJSON, `"monitor":"eDP-1"`, `"monitor":"DP-3"`, 1)
	if code := a.run([]string{"scale", "1.6"}); code != 0 {
		t.Fatal("external scale failed")
	}
	saved, err := display.Load(a.store)
	if err != nil {
		t.Fatal(err)
	}
	panel := saved.Profiles[0].Monitors[0]
	if panel.Disabled || panel.Scale != 1.6 || panel.Mode != "3456x2160@60.001" {
		t.Errorf("closed lid became permanent: %+v", panel)
	}
	if got := saved.Profiles[0].Monitors[1].Workspaces; len(got) != 1 || got[0] != 1 {
		t.Errorf("panel workspace was also saved on the external display: %v", got)
	}
}
