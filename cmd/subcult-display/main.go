// Command subcult-display serves `subcult display ...`: monitor layout
// profiles (rice port of the dock and monitor profiles). `display profile
// save <name>` records the connected monitors by description with their
// mode, position, scale, transform and workspaces; `display profile apply
// <name>` puts that layout back through Hyprland's Lua (`hyprctl eval` for
// monitor rules, `hyprctl dispatch` for workspace moves); `display watch`
// listens to Hyprland's monitor events and applies the profile for the
// connected set after a debounce. Profiles live in
// ~/.config/subcult/display/profiles.json.
package main

import (
	"bufio"
	"encoding/json"
	"fmt"
	"io"
	"net"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"time"

	"git.subcult.tv/subculture-collective/subarchy/internal/dispatch"
	"git.subcult.tv/subculture-collective/subarchy/internal/display"
)

var routes = []dispatch.Described{
	{Words: []string{"display", "profile", "save"}, Metadata: dispatch.Metadata{
		Summary: "Save the connected monitors' layout and workspaces under a name", Args: "<name>",
		Examples: []string{"subcult display profile save home-dock"}}},
	{Words: []string{"display", "profile", "list"}, Metadata: dispatch.Metadata{
		Summary:  "List the saved layouts and which one matches the connected monitors",
		Examples: []string{"subcult display profile list"}}},
	{Words: []string{"display", "profile", "apply"}, Metadata: dispatch.Metadata{
		Summary: "Apply a saved layout (the matching one when no name is given)", Args: "[<name>] [--dry-run]",
		Examples: []string{"subcult display profile apply home-dock", "subcult display profile apply --dry-run"}}},
	{Words: []string{"display", "profile", "remove"}, Metadata: dispatch.Metadata{
		Summary: "Forget a saved layout", Args: "<name>",
		Examples: []string{"subcult display profile remove home-dock"}}},
	{Words: []string{"display", "watch"}, Metadata: dispatch.Metadata{
		Summary: "Apply the matching layout whenever monitors come or go (the session service runs this)", Hidden: true}},
}

// Hypr runs hyprctl: queries, Lua evaluation and dispatches.
type Hypr interface {
	Query(args ...string) ([]byte, error)
	Eval(lua string) error
	Dispatch(lua string) error
}

type realHypr struct{}

func (realHypr) Query(args ...string) ([]byte, error) {
	return exec.Command("hyprctl", append(args, "-j")...).Output()
}

func (realHypr) Eval(lua string) error {
	return hyprctl("eval", lua)
}

func (realHypr) Dispatch(lua string) error {
	return hyprctl("dispatch", lua)
}

func hyprctl(args ...string) error {
	out, err := exec.Command("hyprctl", args...).CombinedOutput()
	s := strings.TrimSpace(string(out))
	if err != nil {
		return fmt.Errorf("hyprctl %s: %s", args[0], s)
	}
	if s != "ok" && s != "" {
		return fmt.Errorf("hyprctl %s: %s", args[0], s)
	}
	return nil
}

type app struct {
	stdout, stderr io.Writer
	store          string
	hypr           Hypr
	// events feeds "monitoradded>>…" lines to watch; nil means Hyprland's socket.
	events func() (io.ReadCloser, error)
	sleep  func(time.Duration)
}

func (a *app) live() ([]display.Monitor, []display.Workspace, error) {
	raw, err := a.hypr.Query("monitors", "all")
	if err != nil {
		return nil, nil, fmt.Errorf("hyprctl monitors: %w", err)
	}
	ms, err := display.ParseMonitors(raw)
	if err != nil {
		return nil, nil, err
	}
	raw, err = a.hypr.Query("workspaces")
	if err != nil {
		return nil, nil, fmt.Errorf("hyprctl workspaces: %w", err)
	}
	ws, err := display.ParseWorkspaces(raw)
	return ms, ws, err
}

