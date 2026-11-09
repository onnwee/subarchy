package hw

import (
	"os"
	"path/filepath"
	"sort"
	"strings"
)

// Fix is one hardware fix (ADR 0050), ported from Omarchy 4.5.0's
// install/hardware scripts as behaviour: a condition on the machine, the
// packages and services it needs, and the files it writes. Each names its
// Omarchy source and whether it has run on the hardware it is for; until
// then it is untested, whatever the fixtures say.
type Fix struct {
	Name     string            `json:"name"`
	Summary  string            `json:"summary"`
	Source   string            `json:"source"` // Omarchy 4.5.0 path
	Tested   bool              `json:"tested"`
	Packages []string          `json:"packages,omitempty"`
	Services []string          `json:"services,omitempty"`
	Files    map[string]string `json:"files,omitempty"` // path under the root -> content
	Note     string            `json:"note,omitempty"`  // what still needs a hand or a package
	applies  func(Machine) bool
}

// Intel radios whose Wi-Fi 7 (EHT) mode fails; 802.11be is turned off.
var intelEHTRadios = map[uint16]bool{0xe440: true, 0x272b: true}

// Intel CPU models (family 6) Omarchy runs intel-lpmd on: Alder Lake,
// Raptor Lake, Meteor Lake, Arrow Lake, Lunar Lake and Panther Lake parts.
var intelLPMDModels = map[int]bool{151: true, 154: true, 170: true, 172: true, 183: true, 186: true, 189: true, 191: true, 204: true}

const intelPantherLake = 204

func (m Machine) hasPCI(vendor uint16, devices map[uint16]bool) bool {
	for _, d := range m.Devices {
		if d.Bus == "pci" && d.Vendor == vendor && devices[d.Device] {
			return true
		}
	}
	return false
}

func (m Machine) hasDisplay(vendor uint16) bool {
	for _, d := range m.Devices {
		if d.Kind() == "display" && d.Vendor == vendor {
			return true
		}
	}
	return false
}

func (m Machine) hasACPI(id string) bool {
	for _, h := range m.Facts.ACPIIDs {
		if h == id {
			return true
		}
	}
	return false
}

func (m Machine) nvidiaOpen() bool {
	for _, d := range m.Devices {
		if d.Kind() == "display" && d.Vendor == vendorNVIDIA && d.Device >= nvidiaTuring {
			return true
		}
	}
	return false
}

// catalogue is every fix, in the order they apply.
var catalogue = []Fix{
	{
		Name: "intel-wifi7-eht", Summary: "Turn Wi-Fi 7 (802.11be) off on Intel radios that fail with it",
		Source:  "install/hardware/intel/fix-wifi7-eht.sh",
		Files:   map[string]string{"etc/modprobe.d/iwlwifi-disable-eht.conf": "# Subarchy hardware fix intel-wifi7-eht (ADR 0050)\noptions iwlwifi disable_11be=Y\n"},
		applies: func(m Machine) bool { return m.hasPCI(vendorIntel, intelEHTRadios) },
	},
	{
		Name: "intel-fred", Summary: "Flexible Return and Event Delivery on Panther Lake (kernel command line fred=on)",
		Source: "install/hardware/intel/fred.sh",
		Files:  map[string]string{"etc/limine-entry-tool.d/intel-panther-lake-fred.conf": "# Subarchy hardware fix intel-fred (ADR 0050)\nKERNEL_CMDLINE[default]+=\" fred=on\"\n"},
		applies: func(m Machine) bool {
			return m.CPUVendor == "GenuineIntel" && m.Facts.CPUModel == intelPantherLake
		},
	},
	{
		Name: "intel-lpmd", Summary: "Intel Low Power Mode Daemon on the Intel laptops it supports",
		Source: "install/hardware/intel/lpmd.sh", Packages: []string{"intel-lpmd"}, Services: []string{"intel_lpmd"},
		applies: func(m Machine) bool {
			return m.CPUVendor == "GenuineIntel" && m.Facts.Battery && intelLPMDModels[m.Facts.CPUModel]
		},
	},
	{
		Name: "intel-video", Summary: "Intel video acceleration: the oneVPL dispatcher and runtime beside the media driver",
		Source: "install/hardware/intel/video-acceleration.sh", Packages: []string{"libvpl", "vpl-gpu-rt"},
		applies: func(m Machine) bool { return m.hasDisplay(vendorIntel) && m.VM == "" },
	},
	{
		Name: "intel-ipu7-camera", Summary: "Intel IPU7 camera (OmniVision OV08F4 sensor)",
		Source:  "install/hardware/intel/ipu7-camera.sh",
		Note:    "intel-ipu7-camera is not in Arch's repositories; package it under packaging/aur before this fix can install it",
		applies: func(m Machine) bool { return m.hasACPI("OVTI08F4") },
	},
	{
		Name: "nvidia-modeset", Summary: "NVIDIA open driver: kernel modesetting and the modules in the initramfs",
		Source: "install/hardware/nvidia.sh",
		Files: map[string]string{
			"etc/modprobe.d/nvidia.conf":        "# Subarchy hardware fix nvidia-modeset (ADR 0050)\noptions nvidia_drm modeset=1\n",
			"etc/mkinitcpio.conf.d/nvidia.conf": "# Subarchy hardware fix nvidia-modeset (ADR 0050)\nMODULES+=(nvidia nvidia_modeset nvidia_uvm nvidia_drm)\n",
		},
		applies: func(m Machine) bool { return m.nvidiaOpen() },
	},
	{
		Name: "hid-apple-fkeys", Summary: "Function keys first on Apple-style keyboards (hid_apple fnmode=2)",
		Source: "install/hardware/fix-fkeys.sh", Tested: true, // every VM run exercises it
		Files:   map[string]string{"etc/modprobe.d/hid_apple.conf": "# Subarchy hardware fix hid-apple-fkeys (ADR 0050)\noptions hid_apple fnmode=2\n"},
		applies: func(m Machine) bool { return m.Facts.Arch == "x86_64" },
	},
}

// AllFixes is the catalogue.
func AllFixes() []Fix {
	out := make([]Fix, len(catalogue))
	copy(out, catalogue)
	return out
}

// Fixes are the fixes that apply to the machine, in catalogue order.
func Fixes(m Machine) []Fix {
	var out []Fix
	for _, f := range catalogue {
		if f.applies(m) {
			out = append(out, f)
		}
	}
	return out
}

// Apply writes the fixes' files under root, creating directories, and
// returns the paths whose content changed. A file already holding the
// content is left alone.
func Apply(root string, fixes []Fix) ([]string, error) {
	var written []string
	for _, f := range fixes {
		paths := make([]string, 0, len(f.Files))
		for p := range f.Files {
			paths = append(paths, p)
		}
		sort.Strings(paths)
		for _, p := range paths {
			full := filepath.Join(root, p)
			if old, err := os.ReadFile(full); err == nil && string(old) == f.Files[p] {
				continue
			}
			if err := os.MkdirAll(filepath.Dir(full), 0o755); err != nil {
				return written, err
			}
			if err := os.WriteFile(full, []byte(f.Files[p]), 0o644); err != nil {
				return written, err
			}
			written = append(written, p)
		}
	}
	return written, nil
}

// NeedsInitramfs reports whether written files change what the initramfs
// or the kernel command line carry.
func NeedsInitramfs(written []string) bool {
	for _, p := range written {
		if strings.HasPrefix(p, "etc/modprobe.d/") || strings.HasPrefix(p, "etc/mkinitcpio.conf.d/") || strings.HasPrefix(p, "etc/limine-entry-tool.d/") {
			return true
		}
	}
	return false
}
