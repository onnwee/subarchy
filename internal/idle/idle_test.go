package idle

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func TestLoad(t *testing.T) {
	dir := t.TempDir()
	if s, err := Load(filepath.Join(dir, "none.json")); err != nil || s != Defaults() {
		t.Errorf("missing: %+v %v", s, err)
	}
	p := filepath.Join(dir, "idle.json")
	os.WriteFile(p, []byte(`{"lockAfterMinutes": 5}`), 0o644)
	s, err := Load(p)
	if err != nil || s.LockAfterMinutes != 5 || s.DisplayOffAfterMinutes != 10 {
		t.Errorf("partial: %+v %v", s, err)
	}
	os.WriteFile(p, []byte(`{ broken`), 0o644)
	if _, err := Load(p); err == nil {
		t.Error("broken file passed")
	}
	os.WriteFile(p, []byte(`{"suspendAfterMinutes": -1}`), 0o644)
	if _, err := Load(p); err == nil {
		t.Error("negative minutes passed")
	}
}

func TestRender(t *testing.T) {
	out := Render(Defaults())
	for _, want := range []string{"lock_cmd = systemctl --user start subcult-lock.service", "inhibit_sleep = 3", "timeout = 420", "timeout = 600", "timeout = 900",
		"on-timeout = loginctl lock-session", `hl.dsp.dpms({ action = "off" })`, "on-timeout = systemctl suspend"} {
		if !strings.Contains(out, want) {
			t.Errorf("render lacks %q:\n%s", want, out)
		}
	}
	off := Render(Settings{LockAfterMinutes: 3})
	if strings.Count(off, "listener {") != 1 || strings.Contains(off, "suspend") && strings.Contains(off, "timeout = 0") {
		t.Errorf("zero disables a step:\n%s", off)
	}
	if Summary(Settings{LockAfterMinutes: 3}) != "lock after 3 min, display off never, suspend never" {
		t.Errorf("summary: %q", Summary(Settings{LockAfterMinutes: 3}))
	}
}

func TestDPMSCommandsSetExplicitState(t *testing.T) {
	// Lua DPMS reads action; an unrecognized field defaults to toggle.
	// This must remain correct even with the idle display timer disabled:
	// after_sleep_cmd runs when the compositor may already have woken outputs.
	for _, settings := range []Settings{Defaults(), {}} {
		out := Render(settings)
		if !strings.Contains(out, `after_sleep_cmd = hyprctl dispatch 'hl.dsp.dpms({ action = "on" })'`) {
			t.Errorf("resume must explicitly power on outputs:\n%s", out)
		}
		if strings.Contains(out, "mode =") {
			t.Errorf("unsupported DPMS mode defaults to toggle:\n%s", out)
		}
	}
}
