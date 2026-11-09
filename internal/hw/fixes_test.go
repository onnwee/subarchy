package hw

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func fixtureRoot(t *testing.T, files map[string]string) string {
	t.Helper()
	root := t.TempDir()
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

func fixNames(fixes []Fix) []string {
	var out []string
	for _, f := range fixes {
		out = append(out, f.Name)
	}
	return out
}

func TestFixesPantherLakeLaptop(t *testing.T) {
	root := fixtureRoot(t, map[string]string{
		"proc/cpuinfo": "vendor_id\t: GenuineIntel\nmodel\t\t: 204\nflags\t\t: fpu\n",
		"sys/bus/pci/devices/0000:00:02.0/vendor": "0x8086\n", "sys/bus/pci/devices/0000:00:02.0/device": "0xb0a0\n", "sys/bus/pci/devices/0000:00:02.0/class": "0x030000\n",
		"sys/bus/pci/devices/0000:00:14.3/vendor": "0x8086\n", "sys/bus/pci/devices/0000:00:14.3/device": "0xe440\n", "sys/bus/pci/devices/0000:00:14.3/class": "0x028000\n",
		"sys/class/power_supply/BAT0/type":     "Battery\n",
		"sys/bus/acpi/devices/OVTI08F4:00/hid": "OVTI08F4\n",
		"sys/class/dmi/id/sys_vendor":          "Dell Inc.\n",
	})
	m, err := Detect(root)
	if err != nil {
		t.Fatal(err)
	}
	if m.Facts.CPUModel != 204 || !m.Facts.Battery || !m.hasACPI("OVTI08F4") {
		t.Fatalf("facts: %+v", m.Facts)
	}
	got := fixNames(Fixes(m))
	want := []string{"intel-wifi7-eht", "intel-fred", "intel-lpmd", "intel-video", "intel-ipu7-camera"}
	if m.Facts.Arch == "x86_64" {
		want = append(want, "hid-apple-fkeys")
	}
	if strings.Join(got, " ") != strings.Join(want, " ") {
		t.Errorf("fixes: %v, want %v", got, want)
	}
	sel := Select(m)
	for _, p := range []string{"intel-lpmd", "libvpl", "vpl-gpu-rt", "intel-ucode"} {
		if !contains(sel.Packages, p) {
			t.Errorf("packages lack %s: %v", p, sel.Packages)
		}
	}
	if contains(sel.Packages, "intel-ipu7-camera") {
		t.Error("a package that is not in Arch's repositories was selected")
	}
	if !contains(sel.Services, "intel_lpmd") {
		t.Errorf("services: %v", sel.Services)
	}
	target := t.TempDir()
	written, _, err := Apply(target, Fixes(m))
	if err != nil {
		t.Fatal(err)
	}
	for _, p := range []string{"etc/modprobe.d/iwlwifi-disable-eht.conf", "etc/limine-entry-tool.d/intel-panther-lake-fred.conf"} {
		if !contains(written, p) {
			t.Errorf("not written: %s (%v)", p, written)
		}
	}
	if b, _ := os.ReadFile(filepath.Join(target, "etc/limine-entry-tool.d/intel-panther-lake-fred.conf")); !strings.Contains(string(b), `KERNEL_CMDLINE[default]+=" fred=on"`) {
		t.Errorf("fred drop-in: %s", b)
	}
	if !NeedsInitramfs(written) {
		t.Error("modprobe and command line changes need an initramfs rebuild")
	}
	again, _, err := Apply(target, Fixes(m))
	if err != nil || len(again) != 0 {
		t.Errorf("second apply wrote %v (%v)", again, err)
	}
	// A file the user wrote is kept, and said so.
	own := filepath.Join(target, "etc/modprobe.d/iwlwifi-disable-eht.conf")
	os.WriteFile(own, []byte("options iwlwifi disable_11be=N\n"), 0o644)
	w, kept, err := Apply(target, Fixes(m))
	if err != nil || len(w) != 0 || !contains(kept, "etc/modprobe.d/iwlwifi-disable-eht.conf") {
		t.Errorf("a user file was not kept: wrote %v kept %v (%v)", w, kept, err)
	}
	if b, _ := os.ReadFile(own); string(b) != "options iwlwifi disable_11be=N\n" {
		t.Error("the user's file was overwritten")
	}
}

func TestFixesNvidiaDesktop(t *testing.T) {
	root := fixtureRoot(t, map[string]string{
		"proc/cpuinfo": "vendor_id\t: AuthenticAMD\nmodel\t\t: 97\n",
		"sys/bus/pci/devices/0000:01:00.0/vendor": "0x10de\n", "sys/bus/pci/devices/0000:01:00.0/device": "0x2684\n", "sys/bus/pci/devices/0000:01:00.0/class": "0x030000\n",
	})
	m, err := Detect(root)
	if err != nil {
		t.Fatal(err)
	}
	got := fixNames(Fixes(m))
	if !contains(got, "nvidia-modeset") || contains(got, "intel-video") || contains(got, "intel-lpmd") {
		t.Errorf("fixes: %v", got)
	}
	target := t.TempDir()
	written, _, _ := Apply(target, Fixes(m))
	if b, _ := os.ReadFile(filepath.Join(target, "etc/mkinitcpio.conf.d/nvidia.conf")); !strings.Contains(string(b), "MODULES+=(nvidia nvidia_modeset nvidia_uvm nvidia_drm)") {
		t.Errorf("nvidia initramfs modules: %s (written %v)", b, written)
	}
}

func TestFixesVM(t *testing.T) {
	root := fixtureRoot(t, map[string]string{
		"proc/cpuinfo":                            "vendor_id\t: GenuineIntel\nmodel\t\t: 85\nflags\t\t: fpu hypervisor\n",
		"sys/class/dmi/id/sys_vendor":             "QEMU\n",
		"sys/bus/pci/devices/0000:00:01.0/vendor": "0x1234\n", "sys/bus/pci/devices/0000:00:01.0/device": "0x1111\n", "sys/bus/pci/devices/0000:00:01.0/class": "0x030000\n",
	})
	m, err := Detect(root)
	if err != nil {
		t.Fatal(err)
	}
	got := fixNames(Fixes(m))
	want := []string{}
	if m.Facts.Arch == "x86_64" {
		want = append(want, "hid-apple-fkeys")
	}
	if strings.Join(got, " ") != strings.Join(want, " ") {
		t.Errorf("a VM gets only the keyboard fix: %v", got)
	}
	if !NeedsInitramfs([]string{"etc/modprobe.d/hid_apple.conf"}) || NeedsInitramfs([]string{"etc/conf.d/x"}) {
		t.Error("NeedsInitramfs")
	}
}

func TestCatalogueIsSound(t *testing.T) {
	seen := map[string]bool{}
	for _, f := range AllFixes() {
		if f.Name == "" || f.Summary == "" || !strings.HasPrefix(f.Source, "install/hardware/") || f.applies == nil {
			t.Errorf("incomplete fix: %+v", f)
		}
		if seen[f.Name] {
			t.Errorf("duplicate fix %s", f.Name)
		}
		seen[f.Name] = true
		if len(f.Packages) == 0 && len(f.Services) == 0 && len(f.Files) == 0 && f.Note == "" {
			t.Errorf("fix %s does nothing", f.Name)
		}
	}
	catalog := map[string]bool{}
	for _, p := range Catalog() {
		catalog[p] = true
	}
	for _, f := range AllFixes() {
		for _, p := range f.Packages {
			if !catalog[p] {
				t.Errorf("fix %s adds %s, which the package catalogue lacks", f.Name, p)
			}
		}
	}
}

func contains(list []string, s string) bool {
	for _, x := range list {
		if x == s {
			return true
		}
	}
	return false
}
