package main

import (
	"bytes"
	"encoding/json"
	"os"
	"path/filepath"
	"strings"
	"testing"

	"git.subcult.tv/subculture-collective/subarchy/internal/dispatch"
)

func newApp(t *testing.T) (*app, *bytes.Buffer, *[]string, *int) {
	t.Helper()
	var out bytes.Buffer
	var execd []string
	restarts := 0
	dir := t.TempDir()
	a := &app{stdout: &out, stderr: &out, settingsPath: filepath.Join(dir, "idle.json"), runtimeDir: filepath.Join(dir, "run"),
		exec: func(argv []string) error { execd = argv; return nil }, restart: func() error { restarts++; return nil }}
	return a, &out, &execd, &restarts
}

func TestShowConfigApplyRun(t *testing.T) {
	a, out, execd, restarts := newApp(t)
	if err := os.WriteFile(a.settingsPath, []byte(`{"lockAfterMinutes": 4, "suspendAfterMinutes": 0}`), 0o644); err != nil {
		t.Fatal(err)
	}
	if code := a.run(nil); code != 0 || strings.TrimSpace(out.String()) != "lock after 4 min, display off after 10 min, suspend never" {
		t.Fatalf("show: %d %q", code, out.String())
	}
	out.Reset()
	if code := a.run([]string{"config"}); code != 0 || !strings.Contains(out.String(), "timeout = 240") || strings.Contains(out.String(), "systemctl suspend") {
		t.Errorf("config: %d\n%s", code, out.String())
	}
	out.Reset()
	if code := a.run([]string{"apply"}); code != 0 || *restarts != 1 {
		t.Errorf("apply: %d restarts %d", code, *restarts)
	}
	if code := a.run([]string{"run"}); code != 0 || len(*execd) != 3 || (*execd)[0] != "hypridle" {
		t.Fatalf("run: %d %v", code, *execd)
	}
	conf, err := os.ReadFile((*execd)[2])
	if err != nil || !strings.Contains(string(conf), "lock_cmd = systemctl --user start subcult-lock.service") {
		t.Errorf("written config: %v\n%s", err, conf)
	}
	if code := a.run([]string{"dance"}); code != 2 {
		t.Errorf("unknown: %d", code)
	}
}

func TestBrokenSettingsUseDefaults(t *testing.T) {
	a, out, _, _ := newApp(t)
	os.WriteFile(a.settingsPath, []byte("{ no"), 0o644)
	if code := a.run(nil); code != 0 || !strings.Contains(out.String(), "using the defaults") || !strings.Contains(out.String(), "lock after 7 min") {
		t.Errorf("broken: %d %q", code, out.String())
	}
}

func TestMetadata(t *testing.T) {
	a, out, _, _ := newApp(t)
	if code := a.run([]string{dispatch.MetadataFlag}); code != 0 {
		t.Fatal(code)
	}
	var d []dispatch.Described
	if err := json.Unmarshal(out.Bytes(), &d); err != nil || len(d) != 4 {
		t.Errorf("metadata: %v %s", err, out.String())
	}
}
