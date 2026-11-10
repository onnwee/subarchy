package hw

import (
	"os"
	"path/filepath"
	"runtime"
	"sort"
	"strconv"
	"strings"
)

// The matching questions the hardware fixes ask (ADR 0050), ported from
// Omarchy 4.5.0's omarchy-hw-* commands as behaviour, not code. Each
// matcher names the Omarchy command it follows; the facts come from the
// sysfs, /proc and /run paths under Detect's root, so fixtures can stand
// in for a machine. `subcult hw packages` stays the only package chooser.

// Facts are the machine details the matchers read, beyond the devices.
type Facts struct {
	Arch          string // "x86_64" or "aarch64", from the running binary
	SysVendor     string
	ProductName   string
	ProductFamily string
	ChassisType   string
	Hypervisor    bool     // the CPU reports a hypervisor
	LidSwitch     bool     // an ACPI lid or an input device with a lid switch
	LidClosed     bool     // ACPI reports the lid closed
	External      bool     // a connected DRM connector that is not a panel
	Backlight     string   // the backlight device the display helpers use
	I2C           []string // i2c device names under /sys/bus/i2c/devices
	USBProducts   []string // USB product strings, lower case
	Webcam        bool     // a video4linux capture node udev marks capture
	Touchpad      string   // the touchpad's input device name
	Touchscreen   string   // the touchscreen's input device name
	DeviceTree    string   // /proc/device-tree/compatible, aarch64 boards
	Vulkan        bool     // a Vulkan ICD is installed
	ProductSKU    string   // DMI product_sku (Dell writes a model code there)
	CPUModel      int      // the CPU's model number from /proc/cpuinfo (family 6 on Intel)
	Battery       bool     // a battery under /sys/class/power_supply
	ACPIIDs       []string // ACPI device hardware ids (the hid files), e.g. OVTI08F4
	Modules       []string // loaded kernel modules (/proc/modules), on the live system
	// PlatformProfiles are the firmware platform-profile devices by name
	// (/sys/class/platform-profile/*/name), e.g. dell-pc.
	PlatformProfiles []string
}

var archNames = map[string]string{"amd64": "x86_64", "arm64": "aarch64"}

