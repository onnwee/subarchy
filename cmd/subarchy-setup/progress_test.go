package main

import (
	"os"
	"strings"
	"testing"
)

// The install view reads subarchy-install's log: its step lines mark the
// phases and its die prefix marks the reason a run stopped. Renaming either
// in the script must fail here, not freeze the bar at the previous phase.
func TestProgressMarkersMatchInstaller(t *testing.T) {
	script, err := os.ReadFile("../../install/subarchy-install")
	if err != nil {
		t.Fatal(err)
	}
	for _, p := range phases {
		step := `step "` + strings.TrimPrefix(p.marker, ">> ")
		if !strings.Contains(string(script), step) {
			t.Errorf("subarchy-install has no %s", step)
		}
	}
	if die := `die() { echo "subarchy-install: error: `; !strings.Contains(string(script), die) {
		t.Errorf("subarchy-install has no %s", die)
	}
}
