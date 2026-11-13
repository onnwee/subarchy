package main

import (
	"bytes"
	"errors"
	"io"
	"path/filepath"
	"strings"
	"testing"
	"time"
)

const dockJSON = `[
 {"id":0,"name":"eDP-1","description":"Samsung Display Corp. 0x414D","width":3456,"height":2160,"refreshRate":60.001,"x":4480,"y":0,"scale":1.6,"transform":0,"disabled":false},
 {"id":1,"name":"DP-3","description":"LG Electronics 32GK650F 108NTBKDK213","width":2560,"height":1440,"refreshRate":143.972,"x":0,"y":0,"scale":1.0,"transform":0,"disabled":false}]`
const laptopJSON = `[{"id":0,"name":"eDP-1","description":"Samsung Display Corp. 0x414D","width":3456,"height":2160,"refreshRate":60.001,"x":0,"y":0,"scale":1.6,"transform":0,"disabled":false}]`
const wsJSON = `[{"id":1,"monitor":"DP-3"},{"id":2,"monitor":"eDP-1"}]`

type fakeHypr struct {
	monitors   string
	workspaces string
	evals      []string
	dispatch   []string
	failEvals  int // the next evaluations that fail
}

func (f *fakeHypr) Query(args ...string) ([]byte, error) {
	if args[0] == "monitors" {
		return []byte(f.monitors), nil
	}
	if f.workspaces != "" {
		return []byte(f.workspaces), nil
	}
	return []byte(wsJSON), nil
}
func (f *fakeHypr) Eval(lua string) error {
	if f.failEvals > 0 {
		f.failEvals--
		return errors.New("mode not offered")
	}
	f.evals = append(f.evals, lua)
	return nil
}
func (f *fakeHypr) Dispatch(lua string) error { f.dispatch = append(f.dispatch, lua); return nil }

func harness(t *testing.T) (*app, *fakeHypr, *bytes.Buffer, *bytes.Buffer) {
	t.Helper()
	h := &fakeHypr{monitors: dockJSON}
	out, errOut := &bytes.Buffer{}, &bytes.Buffer{}
	a := &app{stdout: out, stderr: errOut, store: filepath.Join(t.TempDir(), "profiles.json"), hypr: h, sleep: func(time.Duration) {}}
	return a, h, out, errOut
}

func TestSaveListApplyRemove(t *testing.T) {
	a, h, out, errOut := harness(t)
	if code := a.run([]string{"profile", "list"}); code != 0 || !strings.Contains(out.String(), "no profiles saved") {
		t.Fatalf("list empty: %d %q", code, out.String())
	}
	out.Reset()
	if code := a.run([]string{"profile", "save", "home-dock"}); code != 0 || !strings.Contains(out.String(), "saved home-dock: 2 monitors") {
		t.Fatalf("save: %d %q %q", code, out.String(), errOut.String())
	}
	out.Reset()
	if code := a.run([]string{"profile", "list"}); code != 0 || !strings.Contains(out.String(), "* home-dock") {
		t.Errorf("list marks the matching profile: %d %q", code, out.String())
	}
	out.Reset()
	if code := a.run([]string{"profile", "apply", "--dry-run"}); code != 0 || !strings.Contains(out.String(), `would eval: hl.monitor({ output = "DP-3"`) || !strings.Contains(out.String(), `would dispatch: hl.dsp.workspace.move({ workspace = "1", monitor = "DP-3" })`) {
		t.Errorf("dry run: %d %q", code, out.String())
	}
	if len(h.evals) != 0 {
		t.Error("a dry run changes nothing")
	}
	out.Reset()
	if code := a.run([]string{"profile", "apply", "home-dock"}); code != 0 || len(h.evals) != 2 || len(h.dispatch) != 2 || !strings.Contains(out.String(), "applied home-dock: 4 steps") {
		t.Errorf("apply: %d evals=%v dispatch=%v %q", code, h.evals, h.dispatch, out.String())
	}
	h.monitors = laptopJSON
	out.Reset()
	errOut.Reset()
	if code := a.run([]string{"profile", "apply"}); code != 1 || !strings.Contains(errOut.String(), "no saved profile matches") {
		t.Errorf("apply with no match: %d %q", code, errOut.String())
	}
	out.Reset()
	if code := a.run([]string{"profile", "remove", "home-dock"}); code != 0 || !strings.Contains(out.String(), "removed") {
		t.Errorf("remove: %d %q", code, out.String())
	}
	if code := a.run([]string{"profile", "remove", "home-dock"}); code != 1 {
		t.Errorf("remove twice: %d", code)
	}
	if code := a.run([]string{"profile", "frob"}); code != 2 {
		t.Errorf("usage: %d", code)
	}
}

