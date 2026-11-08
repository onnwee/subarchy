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

func sysfs(t *testing.T) string {
	t.Helper()
	root := t.TempDir()
	files := map[string]string{
		"class/thermal/thermal_zone0/type":              "SKIN\n",
		"class/thermal/thermal_zone0/temp":              "48050\n",
		"class/thermal/thermal_zone0/trip_point_0_type": "passive\n",
		"class/thermal/thermal_zone0/trip_point_0_temp": "-274000\n",
		"class/thermal/thermal_zone0/trip_point_1_type": "hot\n",
		"class/thermal/thermal_zone0/trip_point_1_temp": "82050\n",
	}
	for p, c := range files {
		full := filepath.Join(root, p)
		if err := os.MkdirAll(filepath.Dir(full), 0o755); err != nil {
			t.Fatal(err)
		}
		if err := os.WriteFile(full, []byte(c), 0o644); err != nil {
			t.Fatal(err)
		}
	}
	return root
}

func TestZones(t *testing.T) {
	root := sysfs(t)
	var out, errOut bytes.Buffer
	if code := run([]string{"zones", "--root", root}, &out, &errOut); code != 0 {
		t.Fatalf("exit %d: %s", code, errOut.String())
	}
	text := out.String()
	if !strings.Contains(text, "zone 0  SKIN") || !strings.Contains(text, "trip 1  hot") || strings.Contains(text, "passive") {
		t.Errorf("table:\n%s", text)
	}
	out.Reset()
	if code := run([]string{"zones", "--json", "--root", root}, &out, &errOut); code != 0 {
		t.Fatalf("exit %d: %s", code, errOut.String())
	}
	var zones []map[string]any
	if err := json.Unmarshal(out.Bytes(), &zones); err != nil || len(zones) != 1 || zones[0]["type"] != "SKIN" {
		t.Errorf("json: %s %v", out.String(), err)
	}
	out.Reset()
	if code := run([]string{"zones", "--json", "--root", filepath.Join(root, "none")}, &out, &errOut); code != 0 || strings.TrimSpace(out.String()) != "[]" {
		t.Errorf("no sysfs: %d %q", code, out.String())
	}
}

func TestUsageAndMetadata(t *testing.T) {
	var out, errOut bytes.Buffer
	if code := run(nil, &out, &errOut); code != 2 || !strings.Contains(errOut.String(), "Usage") {
		t.Errorf("no args: %d %s", code, errOut.String())
	}
	errOut.Reset()
	if code := run([]string{"temps"}, &out, &errOut); code != 2 {
		t.Errorf("unknown: %d", code)
	}
	out.Reset()
	if code := run([]string{dispatch.MetadataFlag}, &out, &errOut); code != 0 {
		t.Fatalf("metadata: %d", code)
	}
	var described []dispatch.Described
	if err := json.Unmarshal(out.Bytes(), &described); err != nil || len(described) != 2 {
		t.Errorf("metadata: %s %v", out.String(), err)
	}
}

// Against the live kernel: the watch either has no family (exit 3) or
// returns 0 after the timeout with nothing happening.
func TestWatchLive(t *testing.T) {
	var out, errOut bytes.Buffer
	code := run([]string{"watch", "--timeout", "300ms"}, &out, &errOut)
	if code == 1 {
		t.Skipf("no netlink here: %s", errOut.String())
	}
	if code != 0 && code != exitNoFamily {
		t.Errorf("exit %d: %s", code, errOut.String())
	}
}