// readFacts fills the facts from a root directory.
func readFacts(root string) Facts {
	var f Facts
	f.Arch = archNames[runtime.GOARCH]
	if f.Arch == "" {
		f.Arch = runtime.GOARCH
	}
	dmi := func(name string) string {
		b, _ := os.ReadFile(filepath.Join(root, "sys/class/dmi/id", name))
		return strings.TrimSpace(string(b))
	}
	f.SysVendor, f.ProductName, f.ProductFamily, f.ChassisType = dmi("sys_vendor"), dmi("product_name"), dmi("product_family"), dmi("chassis_type")
	f.ProductSKU = dmi("product_sku")
	if cpu, err := os.ReadFile(filepath.Join(root, "proc/cpuinfo")); err == nil {
		for _, line := range strings.Split(string(cpu), "\n") {
			if k, v, ok := strings.Cut(line, ":"); ok && strings.TrimSpace(k) == "model" && f.CPUModel == 0 {
				f.CPUModel, _ = strconv.Atoi(strings.TrimSpace(v))
			}
			if k, v, ok := strings.Cut(line, ":"); ok && strings.TrimSpace(k) == "flags" {
				for _, flag := range strings.Fields(v) {
					if flag == "hypervisor" {
						f.Hypervisor = true
					}
				}
				break
			}
		}
	}
	// omarchy-hw-laptop, omarchy-hw-laptop-closed: an ACPI lid, or an input
	// device whose switch capabilities include SW_LID (bit 0).
	for _, kind := range glob(root, "sys/class/power_supply/*/type") {
		if b, err := os.ReadFile(kind); err == nil && strings.TrimSpace(string(b)) == "Battery" {
			// A peripheral's battery (mouse, headset) has scope Device.
			scope, _ := os.ReadFile(filepath.Join(filepath.Dir(kind), "scope"))
			if strings.TrimSpace(string(scope)) != "Device" {
				f.Battery = true
			}
		}
	}
	for _, hid := range glob(root, "sys/bus/acpi/devices/*/hid") {
		if b, err := os.ReadFile(hid); err == nil {
			f.ACPIIDs = append(f.ACPIIDs, strings.TrimSpace(string(b)))
		}
	}
	sort.Strings(f.ACPIIDs)
	if b, err := os.ReadFile(filepath.Join(root, "proc/modules")); err == nil {
		for _, line := range strings.Split(string(b), "\n") {
			if name, _, ok := strings.Cut(line, " "); ok && name != "" {
				f.Modules = append(f.Modules, name)
			}
		}
	}
	for _, name := range glob(root, "sys/class/platform-profile/*/name") {
		if b, err := os.ReadFile(name); err == nil {
			f.PlatformProfiles = append(f.PlatformProfiles, strings.TrimSpace(string(b)))
		}
	}
	sort.Strings(f.PlatformProfiles)
	for _, state := range glob(root, "proc/acpi/button/lid/*/state") {
		f.LidSwitch = true
		if b, err := os.ReadFile(state); err == nil && strings.Contains(string(b), "closed") {
			f.LidClosed = true
		}
	}
	for _, sw := range glob(root, "sys/class/input/*/capabilities/sw") {
		b, err := os.ReadFile(sw)
		if err != nil {
			continue
		}
		words := strings.Fields(string(b))
		if len(words) == 0 {
			continue
		}
		if v, err := strconv.ParseUint(words[len(words)-1], 16, 64); err == nil && v&1 == 1 {
			f.LidSwitch = true
		}
	}
	// omarchy-hw-external-monitors: a connected connector that is not the
	// laptop's own panel.
	for _, status := range glob(root, "sys/class/drm/card*-*/status") {
		name := filepath.Base(filepath.Dir(status))
		if strings.Contains(name, "-eDP-") || strings.Contains(name, "-LVDS-") || strings.Contains(name, "-DSI-") {
			continue
		}
		if b, err := os.ReadFile(status); err == nil && strings.TrimSpace(string(b)) == "connected" {
			f.External = true
		}
	}
	f.Backlight = pickBacklight(names(glob(root, "sys/class/backlight/*")))
	f.I2C = names(glob(root, "sys/bus/i2c/devices/*"))
	for _, p := range glob(root, "sys/bus/usb/devices/*/product") {
		if b, err := os.ReadFile(p); err == nil {
			f.USBProducts = append(f.USBProducts, strings.ToLower(strings.TrimSpace(string(b))))
		}
	}
	// omarchy-hw-webcam: a video node whose udev record lists capture.
	for _, node := range glob(root, "sys/class/video4linux/video*") {
		dev, err := os.ReadFile(filepath.Join(node, "dev"))
		if err != nil {
			continue
		}
		data, err := os.ReadFile(filepath.Join(root, "run/udev/data", "c"+strings.TrimSpace(string(dev))))
		if err == nil && strings.Contains(udevProperty(string(data), "ID_V4L_CAPABILITIES"), ":capture:") {
			f.Webcam = true
		}
	}
	// omarchy-hw-touchpad, omarchy-hw-touchscreen: by the input device's
	// name, or udev's ID_INPUT_* tag for its input record.
	for _, event := range glob(root, "sys/class/input/event*") {
		nameB, err := os.ReadFile(filepath.Join(event, "device", "name"))
		if err != nil {
			continue
		}
		name := strings.TrimSpace(string(nameB))
		lower := strings.ToLower(name)
		tags := ""
		if target, err := filepath.EvalSymlinks(filepath.Join(event, "device")); err == nil {
			if data, err := os.ReadFile(filepath.Join(root, "run/udev/data", "+input:"+filepath.Base(target))); err == nil {
				tags = string(data)
			}
		}
		if f.Touchpad == "" && (strings.Contains(lower, "touchpad") || strings.Contains(lower, "trackpad") || udevProperty(tags, "ID_INPUT_TOUCHPAD") == "1") {
			f.Touchpad = name
		}
		if f.Touchscreen == "" && udevProperty(tags, "ID_INPUT_TOUCHSCREEN") == "1" {
			f.Touchscreen = name
		}
	}
	if b, err := os.ReadFile(filepath.Join(root, "proc/device-tree/compatible")); err == nil {
		f.DeviceTree = strings.ReplaceAll(string(b), "\x00", " ")
	}
	f.Vulkan = len(glob(root, "usr/share/vulkan/icd.d/*.json")) > 0
	return f
}