func TestWatchAppliesOnMonitorEvents(t *testing.T) {
	a, h, out, _ := harness(t)
	a.run([]string{"profile", "save", "home-dock"})
	h.monitors = laptopJSON
	a.run([]string{"profile", "save", "laptop"})
	h.evals, h.dispatch = nil, nil
	// Events: a workspace change (ignored), then the dock arrives (two
	// quick events, one evaluation), then it goes.
	script := "workspace>>3\nmonitoradded>>DP-3\nmonitoraddedv2>>1,DP-3,LG\n"
	calls := 0
	a.events = func() (io.ReadCloser, error) { return io.NopCloser(strings.NewReader(script)), nil }
	a.sleep = func(time.Duration) {
		calls++
		h.monitors = dockJSON
	}
	out.Reset()
	if code := a.run([]string{"watch"}); code != 0 {
		t.Fatalf("watch: %d", code)
	}
	if calls != 2 {
		t.Errorf("debounce waited %d times, want 2 (one per monitor event)", calls)
	}
	if len(h.evals) != 3 || len(h.dispatch) != 3 {
		t.Errorf("the initial laptop profile and dock profile applied once each: evals=%v dispatch=%v", h.evals, h.dispatch)
	}
	if !strings.Contains(out.String(), "applied home-dock") {
		t.Errorf("out = %q", out.String())
	}
}

// A profile that fails to apply, at startup or after an event, is
// reported and the watcher goes on: an exit would restart the service into
// the same failure until systemd's start limit stops it.
func TestWatchSurvivesAFailedApply(t *testing.T) {
	a, h, out, errOut := harness(t)
	a.run([]string{"profile", "save", "home-dock"})
	h.monitors = laptopJSON
	a.run([]string{"profile", "save", "laptop"})
	h.evals, h.dispatch = nil, nil
	h.failEvals = 2 // the startup laptop profile, then the dock
	layouts := []string{dockJSON, laptopJSON}
	a.events = func() (io.ReadCloser, error) {
		return io.NopCloser(strings.NewReader("monitoradded>>DP-3\nmonitorremoved>>DP-3\n")), nil
	}
	a.sleep = func(time.Duration) { h.monitors, layouts = layouts[0], layouts[1:] }
	out.Reset()
	if code := a.run([]string{"watch"}); code != 0 {
		t.Fatalf("watch: %d; %s", code, errOut)
	}
	if strings.Count(errOut.String(), "mode not offered") != 2 {
		t.Errorf("both failures are reported: %q", errOut.String())
	}
	if !strings.Contains(out.String(), "applied laptop") {
		t.Errorf("the event after the failures is handled: %q", out.String())
	}
}

// A read error ends the watcher with a failure, so systemd restarts it.
func TestWatchFailsOnAReadError(t *testing.T) {
	a, _, _, errOut := harness(t)
	long := "windowtitlev2>>1," + strings.Repeat("x", 2<<20) + "\n"
	a.events = func() (io.ReadCloser, error) { return io.NopCloser(strings.NewReader(long)), nil }
	if code := a.run([]string{"watch"}); code != 1 || !strings.Contains(errOut.String(), "too long") {
		t.Errorf("watch: %d %q", code, errOut.String())
	}
}
