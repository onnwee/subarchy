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
	written, err := Apply(target, Fixes(m))
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
	again, err := Apply(target, Fixes(m))
	if err != nil || len(again) != 0 {
		t.Errorf("second apply wrote %v (%v)", again, err)
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
	written, _ := Apply(target, Fixes(m))
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

func TestFixesPeripherals(t *testing.T) {
	root := fixtureRoot(t, map[string]string{
		"proc/cpuinfo": "vendor_id\t: GenuineIntel\nmodel\t\t: 94\n",
		"sys/bus/pci/devices/0000:02:00.0/vendor": "0x14e4\n", "sys/bus/pci/devices/0000:02:00.0/device": "0x43a0\n", "sys/bus/pci/devices/0000:02:00.0/class": "0x028000\n",
		"sys/bus/usb/devices/1-2/idVendor": "0fd9\n", "sys/bus/usb/devices/1-2/idProduct": "0066\n", "sys/bus/usb/devices/1-2/product": "Cam Link 4K\n",
		"sys/class/input/event5/device/name": "Synaptics TM3276-022\n",
		"run/udev/data/c13:69":               "E:ID_INPUT_TOUCHPAD=1\n",
	})
	m, err := Detect(root)
	if err != nil {
		t.Fatal(err)
	}
	got := fixNames(Fixes(m))
	for _, want := range []string{"broadcom-wl", "elgato-camlink-4k"} {
		if !contains(got, want) {
			t.Errorf("fixes lack %s: %v (usb %v)", want, got, m.Facts.USBProducts)
		}
	}
	if strings.Contains(strings.ToLower(m.Facts.Touchpad), "synaptics") && !contains(got, "synaptics-intertouch") {
		t.Errorf("synaptics touchpad %q without the fix: %v", m.Facts.Touchpad, got)
	}
	sel := Select(m)
	for _, p := range []string{"broadcom-wl-dkms", "v4l2loopback-dkms", "linux-zen-headers"} {
		if !contains(sel.Packages, p) {
			t.Errorf("packages lack %s: %v", p, sel.Packages)
		}
	}
	target := t.TempDir()
	written, err := Apply(target, Fixes(m))
	if err != nil || !contains(written, "etc/modprobe.d/v4l2loopback-exclusive-caps.conf") {
		t.Errorf("apply: %v %v", written, err)
	}
}

func TestFixesVendors(t *testing.T) {
	cases := []struct {
		name  string
		files map[string]string
		want  []string
		file  string
	}{
		{"ROG Flow Z13", map[string]string{
			"proc/cpuinfo":                "vendor_id\t: AuthenticAMD\nmodel\t\t: 112\n",
			"sys/class/dmi/id/sys_vendor": "ASUSTeK COMPUTER INC.\n", "sys/class/dmi/id/product_name": "ROG Flow Z13 GZ302EA\n", "sys/class/dmi/id/product_family": "ROG Flow Z13\n",
		}, []string{"asus-rog", "asus-z13-touchpad"}, "etc/udev/rules.d/99-subarchy-asus-z13-touchpad.rules"},
		{"ExpertBook B9406 on Panther Lake", map[string]string{
			"proc/cpuinfo":                "vendor_id\t: GenuineIntel\nmodel\t\t: 204\n",
			"sys/class/dmi/id/sys_vendor": "ASUSTeK COMPUTER INC.\n", "sys/class/dmi/id/product_name": "ASUS EXPERTBOOK B9406CVA\n",
		}, []string{"intel-fred", "asus-expertbook-b9406", "asus-ptl-backlight"}, "etc/libinput/asus-expertbook-b9406.quirks"},
		{"Dell XPS 13 DX13260 with sidecar amps", map[string]string{
			"proc/cpuinfo":                "vendor_id\t: GenuineIntel\nmodel\t\t: 204\n",
			"sys/class/dmi/id/sys_vendor": "Dell Inc.\n", "sys/class/dmi/id/product_name": "XPS 13 DX13260\n", "sys/class/dmi/id/product_sku": "0E53\n",
		}, []string{"dell-xps13-ptl-speakers", "dell-xps13-sidecar-amps"}, ""},
		{"Yoga Pro 7", map[string]string{
			"proc/cpuinfo":                "vendor_id\t: GenuineIntel\nmodel\t\t: 170\n",
			"sys/class/dmi/id/sys_vendor": "LENOVO\n", "sys/class/dmi/id/product_name": "83JD\n", "sys/class/dmi/id/product_family": "Yoga Pro 7 14IAH10\n",
		}, []string{"lenovo-yoga-pro7-bass"}, "etc/modprobe.d/lenovo-yoga-pro7-bass.conf"},
		{"TUXEDO", map[string]string{
			"proc/cpuinfo":                "vendor_id\t: GenuineIntel\nmodel\t\t: 186\n",
			"sys/class/dmi/id/sys_vendor": "TUXEDO\n", "sys/class/dmi/id/product_name": "TUXEDO InfinityBook Pro 14\n",
		}, []string{"tuxedo-keyboard"}, "etc/modprobe.d/blacklist-clevo-xsm-wmi.conf"},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			m, err := Detect(fixtureRoot(t, c.files))
			if err != nil {
				t.Fatal(err)
			}
			got := fixNames(Fixes(m))
			for _, w := range c.want {
				if !contains(got, w) {
					t.Errorf("fixes lack %s: %v", w, got)
				}
			}
			if c.file != "" {
				target := t.TempDir()
				written, err := Apply(target, Fixes(m))
				if err != nil || !contains(written, c.file) {
					t.Errorf("apply: %v %v", written, err)
				}
			}
		})
	}
	// A plain machine gets none of the vendor fixes.
	m, _ := Detect(fixtureRoot(t, map[string]string{"proc/cpuinfo": "vendor_id\t: GenuineIntel\nmodel\t\t: 94\n", "sys/class/dmi/id/sys_vendor": "Acme\n", "sys/class/dmi/id/product_name": "Box\n"}))
	for _, f := range Fixes(m) {
		if strings.HasPrefix(f.Name, "asus-") || strings.HasPrefix(f.Name, "dell-") || strings.HasPrefix(f.Name, "lenovo-") || f.Name == "tuxedo-keyboard" || f.Name == "framework16-qmk" {
			t.Errorf("vendor fix %s on a plain machine", f.Name)
		}
	}
}

