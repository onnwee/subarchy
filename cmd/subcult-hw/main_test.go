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

func machine(t *testing.T) string {
	t.Helper()
	root := t.TempDir()
	files := map[string]string{
		"proc/cpuinfo": "vendor_id\t: GenuineIntel\n",
		"sys/bus/pci/devices/0000:00:02.0/vendor": "0x8086\n",
		"sys/bus/pci/devices/0000:00:02.0/device": "0x46a6\n",
		"sys/bus/pci/devices/0000:00:02.0/class":  "0x030000\n",
		"sys/bus/pci/devices/0000:01:00.0/vendor": "0x10de\n",
		"sys/bus/pci/devices/0000:01:00.0/device": "0x25a0\n",
		"sys/bus/pci/devices/0000:01:00.0/class":  "0x030200\n",
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

func TestRun(t *testing.T) {
	root := machine(t)
	var out, errOut bytes.Buffer
	if code := run([]string{"packages", "--root", root}, &out, &errOut); code != 0 {
		t.Fatalf("exit %d: %s", code, errOut.String())
	}
	if !strings.Contains(out.String(), "nvidia-open-dkms\n") || !strings.Contains(errOut.String(), "hybrid graphics") {
		t.Errorf("packages: %q / %q", out.String(), errOut.String())
	}
	out.Reset()
	if code := run([]string{"info", "--root", root}, &out, &errOut); code != 0 || !strings.Contains(out.String(), "Hybrid:    true") ||
		!strings.Contains(out.String(), "display:   pci 10de:25a0") {
		t.Errorf("info: %d %q", code, out.String())
	}
	out.Reset()
	if code := run([]string{"info", "--json", "--root", root}, &out, &errOut); code != 0 {
		t.Fatalf("json exit %d", code)
	}
	var got map[string]any
	if err := json.Unmarshal(out.Bytes(), &got); err != nil || got["hybrid"] != true {
		t.Errorf("json %q: %v", out.String(), err)
	}
	out.Reset()
	if code := run([]string{dispatch.MetadataFlag}, &out, &errOut); code != 0 || !strings.Contains(out.String(), `"hw","packages"`) {
		t.Errorf("metadata %q", out.String())
	}
	for _, bad := range [][]string{nil, {"frob"}, {"info", "--bogus"}} {
		if code := run(bad, &out, &errOut); code != 2 {
			t.Errorf("%q: exit %d", bad, code)
		}
	}
	if code := run([]string{"packages", "--root", t.TempDir()}, &out, &errOut); code != 1 {
		t.Errorf("missing cpuinfo: exit %d", code)
	}
}
