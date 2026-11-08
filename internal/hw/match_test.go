package hw

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
)

// put writes one file under a fixture root.
func put(t *testing.T, root, path, content string) {
	t.Helper()
	p := filepath.Join(root, path)
	if err := os.MkdirAll(filepath.Dir(p), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(p, []byte(content), 0o644); err != nil {
		t.Fatal(err)
	}
}

func detect(t *testing.T, root string) Machine {
	t.Helper()
	m, err := Detect(root)
	if err != nil {
		t.Fatal(err)
	}
	return m
}

func TestMatchProduct(t *testing.T) {
	root := fixture{cpu: "GenuineIntel", vendor: "Dell Inc.", product: "XPS 13 9350"}.write(t)
	put(t, root, "sys/class/dmi/id/product_family", "XPS\n")
	m := detect(t, root)
	if !m.Match("xps") || !m.Match("XPS 13") || m.Match("ThinkPad") || m.Match("") {
		t.Errorf("match: %+v", m.Facts)
	}
}

func TestLaptopByChassisLidAndSwitch(t *testing.T) {
	desktop := fixture{cpu: "AuthenticAMD", vendor: "ASUSTeK COMPUTER INC.", product: "ROG STRIX"}.write(t)
	put(t, desktop, "sys/class/dmi/id/chassis_type", "3\n")
	if detect(t, desktop).Matches()["laptop"] {
		t.Error("a desktop chassis is not a laptop")
	}
	byChassis := fixture{cpu: "GenuineIntel"}.write(t)
	put(t, byChassis, "sys/class/dmi/id/chassis_type", "10\n")
	if !detect(t, byChassis).Matches()["laptop"] {
		t.Error("chassis 10 (notebook) is a laptop")
	}
	byLid := fixture{cpu: "GenuineIntel"}.write(t)
	put(t, byLid, "proc/acpi/button/lid/LID0/state", "state:      open\n")
	m := detect(t, byLid)
	if !m.Matches()["laptop"] || m.Matches()["laptop-closed"] {
		t.Errorf("an ACPI lid, open: %+v", m.Facts)
	}
	put(t, byLid, "proc/acpi/button/lid/LID0/state", "state:      closed\n")
	if !detect(t, byLid).Matches()["laptop-closed"] {
		t.Error("the lid is closed")
	}
	bySwitch := fixture{cpu: "GenuineIntel"}.write(t)
	put(t, bySwitch, "sys/class/input/input5/capabilities/sw", "1\n")
	if !detect(t, bySwitch).Matches()["laptop"] {
		t.Error("an input switch with SW_LID is a laptop")
	}
	otherSwitch := fixture{cpu: "GenuineIntel"}.write(t)
	put(t, otherSwitch, "sys/class/input/input5/capabilities/sw", "4\n")
	if detect(t, otherSwitch).Matches()["laptop"] {
		t.Error("a switch without SW_LID is not a lid")
	}
}

func TestExternalMonitorsAndClamshell(t *testing.T) {
	root := fixture{cpu: "GenuineIntel"}.write(t)
	put(t, root, "sys/class/drm/card1-eDP-1/status", "connected\n")
	put(t, root, "sys/class/drm/card1-DP-3/status", "disconnected\n")
	if detect(t, root).Matches()["external-monitors"] {
		t.Error("only the panel is connected")
	}
	put(t, root, "sys/class/drm/card1-DP-3/status", "connected\n")
	m := detect(t, root)
	if !m.Matches()["external-monitors"] || m.Matches()["clamshell"] {
		t.Errorf("an external monitor with the lid open: %+v", m.Facts)
	}
	put(t, root, "proc/acpi/button/lid/LID0/state", "state:      closed\n")
	if !detect(t, root).Matches()["clamshell"] {
		t.Error("closed lid and an external monitor is clamshell")
	}
}

func TestGPUMatchers(t *testing.T) {
	hybrid := fixture{cpu: "GenuineIntel", pci: [][3]uint32{{0x8086, 0x46a6, 0x030000}, {0x10de, 0x25a0, 0x030200}, {0x8086, 0x51c8, 0x040300}}}.write(t)
	got := detect(t, hybrid).Matches()
	for name, want := range map[string]bool{"hybrid-gpu": true, "nvidia": true, "nvidia-gsp": true, "nvidia-without-gsp": false, "intel-sof": true, "intel": true} {
		if got[name] != want {
			t.Errorf("%s = %v, want %v", name, got[name], want)
		}
	}
	maxwell := fixture{cpu: "AuthenticAMD", pci: [][3]uint32{{0x10de, 0x1b80, 0x030000}, {0x1022, 0x1457, 0x040300}}}.write(t)
	got = detect(t, maxwell).Matches()
	for name, want := range map[string]bool{"hybrid-gpu": false, "nvidia": true, "nvidia-gsp": false, "nvidia-without-gsp": true, "intel-sof": false} {
		if got[name] != want {
			t.Errorf("%s = %v, want %v", name, got[name], want)
		}
	}
}

func TestVendorMatchers(t *testing.T) {
	cases := []struct {
		name, vendor, product, family, i2c string
		want                               string
	}{
		{"surface", "Microsoft Corporation", "Surface Pro 9", "Surface", "", "surface"},
		{"not surface", "Microsoft Corporation", "Virtual Machine", "", "", ""},
		{"framework16", "Framework", "Laptop 16 (AMD Ryzen 7040Series)", "Laptop", "", "framework16"},
		{"asus rog", "ASUSTeK COMPUTER INC.", "G14", "ROG Zephyrus", "", "asus-rog"},
		{"asus other", "ASUSTeK COMPUTER INC.", "UX5406", "Zenbook", "", ""},
		{"dell haptic", "Dell Inc.", "XPS 13 9350", "XPS", "i2c-VEN_06CB:00", "dell-xps-haptic-touchpad"},
		{"dell other", "Dell Inc.", "XPS 13 9350", "XPS", "i2c-DELL0A1B:00", ""},
	}
	for _, c := range cases {
		root := fixture{cpu: "GenuineIntel", vendor: c.vendor, product: c.product}.write(t)
		put(t, root, "sys/class/dmi/id/product_family", c.family+"\n")
		if c.i2c != "" {
			put(t, root, "sys/bus/i2c/devices/"+c.i2c+"/name", "x\n")
		}
		got := detect(t, root).Matches()
		for _, name := range []string{"surface", "framework16", "asus-rog", "dell-xps-haptic-touchpad"} {
			if got[name] != (name == c.want) {
				t.Errorf("%s: %s = %v", c.name, name, got[name])
			}
		}
	}
}

func TestFingerprint(t *testing.T) {
	byVendor := fixture{cpu: "GenuineIntel", usb: [][3]uint32{{0x27c6, 0x55a2, 0xef}}}.write(t)
	if !detect(t, byVendor).Matches()["fingerprint"] {
		t.Error("a Goodix reader by vendor")
	}
	byProduct := fixture{cpu: "GenuineIntel", usb: [][3]uint32{{0x1234, 0x0001, 0x00}}}.write(t)
	put(t, byProduct, "sys/bus/usb/devices/3-1/product", "Synaptics Fingerprint Sensor\n")
	if !detect(t, byProduct).Matches()["fingerprint"] {
		t.Error("a reader by product string")
	}
	none := fixture{cpu: "GenuineIntel", usb: [][3]uint32{{0x1234, 0x0001, 0x00}}}.write(t)
	put(t, none, "sys/bus/usb/devices/3-1/product", "USB Mouse\n")
	if detect(t, none).Matches()["fingerprint"] {
		t.Error("a mouse is not a reader")
	}
}

func TestWebcamTouchpadTouchscreen(t *testing.T) {
	root := fixture{cpu: "GenuineIntel"}.write(t)
	put(t, root, "sys/class/video4linux/video0/dev", "81:0\n")
	put(t, root, "run/udev/data/c81:0", "E:ID_V4L_CAPABILITIES=:capture:\nE:ID_V4L_PRODUCT=Integrated Camera\n")
	put(t, root, "sys/class/video4linux/video1/dev", "81:1\n")
	put(t, root, "run/udev/data/c81:1", "E:ID_V4L_CAPABILITIES=:\n")
	put(t, root, "sys/class/input/event3/device/name", "SYNA8017:00 06CB:CE44 Touchpad\n")
	put(t, root, "sys/class/input/event4/device/name", "ELAN2513:00 04F3:2E3B\n")
	put(t, root, "sys/class/input/event5/device/name", "AT Translated Set 2 keyboard\n")
	// udev tags live under the input record's name; event4's device dir is
	// a real directory here, so the tag file is named after it.
	put(t, root, "run/udev/data/+input:device", "E:ID_INPUT_TOUCHSCREEN=1\n")
	m := detect(t, root)
	if !m.Matches()["webcam"] {
		t.Error("video0 captures")
	}
	if m.Facts.Touchpad != "SYNA8017:00 06CB:CE44 Touchpad" {
		t.Errorf("touchpad = %q", m.Facts.Touchpad)
	}
	if !m.Matches()["touchpad"] {
		t.Error("touchpad by name")
	}
	if !m.Matches()["touchscreen"] {
		t.Errorf("touchscreen by udev tag: %+v", m.Facts)
	}
	bare := fixture{cpu: "GenuineIntel"}.write(t)
	put(t, bare, "sys/class/video4linux/video1/dev", "81:1\n")
	put(t, bare, "run/udev/data/c81:1", "E:ID_V4L_CAPABILITIES=:\n")
	got := detect(t, bare).Matches()
	if got["webcam"] || got["touchpad"] || got["touchscreen"] {
		t.Error("an output-only video node, no touch devices")
	}
}

func TestBacklightChoice(t *testing.T) {
	cases := []struct {
		devices []string
		want    string
	}{
		{[]string{"intel_backlight"}, "intel_backlight"},
		{[]string{"acpi_video0", "intel_backlight"}, "intel_backlight"},
		{[]string{"appletb_backlight", "gmux_backlight"}, "gmux_backlight"},
		{[]string{"amdgpu_bl1", "acpi_video0"}, "amdgpu_bl1"},
		{[]string{"appletb_backlight"}, ""},
		{[]string{"ddcci1"}, "ddcci1"},
		{nil, ""},
	}
	for _, c := range cases {
		if got := pickBacklight(c.devices); got != c.want {
			t.Errorf("%v: got %q, want %q", c.devices, got, c.want)
		}
	}
	root := fixture{cpu: "GenuineIntel"}.write(t)
	put(t, root, "sys/class/backlight/intel_backlight/brightness", "10\n")
	m := detect(t, root)
	if m.Facts.Backlight != "intel_backlight" || !m.Matches()["display"] {
		t.Errorf("backlight = %q", m.Facts.Backlight)
	}
}

func TestVMVulkanAndArch(t *testing.T) {
	root := fixture{cpu: "GenuineIntel", vendor: "QEMU", product: "Standard PC (Q35 + ICH9, 2009)"}.write(t)
	got := detect(t, root).Matches()
	if !got["vm"] {
		t.Error("QEMU is a VM")
	}
	if got["vulkan"] {
		t.Error("no ICD installed")
	}
	put(t, root, "usr/share/vulkan/icd.d/intel_icd.x86_64.json", "{}\n")
	if !detect(t, root).Matches()["vulkan"] {
		t.Error("an ICD is installed")
	}
	byFlag := fixture{cpu: "GenuineIntel"}.write(t)
	put(t, byFlag, "proc/cpuinfo", "vendor_id\t: GenuineIntel\nflags\t\t: fpu vme hypervisor sse\n")
	if !detect(t, byFlag).Matches()["vm"] {
		t.Error("the hypervisor CPU flag marks a VM")
	}
	hw := fixture{cpu: "GenuineIntel", vendor: "LENOVO", product: "21AB"}.write(t)
	m := detect(t, hw)
	if m.Matches()["vm"] {
		t.Error("real hardware")
	}
	if m.Matches()["x86"] == m.Matches()["aarch64"] {
		t.Error("exactly one architecture matches")
	}
	m.Facts.Arch, m.Facts.DeviceTree = "aarch64", "apple,j314s\x00apple,t6000\x00"
	if !m.Matches()["apple-silicon"] || !m.Matches()["aarch64"] {
		t.Error("an Apple device tree on aarch64")
	}
}

func TestEveryMatcherHasASource(t *testing.T) {
	seen := map[string]bool{}
	for _, mt := range Matchers {
		if mt.Source == "" || !containsStr(mt.Source, "omarchy-hw-") {
			t.Errorf("%s names no Omarchy source", mt.Name)
		}
		if seen[mt.Name] {
			t.Errorf("%s listed twice", mt.Name)
		}
		seen[mt.Name] = true
		if _, ok := FindMatcher(mt.Name); !ok {
			t.Errorf("%s not found", mt.Name)
		}
	}
	if _, ok := FindMatcher("nothing"); ok {
		t.Error("an unknown matcher")
	}
}

func containsStr(s, sub string) bool { return strings.Contains(s, sub) }
