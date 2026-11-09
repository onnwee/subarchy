package main

import (
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"strconv"
	"strings"

	"git.subcult.tv/subculture-collective/subarchy/internal/display"
)

func (a *app) scale(value string) int {
	ms, ws, err := a.live()
	if err != nil {
		return a.fail(err)
	}
	store, err := display.Load(a.store)
	if err != nil {
		return a.fail(err)
	}
	lid, err := display.Load(a.lidFile)
	if err != nil {
		return a.fail(err)
	}
	for i, m := range ms {
		if !m.Focused || m.Disabled {
			continue
		}
		var scale float64
		if value == "up" {
			scale, err = display.StepScale(m, 1)
		} else if value == "down" {
			scale, err = display.StepScale(m, -1)
		} else {
			scale, err = strconv.ParseFloat(value, 64)
			if err == nil {
				scale, err = display.CleanScale(m.Width, m.Height, scale)
			}
		}
		if err != nil {
			return a.fail(err)
		}
		p := display.Capture("scale", []display.Monitor{m}, nil)
		p.Monitors[0].Scale = scale
		if code := a.apply(p, ms, false); code != 0 {
			return code
		}
		profile, ok := store.Match(ms)
		if !ok {
			// A new monitor set gets its own profile; do not replace a layout
			// saved for another dock or force the user to name one per keypress.
			for n := 1; ; n++ {
				profile.Name = fmt.Sprintf("scaled-%d", n)
				exists := false
				for _, saved := range store.Profiles {
					exists = exists || saved.Name == profile.Name
				}
				if !exists {
					break
				}
			}
		}
		ms[i].Scale = scale
		profile = display.Capture(profile.Name, ms, ws)
		// A closed lid is temporary. Saving an external scale must not
		// turn it into a permanently disabled laptop panel in this profile.
		restored := map[string]bool{}
		panelWorkspaces := map[int]bool{}
		for i, m := range profile.Monitors {
			if !m.Disabled {
				continue
			}
			for _, snapshot := range lid.Profiles {
				for _, panel := range snapshot.Monitors {
					if panel.Description == m.Description {
						profile.Monitors[i] = panel
						restored[panel.Description] = true
						for _, w := range panel.Workspaces {
							panelWorkspaces[w] = true
						}
					}
				}
			}
		}
		for i, m := range profile.Monitors {
			if restored[m.Description] {
				continue
			}
			var keep []int
			for _, w := range m.Workspaces {
				if !panelWorkspaces[w] {
					keep = append(keep, w)
				}
			}
			profile.Monitors[i].Workspaces = keep
		}
		store.Upsert(profile)
		if err := display.Save(a.store, store); err != nil {
			return a.fail(fmt.Errorf("scale changed but could not save layout: %w", err))
		}
		return 0
	}
	return a.fail(fmt.Errorf("no focused display"))
}

// lid saves only panels it disables. The snapshot survives separate keybind
// invocations within this session, without changing the user's profiles.
func (a *app) lid(closed bool) int {
	ms, ws, err := a.live()
	if err != nil {
		return a.fail(err)
	}
	saved, err := display.Load(a.lidFile)
	if err != nil {
		return a.fail(err)
	}
	external := false
	var panels []display.Monitor
	for _, m := range ms {
		if !m.Disabled && m.Width > 0 && m.Height > 0 {
			if m.Internal() {
				panels = append(panels, m)
			} else if m.Name != "FALLBACK" {
				external = true
			}
		}
	}
	if closed && external {
		if len(saved.Profiles) == 0 && len(panels) > 0 {
			saved.Profiles = []display.Profile{display.Capture("laptop panel", panels, ws)}
			if err := display.Save(a.lidFile, saved); err != nil {
				return a.fail(err)
			}
		}
		// Repeated close/hotplug events must not overwrite the saved scale
		// with the disabled output's zero dimensions or emit a feedback loop.
		if len(panels) == 0 {
			return 0
		}
		p := display.Capture("closed lid", panels, nil)
		for i := range p.Monitors {
			p.Monitors[i].Disabled = true
		}
		return a.apply(p, ms, false)
	}
	// Opening, or unplugging the last external output while closed, restores
	// the saved mode, scale, position and workspaces before removing the cache.
	for _, p := range saved.Profiles {
		if _, missing := display.Plan(p, ms); len(missing) > 0 {
			// It may reappear in a later hotplug event; keep the snapshot.
			return 0
		}
		if code := a.apply(p, ms, false); code != 0 {
			return code
		}
	}
	if err := os.Remove(a.lidFile); err != nil && !errors.Is(err, os.ErrNotExist) {
		return a.fail(err)
	}
	return 0
}

func (a *app) syncLid() int {
	if a.lidClosed == nil {
		return 0
	}
	closed, err := a.lidClosed()
	if err != nil {
		return a.fail(err)
	}
	return a.lid(closed)
}

func lidClosed() (bool, error) {
	paths, err := filepath.Glob("/proc/acpi/button/lid/*/state")
	if err != nil {
		return false, err
	}
	for _, path := range paths {
		raw, err := os.ReadFile(path)
		if err != nil {
			return false, err
		}
		if strings.Contains(string(raw), "closed") {
			return true, nil
		}
	}
	return false, nil
}
