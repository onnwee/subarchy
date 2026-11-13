// Package display saves and applies monitor layouts (rice port: dock and
// monitor profiles). A profile records the connected monitors by their
// description (make, model, serial) and which workspaces live on each. The
// connector is kept only to tell identical monitors apart.
// `subcult display watch` reacts to Hyprland's monitor events (no polling)
// and applies the profile for the connected set after a short debounce;
// `subcult display profile apply` does it by hand. Changes go through
// `hyprctl eval` (monitor rules) and `hyprctl dispatch` (workspace moves),
// the same Lua Hyprland's config uses.
package display

import (
	"encoding/json"
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"sort"
	"strconv"
	"strings"

	"git.subcult.tv/subculture-collective/subarchy/internal/atomicfile"
)

// Monitor is what `hyprctl monitors all -j` reports, the parts kept.
type Monitor struct {
	Name        string  `json:"name"`
	Description string  `json:"description"`
	Width       int     `json:"width"`
	Height      int     `json:"height"`
	RefreshRate float64 `json:"refreshRate"`
	X           int     `json:"x"`
	Y           int     `json:"y"`
	Scale       float64 `json:"scale"`
	Transform   int     `json:"transform"`
	Disabled    bool    `json:"disabled"`
	Focused     bool    `json:"focused"`
}

// Internal reports a laptop panel.
func (m Monitor) Internal() bool {
	return strings.HasPrefix(m.Name, "eDP-") || strings.HasPrefix(m.Name, "LVDS-") || strings.HasPrefix(m.Name, "DSI-")
}

// Workspace is what `hyprctl workspaces -j` reports, the parts kept.
type Workspace struct {
	ID      int    `json:"id"`
	Monitor string `json:"monitor"`
}

// ParseMonitors reads `hyprctl monitors all -j`.
func ParseMonitors(raw []byte) ([]Monitor, error) {
	var ms []Monitor
	if err := json.Unmarshal(raw, &ms); err != nil {
		return nil, fmt.Errorf("monitors: %w", err)
	}
	return ms, nil
}

// ParseWorkspaces reads `hyprctl workspaces -j`, numbered workspaces only.
func ParseWorkspaces(raw []byte) ([]Workspace, error) {
	var ws []Workspace
	if err := json.Unmarshal(raw, &ws); err != nil {
		return nil, fmt.Errorf("workspaces: %w", err)
	}
	var out []Workspace
	for _, w := range ws {
		if w.ID > 0 {
			out = append(out, w)
		}
	}
	return out, nil
}

// Identity is the connected set: the monitors' descriptions, sorted, with
// duplicates kept (two identical monitors are two entries). Connector
// names are not part of it, so a monitor that moves between dock ports
// keeps its profile.
func Identity(monitors []Monitor) []string {
	var id []string
	for _, m := range monitors {
		if m.Description != "" {
			id = append(id, m.Description)
		}
	}
	sort.Strings(id)
	return id
}

func sameIdentity(a, b []string) bool {
	if len(a) != len(b) {
		return false
	}
	for i := range a {
		if a[i] != b[i] {
			return false
		}
	}
	return true
}

// ProfileMonitor is one monitor's saved layout.
type ProfileMonitor struct {
	Description string  `json:"description"`
	Connector   string  `json:"connector,omitempty"` // tells identical monitors apart
	Mode        string  `json:"mode"`                // "2560x1440@144"
	Position    string  `json:"position"`
	Scale       float64 `json:"scale"`
	Transform   int     `json:"transform"`
	Disabled    bool    `json:"disabled"`
	Workspaces  []int   `json:"workspaces"`
}

// Profile is one saved layout for one connected set.
type Profile struct {
	Name     string           `json:"name"`
	Identity []string         `json:"identity"`
	Monitors []ProfileMonitor `json:"monitors"`
}

// Store is ~/.config/subcult/display/profiles.json.
type Store struct {
	Schema   int       `json:"schema"`
	Debounce int       `json:"debounceMs,omitempty"`
	Profiles []Profile `json:"profiles"`
}

// Load reads the store; a missing file is empty.
func Load(path string) (Store, error) {
	var s Store
	raw, err := os.ReadFile(path)
	if errors.Is(err, os.ErrNotExist) {
		return Store{Schema: 1}, nil
	}
	if err != nil {
		return s, err
	}
	if err := json.Unmarshal(raw, &s); err != nil {
		return s, fmt.Errorf("%s: %w", path, err)
	}
	if s.Schema != 1 {
		return s, fmt.Errorf("%s: schema must be 1", path)
	}
	return s, nil
}

// Save writes the store atomically, private to the user.
func Save(path string, s Store) error {
	s.Schema = 1
	raw, err := json.MarshalIndent(s, "", "  ")
	if err != nil {
		return err
	}
	if err := os.MkdirAll(filepath.Dir(path), 0o700); err != nil {
		return err
	}
	return atomicfile.Write(path, append(raw, '\n'), 0o600)
}