func (a *app) run(args []string) int {
	if len(args) == 1 && args[0] == dispatch.MetadataFlag {
		if err := json.NewEncoder(a.stdout).Encode(routes); err != nil {
			return 1
		}
		return 0
	}
	if len(args) == 0 {
		return a.usage()
	}
	store, err := display.Load(a.store)
	if err != nil {
		return a.fail(err)
	}
	switch {
	case args[0] == "watch":
		return a.watch(store)
	case args[0] == "profile" && len(args) >= 2:
		rest := args[2:]
		dryRun := false
		var names []string
		for _, r := range rest {
			if r == "--dry-run" || r == "-n" {
				dryRun = true
			} else {
				names = append(names, r)
			}
		}
		switch args[1] {
		case "save":
			if len(names) != 1 {
				return a.usage()
			}
			ms, ws, err := a.live()
			if err != nil {
				return a.fail(err)
			}
			p := display.Capture(names[0], ms, ws)
			store.Upsert(p)
			if err := display.Save(a.store, store); err != nil {
				return a.fail(err)
			}
			fmt.Fprintf(a.stdout, "saved %s: %d monitors (%s)\n", p.Name, len(p.Monitors), strings.Join(p.Identity, "; "))
			return 0
		case "list":
			ms, _, err := a.live()
			current := ""
			if err == nil {
				if p, ok := store.Match(ms); ok {
					current = p.Name
				}
			}
			if len(store.Profiles) == 0 {
				fmt.Fprintln(a.stdout, "no profiles saved; arrange the monitors, then: subcult display profile save <name>")
				return 0
			}
			for _, p := range store.Profiles {
				mark := " "
				if p.Name == current {
					mark = "*"
				}
				fmt.Fprintf(a.stdout, "%s %-16s %d monitors: %s\n", mark, p.Name, len(p.Monitors), strings.Join(p.Identity, "; "))
			}
			return 0
		case "apply":
			ms, _, err := a.live()
			if err != nil {
				return a.fail(err)
			}
			var p display.Profile
			if len(names) == 1 {
				found := false
				for _, q := range store.Profiles {
					if q.Name == names[0] {
						p, found = q, true
					}
				}
				if !found {
					return a.fail(fmt.Errorf("no profile %q", names[0]))
				}
			} else {
				q, ok := store.Match(ms)
				if !ok {
					return a.fail(fmt.Errorf("no saved profile matches the connected monitors (%s)", strings.Join(display.Identity(ms), "; ")))
				}
				p = q
			}
			return a.apply(p, ms, dryRun)
		case "remove":
			if len(names) != 1 {
				return a.usage()
			}
			if !store.Remove(names[0]) {
				return a.fail(fmt.Errorf("no profile %q", names[0]))
			}
			if err := display.Save(a.store, store); err != nil {
				return a.fail(err)
			}
			fmt.Fprintf(a.stdout, "removed %s\n", names[0])
			return 0
		}
	}
	return a.usage()
}

func (a *app) apply(p display.Profile, ms []display.Monitor, dryRun bool) int {
	steps, missing := display.Plan(p, ms)
	for _, m := range missing {
		fmt.Fprintf(a.stderr, "subcult display: %s: %q is not connected; skipped\n", p.Name, m)
	}
	for _, s := range steps {
		if dryRun {
			fmt.Fprintf(a.stdout, "would %s: %s\n", s.Kind, s.Lua)
			continue
		}
		var err error
		if s.Kind == "eval" {
			err = a.hypr.Eval(s.Lua)
		} else {
			err = a.hypr.Dispatch(s.Lua)
		}
		if err != nil {
			return a.fail(err)
		}
	}
	if !dryRun {
		fmt.Fprintf(a.stdout, "applied %s: %d steps\n", p.Name, len(steps))
	}
	return 0
}

// watch applies the matching profile after monitor events settle. Nothing
// polls: the goroutine blocks on Hyprland's event socket, and the only
// timer is the debounce after an event.
func (a *app) watch(store display.Store) int {
	open := a.events
	if open == nil {
		open = hyprlandEvents
	}
	conn, err := open()
	if err != nil {
		return a.fail(err)
	}
	defer conn.Close()
	debounce := time.Duration(store.Debounce) * time.Millisecond
	if debounce <= 0 {
		debounce = display.DefaultDebounceMs * time.Millisecond
	}
	var last []string
	sc := bufio.NewScanner(conn)
	for sc.Scan() {
		if !display.MonitorEvent(sc.Text()) {
			continue
		}
		a.sleep(debounce)
		// Later events during the wait are already in the buffer; the
		// layout is read once, after them.
		ms, _, err := a.live()
		if err != nil {
			fmt.Fprintf(a.stderr, "subcult display: %v\n", err)
			continue
		}
		id := display.Identity(ms)
		if len(last) == len(id) && strings.Join(last, "\x00") == strings.Join(id, "\x00") {
			continue
		}
		last = id
		store, err = display.Load(a.store) // the user may have saved a profile meanwhile
		if err != nil {
			fmt.Fprintf(a.stderr, "subcult display: %v\n", err)
			continue
		}
		p, ok := store.Match(ms)
		if !ok {
			fmt.Fprintf(a.stdout, "monitors changed (%s): no saved profile, left as is\n", strings.Join(id, "; "))
			continue
		}
		a.apply(p, ms, false)
	}
	return 0
}

// hyprlandEvents opens Hyprland's event socket for this session.
func hyprlandEvents() (io.ReadCloser, error) {
	sig := os.Getenv("HYPRLAND_INSTANCE_SIGNATURE")
	runtime := os.Getenv("XDG_RUNTIME_DIR")
	if sig == "" || runtime == "" {
		return nil, fmt.Errorf("not inside a Hyprland session (HYPRLAND_INSTANCE_SIGNATURE and XDG_RUNTIME_DIR needed)")
	}
	return net.Dial("unix", filepath.Join(runtime, "hypr", sig, ".socket2.sock"))
}

func (a *app) usage() int {
	fmt.Fprintln(a.stderr, "Usage: subcult display profile save <name> | list | apply [<name>] [--dry-run] | remove <name>")
	return 2
}

func (a *app) fail(err error) int {
	fmt.Fprintf(a.stderr, "subcult display: %v\n", err)
	return 1
}

func main() {
	config, err := os.UserConfigDir()
	if err != nil {
		fmt.Fprintln(os.Stderr, "subcult display:", err)
		os.Exit(1)
	}
	a := &app{stdout: os.Stdout, stderr: os.Stderr, store: filepath.Join(config, "subcult", "display", "profiles.json"), hypr: realHypr{}, sleep: time.Sleep}
	os.Exit(a.run(os.Args[1:]))
}