func glob(root, pattern string) []string {
	m, _ := filepath.Glob(filepath.Join(root, pattern))
	sort.Strings(m)
	return m
}

func names(paths []string) []string {
	out := make([]string, 0, len(paths))
	for _, p := range paths {
		out = append(out, filepath.Base(p))
	}
	return out
}

// udevProperty reads E:KEY=value from a udev data record.
func udevProperty(data, key string) string {
	for _, line := range strings.Split(data, "\n") {
		if v, ok := strings.CutPrefix(line, "E:"+key+"="); ok {
			return strings.TrimSpace(v)
		}
	}
	return ""
}

// pickBacklight follows omarchy-hw-display: the Apple gmux first, then
// amdgpu, Intel and ACPI backlights, else the first device that is not the
// MacBook touch bar's.
func pickBacklight(devices []string) string {
	usable := func(n string) bool { return n != "" && n != "appletb_backlight" }
	for _, want := range []string{"gmux_backlight", "amdgpu_bl", "intel_backlight", "acpi_video"} {
		for _, d := range devices {
			if usable(d) && (d == want || strings.HasPrefix(d, want)) {
				return d
			}
		}
	}
	for _, d := range devices {
		if usable(d) {
			return d
		}
	}
	return ""
}

// Match follows omarchy-hw-match: the product name or family contains the
// pattern, case insensitive.
func (m Machine) Match(pattern string) bool {
	p := strings.ToLower(pattern)
	return p != "" && (strings.Contains(strings.ToLower(m.Facts.ProductName), p) || strings.Contains(strings.ToLower(m.Facts.ProductFamily), p))
}

func (m Machine) displays() []Device {
	var out []Device
	for _, d := range m.Devices {
		if d.Bus == "pci" && d.Kind() == "display" {
			out = append(out, d)
		}
	}
	return out
}

func (m Machine) nvidiaIn(lo, hi uint16) bool {
	for _, d := range m.displays() {
		if d.Vendor == vendorNVIDIA && d.Device >= lo && d.Device < hi {
			return true
		}
	}
	return false
}

// Matcher answers one hardware question.
type Matcher struct {
	Name   string
	Source string // the Omarchy 4.5.0 command it follows
	Test   func(Machine) bool
}

var fingerprintVendors = map[uint16]bool{0x27c6: true, 0x138a: true, 0x06cb: true, 0x08ff: true, 0x1c7a: true, 0x147e: true}