// Capture makes a profile from the live monitors and workspaces.
func Capture(name string, monitors []Monitor, workspaces []Workspace) Profile {
	p := Profile{Name: name, Identity: Identity(monitors)}
	for _, m := range monitors {
		if m.Description == "" {
			continue
		}
		pm := ProfileMonitor{
			Description: m.Description,
			Connector:   m.Name,
			Mode:        fmt.Sprintf("%dx%d@%s", m.Width, m.Height, trimFloat(m.RefreshRate)),
			Position:    fmt.Sprintf("%dx%d", m.X, m.Y),
			Scale:       m.Scale,
			Transform:   m.Transform,
			Disabled:    m.Disabled,
		}
		for _, w := range workspaces {
			if w.Monitor == m.Name {
				pm.Workspaces = append(pm.Workspaces, w.ID)
			}
		}
		sort.Ints(pm.Workspaces)
		p.Monitors = append(p.Monitors, pm)
	}
	return p
}

func trimFloat(f float64) string {
	s := fmt.Sprintf("%.3f", f)
	s = strings.TrimRight(strings.TrimRight(s, "0"), ".")
	return s
}

// Match finds the profile for the connected set.
func (s Store) Match(monitors []Monitor) (Profile, bool) {
	id := Identity(monitors)
	for _, p := range s.Profiles {
		if sameIdentity(p.Identity, id) {
			return p, true
		}
	}
	return Profile{}, false
}

// Upsert replaces a profile of the same name, or adds it.
func (s *Store) Upsert(p Profile) {
	for i, q := range s.Profiles {
		if q.Name == p.Name {
			s.Profiles[i] = p
			return
		}
	}
	s.Profiles = append(s.Profiles, p)
}

// Remove drops a profile by name.
func (s *Store) Remove(name string) bool {
	for i, q := range s.Profiles {
		if q.Name == name {
			s.Profiles = append(s.Profiles[:i], s.Profiles[i+1:]...)
			return true
		}
	}
	return false
}

// Step is one change to make: a Lua expression for `hyprctl eval`
// (monitor rules) or `hyprctl dispatch` (workspace moves).
type Step struct {
	Kind string // "eval" or "dispatch"
	Lua  string
}

// Plan maps the profile's monitors onto the connected ones by description
// and returns the steps: monitor rules first, then the workspace moves.
// Identical monitors go to the connector each was saved on when it is
// connected, the rest in connector-name order. A profile monitor that is
// not connected is skipped and named in the returned list.
func Plan(p Profile, monitors []Monitor) ([]Step, []string) {
	byDesc := map[string][]Monitor{}
	for _, m := range monitors {
		byDesc[m.Description] = append(byDesc[m.Description], m)
	}
	for d := range byDesc {
		sort.Slice(byDesc[d], func(i, j int) bool { return byDesc[d][i].Name < byDesc[d][j].Name })
	}
	// Saved connectors first, so a fallback pick cannot take a monitor a
	// later profile entry was saved on.
	used := map[string]bool{} // by connector
	picked := make([]*Monitor, len(p.Monitors))
	for i, pm := range p.Monitors {
		for j, m := range byDesc[pm.Description] {
			if pm.Connector != "" && m.Name == pm.Connector && !used[m.Name] {
				picked[i], used[m.Name] = &byDesc[pm.Description][j], true
				break
			}
		}
	}
	for i, pm := range p.Monitors {
		if picked[i] != nil {
			continue
		}
		for j, m := range byDesc[pm.Description] {
			if !used[m.Name] {
				picked[i], used[m.Name] = &byDesc[pm.Description][j], true
				break
			}
		}
	}
	var steps []Step
	var missing []string
	var moves []Step
	for i, pm := range p.Monitors {
		if picked[i] == nil {
			missing = append(missing, pm.Description)
			continue
		}
		m := *picked[i]
		if pm.Disabled {
			steps = append(steps, Step{"eval", fmt.Sprintf(`hl.monitor({ output = %s, disabled = true })`, luaString(m.Name))})
			continue
		}
		steps = append(steps, Step{"eval", fmt.Sprintf(`hl.monitor({ output = %s, disabled = false, mode = %s, position = %s, scale = %s, transform = %d, mirror = "" })`,
			luaString(m.Name), luaString(pm.Mode), luaString(pm.Position), strconv.FormatFloat(pm.Scale, 'f', -1, 64), pm.Transform)})
		for _, w := range pm.Workspaces {
			moves = append(moves, Step{"dispatch", fmt.Sprintf(`hl.dsp.workspace.move({ workspace = "%d", monitor = %s })`, w, luaString(m.Name))})
		}
	}
	return append(steps, moves...), missing
}

// luaString quotes a value for Lua; names and descriptions come from
// Hyprland and are quoted so nothing in them reaches the interpreter.
func luaString(s string) string {
	return `"` + strings.NewReplacer(`\`, `\\`, `"`, `\"`, "\n", `\n`, "\r", ``).Replace(s) + `"`
}

// DefaultDebounceMs is how long the watcher waits after a monitor event, in milliseconds.
const DefaultDebounceMs = 1500

// MonitorEvent reports whether a Hyprland event line changes the monitor
// set ("monitoradded>>DP-3", "monitorremoved>>DP-3", the v2 forms).
func MonitorEvent(line string) bool {
	name, _, _ := strings.Cut(line, ">>")
	switch name {
	case "monitoradded", "monitoraddedv2", "monitorremoved", "monitorremovedv2":
		return true
	}
	return false
}