func TestFixesAppleAndSurface(t *testing.T) {
	t2, _ := Detect(fixtureRoot(t, map[string]string{
		"proc/cpuinfo":                "vendor_id\t: GenuineIntel\nmodel\t\t: 158\n",
		"sys/class/dmi/id/sys_vendor": "Apple Inc.\n", "sys/class/dmi/id/product_name": "MacBookPro16,1\n",
		"sys/bus/pci/devices/0000:03:00.0/vendor": "0x106b\n", "sys/bus/pci/devices/0000:03:00.0/device": "0x1801\n", "sys/bus/pci/devices/0000:03:00.0/class": "0x0c0300\n",
	}))
	got := fixNames(Fixes(t2))
	for _, w := range []string{"apple-t2", "apple-brcmfmac-supplicant"} {
		if !contains(got, w) {
			t.Errorf("T2 Mac lacks %s: %v", w, got)
		}
	}
	if contains(got, "apple-spi-keyboard") {
		t.Error("a MacBookPro16,1 has no SPI keyboard")
	}
	target := t.TempDir()
	written, _ := Apply(target, Fixes(t2))
	if !contains(written, "etc/limine-entry-tool.d/apple-t2-mac.conf") || !contains(written, "etc/modprobe.d/brcmfmac.conf") {
		t.Errorf("T2 files: %v", written)
	}

	spi, _ := Detect(fixtureRoot(t, map[string]string{
		"proc/cpuinfo":                "vendor_id\t: GenuineIntel\nmodel\t\t: 78\n",
		"sys/class/dmi/id/sys_vendor": "Apple Inc.\n", "sys/class/dmi/id/product_name": "MacBookPro13,2\n",
		"sys/bus/pci/devices/0000:02:00.0/vendor": "0x14e4\n", "sys/bus/pci/devices/0000:02:00.0/device": "0x43ba\n", "sys/bus/pci/devices/0000:02:00.0/class": "0x028000\n",
	}))
	got = fixNames(Fixes(spi))
	for _, w := range []string{"apple-spi-keyboard", "apple-nvme-suspend", "apple-brcmfmac-supplicant"} {
		if !contains(got, w) {
			t.Errorf("2016 MacBook Pro lacks %s: %v", w, got)
		}
	}
	if contains(got, "apple-t2") {
		t.Error("a 2016 MacBook Pro has no T2")
	}
	if !contains(Select(spi).Services, "subarchy-apple-nvme-suspend") {
		t.Errorf("services: %v", Select(spi).Services)
	}

	surface, _ := Detect(fixtureRoot(t, map[string]string{
		"proc/cpuinfo":                "vendor_id\t: GenuineIntel\nmodel\t\t: 126\n",
		"sys/class/dmi/id/sys_vendor": "Microsoft Corporation\n", "sys/class/dmi/id/product_name": "Surface Laptop 3\n",
	}))
	got = fixNames(Fixes(surface))
	for _, w := range []string{"surface-firmware", "surface-keyboard"} {
		if !contains(got, w) {
			t.Errorf("Surface lacks %s: %v (surface matcher %v)", w, got, matches(surface, "surface"))
		}
	}
	if !contains(Select(surface).Packages, "linux-firmware-marvell") {
		t.Errorf("Surface packages: %v", Select(surface).Packages)
	}
}