// Matchers are the questions, in a fixed order. `subcult hw <name>` exits
// 0 when the answer is yes.
var Matchers = []Matcher{
	{"x86", "omarchy-hw-x86", func(m Machine) bool { return m.Facts.Arch == "x86_64" }},
	{"aarch64", "omarchy-hw-aarch64", func(m Machine) bool { return m.Facts.Arch == "aarch64" }},
	{"apple-silicon", "omarchy-hw-aarch64-apple (device tree)", func(m Machine) bool {
		return m.Facts.Arch == "aarch64" && strings.Contains(m.Facts.DeviceTree, "apple,")
	}},
	{"intel", "omarchy-hw-intel", func(m Machine) bool { return m.CPUVendor == "GenuineIntel" }},
	{"vm", "omarchy-hw-vm (DMI vendor and the CPU's hypervisor flag, not systemd-detect-virt)", func(m Machine) bool {
		return m.VM != "" || m.Facts.Hypervisor
	}},
	{"laptop", "omarchy-hw-laptop", func(m Machine) bool {
		switch m.Facts.ChassisType {
		case "8", "9", "10", "14", "30", "31", "32":
			return true
		}
		return m.Facts.LidSwitch
	}},
	{"laptop-closed", "omarchy-hw-laptop-closed (ACPI lid state only)", func(m Machine) bool { return m.Facts.LidClosed }},
	{"external-monitors", "omarchy-hw-external-monitors", func(m Machine) bool { return m.Facts.External }},
	{"clamshell", "omarchy-hw-clamshell", func(m Machine) bool { return m.Facts.LidClosed && m.Facts.External }},
	{"hybrid-gpu", "omarchy-hw-hybrid-gpu (two display devices; supergfxctl is not asked)", func(m Machine) bool {
		return len(m.displays()) >= 2
	}},
	{"nvidia", "omarchy-hw-nvidia", func(m Machine) bool { return m.nvidiaIn(0, 0xffff) }},
	{"nvidia-gsp", "omarchy-hw-nvidia-gsp", func(m Machine) bool { return m.nvidiaIn(nvidiaTuring, 0xffff) }},
	{"nvidia-without-gsp", "omarchy-hw-nvidia-without-gsp", func(m Machine) bool { return m.nvidiaIn(nvidiaMaxwell, nvidiaTuring) }},
	{"intel-sof", "omarchy-hw-intel-sof (PCI audio class instead of lspci's text)", func(m Machine) bool {
		for _, d := range m.Devices {
			if d.Bus == "pci" && d.Kind() == "audio" && d.Vendor == vendorIntel {
				return true
			}
		}
		return false
	}},
	{"surface", "omarchy-hw-surface", func(m Machine) bool {
		return m.Facts.SysVendor == "Microsoft Corporation" && m.Match("Surface")
	}},
	{"framework16", "omarchy-hw-framework16", func(m Machine) bool {
		return m.Facts.SysVendor == "Framework" && m.Match("Laptop 16")
	}},
	{"asus-rog", "omarchy-hw-asus-rog", func(m Machine) bool {
		return m.Facts.SysVendor == "ASUSTeK COMPUTER INC." && strings.Contains(m.Facts.ProductFamily, "ROG")
	}},
	{"dell-xps-haptic-touchpad", "omarchy-hw-dell-xps-haptic-touchpad", func(m Machine) bool {
		if !m.Match("XPS") {
			return false
		}
		for _, d := range m.Facts.I2C {
			if d == "i2c-VEN_06CB:00" {
				return true
			}
		}
		return false
	}},
	{"fingerprint", "omarchy-hw-fingerprint (USB product strings and vendors)", func(m Machine) bool {
		for _, p := range m.Facts.USBProducts {
			if strings.Contains(p, "fingerprint") || strings.Contains(p, "biometric") || strings.Contains(p, "elan:arm-m4") || strings.HasPrefix(p, "fpc ") {
				return true
			}
		}
		for _, d := range m.Devices {
			if d.Bus == "usb" && fingerprintVendors[d.Vendor] {
				return true
			}
		}
		return false
	}},
	{"webcam", "omarchy-hw-webcam (udev capture capability)", func(m Machine) bool { return m.Facts.Webcam }},
	{"touchpad", "omarchy-hw-touchpad (input device names and udev, not hyprctl)", func(m Machine) bool { return m.Facts.Touchpad != "" }},
	{"touchscreen", "omarchy-hw-touchscreen (udev, not hyprctl)", func(m Machine) bool { return m.Facts.Touchscreen != "" }},
	{"display", "omarchy-hw-display (without the platform displays.conf)", func(m Machine) bool { return m.Facts.Backlight != "" }},
	{"vulkan", "omarchy-hw-vulkan", func(m Machine) bool { return m.Facts.Vulkan }},
}

// Matches answers every matcher.
func (m Machine) Matches() map[string]bool {
	out := map[string]bool{}
	for _, mt := range Matchers {
		out[mt.Name] = mt.Test(m)
	}
	return out
}

// Matcher finds a matcher by name.
func FindMatcher(name string) (Matcher, bool) {
	for _, mt := range Matchers {
		if mt.Name == name {
			return mt, true
		}
	}
	return Matcher{}, false
}
