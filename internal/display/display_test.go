package display

import (
	"path/filepath"
	"strconv"
	"strings"
	"testing"
)

const monitorsJSON = `[
 {"id":0,"name":"eDP-1","description":"Samsung Display Corp. 0x414D","width":3456,"height":2160,"refreshRate":60.001,"x":4480,"y":0,"scale":1.6,"transform":0,"disabled":false},
 {"id":1,"name":"DP-3","description":"LG Electronics 32GK650F 108NTBKDK213","width":2560,"height":1440,"refreshRate":143.972,"x":0,"y":0,"scale":1.0,"transform":0,"disabled":false},
 {"id":2,"name":"DP-2","description":"ONN 100002487","width":1920,"height":1080,"refreshRate":60.0,"x":2560,"y":0,"scale":1.0,"transform":0,"disabled":false},
 {"id":3,"name":"DVI-I-1","description":"ONN 100002487","width":1920,"height":1080,"refreshRate":60.0,"x":-1080,"y":0,"scale":1.0,"transform":1,"disabled":false}
]`

const workspacesJSON = `[{"id":1,"monitor":"DP-3"},{"id":2,"monitor":"DP-3"},{"id":5,"monitor":"DVI-I-1"},{"id":8,"monitor":"DP-2"},{"id":-98,"monitor":"DP-3"}]`

func dock(t *testing.T) ([]Monitor, []Workspace) {
	t.Helper()
	ms, err := ParseMonitors([]byte(monitorsJSON))
	if err != nil {
		t.Fatal(err)
	}
	ws, err := ParseWorkspaces([]byte(workspacesJSON))
	if err != nil {
		t.Fatal(err)
	}
	return ms, ws
}

func TestIdentityIgnoresConnectors(t *testing.T) {
	ms, _ := dock(t)
	id := Identity(ms)
	want := []string{"LG Electronics 32GK650F 108NTBKDK213", "ONN 100002487", "ONN 100002487", "Samsung Display Corp. 0x414D"}
	if strings.Join(id, "|") != strings.Join(want, "|") {
		t.Errorf("identity = %v", id)
	}
	ms[1].Name, ms[2].Name = ms[2].Name, ms[1].Name // the dock swapped connectors
	if !sameIdentity(Identity(ms), want) {
		t.Error("connector names do not change the identity")
	}
	if sameIdentity(Identity(ms[:2]), want) {
		t.Error("fewer monitors is another identity")
	}
}

func TestCaptureAndPlan(t *testing.T) {
	ms, ws := dock(t)
	p := Capture("home-dock", ms, ws)
	if len(p.Monitors) != 4 || p.Monitors[1].Mode != "2560x1440@143.972" || p.Monitors[0].Position != "4480x0" || p.Monitors[3].Transform != 1 {
		t.Errorf("capture: %+v", p.Monitors)
	}
	if strings.Join(intsToStr(p.Monitors[1].Workspaces), ",") != "1,2" || strings.Join(intsToStr(p.Monitors[3].Workspaces), ",") != "5" {
		t.Errorf("workspaces: %+v", p.Monitors)
	}
	// Dock re-enumerated: the LG and the landscape ONN swapped connectors.
	ms[1].Name, ms[2].Name = "DP-2", "DP-3"
	steps, missing := Plan(p, ms)
	if len(missing) != 0 {
		t.Errorf("missing %v", missing)
	}
	var evals, moves []string
	for _, s := range steps {
		if s.Kind == "eval" {
			evals = append(evals, s.Lua)
		} else {
			moves = append(moves, s.Lua)
		}
	}
	if len(evals) != 4 || len(moves) != 4 {
		t.Fatalf("steps = %+v", steps)
	}
	if !strings.Contains(evals[1], `output = "DP-2"`) || !strings.Contains(evals[1], `mode = "2560x1440@143.972"`) || !strings.Contains(evals[1], `position = "0x0"`) {
		t.Errorf("the LG follows its description to DP-2: %s", evals[1])
	}
	if !strings.Contains(moves[0], `workspace = "1", monitor = "DP-2"`) {
		t.Errorf("workspace 1 goes with the LG: %s", moves[0])
	}
	// The two ONNs share a description: the first saved (DP-2, landscape)
	// maps to the first connected by name (now DP-3), the second to DVI-I-1.
	if !strings.Contains(evals[2], `output = "DP-3"`) || !strings.Contains(evals[2], `transform = 0`) || !strings.Contains(evals[3], `output = "DVI-I-1"`) || !strings.Contains(evals[3], `transform = 1`) {
		t.Errorf("identical monitors map in name order: %s | %s", evals[2], evals[3])
	}
	if !strings.Contains(evals[0], `output = "eDP-1"`) || !strings.Contains(evals[0], `scale = 1.6`) {
		t.Errorf("panel: %s", evals[0])
	}
}

func TestPlanMissingAndDisabled(t *testing.T) {
	ms, ws := dock(t)
	p := Capture("home-dock", ms, ws)
	p.Monitors[0].Disabled = true // clamshell: the panel off
	steps, missing := Plan(p, ms[:3])
	if len(missing) != 1 || missing[0] != "ONN 100002487" {
		t.Errorf("one ONN unplugged: missing = %v", missing)
	}
	if steps[0].Lua != `hl.monitor({ output = "eDP-1", disabled = true })` {
		t.Errorf("disabled rule: %s", steps[0].Lua)
	}
}

func TestStoreMatchUpsertRemove(t *testing.T) {
	ms, ws := dock(t)
	path := filepath.Join(t.TempDir(), "display", "profiles.json")
	s, err := Load(path)
	if err != nil || s.Schema != 1 || len(s.Profiles) != 0 {
		t.Fatalf("empty store: %+v, %v", s, err)
	}
	s.Upsert(Capture("home-dock", ms, ws))
	s.Upsert(Capture("laptop", ms[:1], nil))
	s.Upsert(Capture("home-dock", ms, ws)) // replaces, not duplicates
	if len(s.Profiles) != 2 {
		t.Errorf("upsert: %d profiles", len(s.Profiles))
	}
	if err := Save(path, s); err != nil {
		t.Fatal(err)
	}
	back, err := Load(path)
	if err != nil || len(back.Profiles) != 2 {
		t.Fatalf("round trip: %+v, %v", back, err)
	}
	if p, ok := back.Match(ms); !ok || p.Name != "home-dock" {
		t.Errorf("match dock: %+v %v", p, ok)
	}
	if p, ok := back.Match(ms[:1]); !ok || p.Name != "laptop" {
		t.Errorf("match laptop: %+v %v", p, ok)
	}
	if _, ok := back.Match(ms[:2]); ok {
		t.Error("an unknown set matches nothing")
	}
	if !back.Remove("laptop") || back.Remove("laptop") || len(back.Profiles) != 1 {
		t.Error("remove")
	}
}

func TestLuaStringAndEvents(t *testing.T) {
	if got := luaString(`A "quoted" \ name`); got != `"A \"quoted\" \\ name"` {
		t.Errorf("luaString = %s", got)
	}
	for line, want := range map[string]bool{"monitoradded>>DP-3": true, "monitoraddedv2>>1,DP-3,LG": true, "monitorremoved>>DP-3": true, "workspace>>3": false, "focusedmon>>DP-3,1": false} {
		if MonitorEvent(line) != want {
			t.Errorf("%s: %v", line, !want)
		}
	}
}

func intsToStr(a []int) []string {
	out := make([]string, len(a))
	for i, v := range a {
		out[i] = strconv.Itoa(v)
	}
	return out
}
