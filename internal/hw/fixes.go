package hw

import (
	"os"
	"path/filepath"
	"regexp"
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

// Apple's T2 security chip appears as a PCI bridge; Macs with it need the
// t2linux kernel and firmware.
const vendorApple = 0x106b

var appleT2Bridges = map[uint16]bool{0x1801: true, 0x1802: true}

// Broadcom radios in Intel Macs whose WPA handshake must run in software.
var appleBroadcomRadios = map[uint16]bool{0x43ba: true, 0x43bb: true, 0x43bc: true, 0x43a3: true, 0x43dc: true, 0x4464: true, 0x4488: true, 0x4425: true, 0x4433: true}

// MacBooks with the SPI keyboard, and those whose NVMe drive breaks suspend.
var (
	appleSPIKeyboard = regexp.MustCompile(`^(MacBook[89],1|MacBook1[02],1|MacBookPro13,[123]|MacBookPro14,[123])$`)
	appleNVMeSuspend = regexp.MustCompile(`^(MacBook(8,1|9,1|10,1)|MacBookPro13,[123]|MacBookPro14,[123])$`)
)

// Broadcom radios that need the proprietary wl driver (BCM4360, BCM4331).
const vendorBroadcom = 0x14e4

var broadcomWLRadios = map[uint16]bool{0x43a0: true, 0x4331: true}

// matches answers one of the matching questions (match.go) by name.
func matches(m Machine, question string) bool {
	mt, ok := FindMatcher(question)
	return ok && mt.Test(m)
}

func isPantherLake(m Machine) bool {
	return m.CPUVendor == "GenuineIntel" && m.Facts.CPUModel == intelPantherLake
}

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
	// Vendors (issue #82): ASUS, Dell, Framework, Lenovo, Tuxedo.
	{
		Name: "asus-rog", Summary: "ASUS ROG laptops: asusctl and its daemon for fans, keyboard lights and profiles",
		Source: "install/hardware/asus-rog.sh", Packages: []string{"asusctl"}, Services: []string{"asusd"},
		applies: func(m Machine) bool { return matches(m, "asus-rog") },
	},
	{
		Name: "asus-z13-touchpad", Summary: "ASUS ROG Flow Z13 (GZ302): the detachable keyboard's touchpad counts as internal",
		Source: "install/hardware/asus/fix-z13-touchpad.sh",
		Files: map[string]string{"etc/udev/rules.d/99-subarchy-asus-z13-touchpad.rules": "# Subarchy hardware fix asus-z13-touchpad (ADR 0050)\n" +
			"ACTION==\"add|change\", KERNEL==\"event*\", ATTRS{idVendor}==\"0b05\", ATTRS{idProduct}==\"1a30\", ENV{ID_INPUT_TOUCHPAD}==\"1\", ENV{ID_INPUT_TOUCHPAD_INTEGRATION}=\"internal\"\n"},
		applies: func(m Machine) bool { return matches(m, "asus-rog") && m.Match("GZ302") },
	},
	{
		Name: "asus-expertbook-b9406", Summary: "ASUS ExpertBook B9406 (Panther Lake): panel replay off, touchpad pressure quirk",
		Source: "install/hardware/asus/fix-asus-ptl-b9406-display.sh, fix-asus-ptl-b9406-touchpad.sh",
		Files: map[string]string{
			"etc/limine-entry-tool.d/asus-expertbook-b9406-display.conf": "# Subarchy hardware fix asus-expertbook-b9406 (ADR 0050)\nKERNEL_CMDLINE[default]+=\" xe.enable_panel_replay=0\"\n",
			"etc/libinput/asus-expertbook-b9406.quirks":                  "# Subarchy hardware fix asus-expertbook-b9406 (ADR 0050)\n[ASUS ExpertBook B9406 Touchpad]\nMatchBus=i2c\nMatchUdevType=touchpad\nMatchVendor=0x093A\nMatchProduct=0x4F05\nMatchDMIModalias=dmi:*svnASUS*:pn*B9406*\nAttrEventCode=-ABS_MT_PRESSURE;-ABS_PRESSURE;\n",
		},
		applies: func(m Machine) bool { return m.Match("B9406") && isPantherLake(m) },
	},
	{
		Name: "asus-ptl-backlight", Summary: "ASUS Panther Lake laptops (ExpertBook B9406, Zenbook UX5406AA): backlight over DPCD",
		Source:  "install/hardware/asus/fix-asus-ptl-display-backlight.sh",
		Files:   map[string]string{"etc/limine-entry-tool.d/asus-ptl-display-backlight.conf": "# Subarchy hardware fix asus-ptl-backlight (ADR 0050)\nKERNEL_CMDLINE[default]+=\" xe.enable_dpcd_backlight=1\"\n"},
		applies: func(m Machine) bool { return (m.Match("B9406") || m.Match("UX5406AA")) && isPantherLake(m) },
	},
	{
		Name: "asus-proart-p14-speakers", Summary: "ASUS ProArt P14 (H7407BA) speaker firmware",
		Source:  "install/hardware/asus/fix-asus-proart-p14-speakers.sh",
		Note:    "asus-proart-p14-speaker-firmware is not in Arch's repositories; package it under packaging/aur before this fix can install it",
		applies: func(m Machine) bool { return m.Match("H7407BA") },
	},
	{
		Name: "framework16-qmk", Summary: "Framework Laptop 16: the input modules' QMK raw HID reachable by the logged-in user",
		Source: "install/hardware/framework16.sh, framework/qmk-hid.sh",
		Files: map[string]string{"etc/udev/rules.d/50-subarchy-framework16-qmk-hid.rules": "# Subarchy hardware fix framework16-qmk (ADR 0050)\n" +
			"SUBSYSTEM==\"hidraw\", ATTRS{idVendor}==\"32ac\", ATTRS{idProduct}==\"0012\", MODE=\"0660\", TAG+=\"uaccess\"\n"},
		Note:    "qmk-hid, the tool that talks to the modules, is not in Arch's repositories; package it under packaging/aur",
		applies: func(m Machine) bool { return matches(m, "framework16") },
	},
	{
		Name: "lenovo-yoga-pro7-bass", Summary: "Lenovo Yoga Pro 7 14IAH10: the bass speakers through the ALC287 Yoga 9 pin layout",
		Source:  "install/hardware/lenovo/fix-yoga-pro7-bass-speakers.sh",
		Files:   map[string]string{"etc/modprobe.d/lenovo-yoga-pro7-bass.conf": "# Subarchy hardware fix lenovo-yoga-pro7-bass (ADR 0050)\noptions snd-sof-intel-hda-generic hda_model=alc287-yoga9-bass-spk-pin\n"},
		applies: func(m Machine) bool { return m.Match("Yoga Pro 7 14IAH10") },
	},
	{
		Name: "dell-xps13-ptl-speakers", Summary: "Dell XPS 13 DX13260 (Panther Lake) speaker firmware",
		Source:  "install/hardware/dell-xps13-ptl-speaker-firmware.sh",
		Note:    "linux-firmware-cirrus-dx13260 is not in Arch's repositories; package it under packaging/aur before this fix can install it",
		applies: func(m Machine) bool { return m.Match("DX13260") && isPantherLake(m) },
	},
	{
		Name: "dell-xps13-sidecar-amps", Summary: "Dell XPS 13 DX13260 with the sidecar amplifiers (SKU 0E53)",
		Source:  "install/hardware/dell-xps13-sidecar-amps.sh",
		Note:    "dell-xps13-sidecar-amps and its apply step are not in Arch's repositories; package them under packaging/aur first",
		applies: func(m Machine) bool { return m.Match("DX13260") && strings.EqualFold(m.Facts.ProductSKU, "0E53") },
	},
	{
		Name: "dell-xps-haptic-touchpad", Summary: "Dell XPS haptic touchpad driver",
		Source:  "install/hardware/dell-xps-touchpad-haptics.sh",
		Note:    "dell-xps-touchpad-haptics is not in Arch's repositories; package it under packaging/aur before this fix can install it",
		applies: func(m Machine) bool { return matches(m, "dell-xps-haptic-touchpad") },
	},
	{
		Name: "tuxedo-keyboard", Summary: "TUXEDO and Slimbook laptops: the Clevo WMI module out of the way of the TUXEDO drivers",
		Source: "install/hardware/fix-tuxedo-backlight.sh",
		Files:  map[string]string{"etc/modprobe.d/blacklist-clevo-xsm-wmi.conf": "# Subarchy hardware fix tuxedo-keyboard (ADR 0050)\nblacklist clevo_xsm_wmi\n"},
		Note:   "tuxedo-drivers-nocompatcheck-dkms is not in Arch's repositories; package it under packaging/aur before the keyboard backlight works",
		applies: func(m Machine) bool {
			v := strings.ToLower(m.Facts.SysVendor)
			return strings.Contains(v, "tuxedo") || strings.Contains(v, "slimbook")
		},
	},
	// Apple (Intel Macs, T2) and Microsoft Surface (issue #105).
	{
		Name: "apple-t2", Summary: "Macs with the T2 chip: the kernel, firmware and fan daemon of the t2linux project; boot modules and command line",
		Source: "install/hardware/apple/fix-t2.sh",
		Files: map[string]string{
			"etc/modules-load.d/apple-t2.conf":          "# Subarchy hardware fix apple-t2 (ADR 0050)\nt2bce_vhci\nhci_bcm4377\n",
			"etc/mkinitcpio.conf.d/apple-t2.conf":       "# Subarchy hardware fix apple-t2 (ADR 0050)\nMODULES+=(t2bce_vhci usbhid hid_apple hid_generic xhci_pci xhci_hcd)\n",
			"etc/limine-entry-tool.d/apple-t2-mac.conf": "# Subarchy hardware fix apple-t2 (ADR 0050)\nKERNEL_CMDLINE[default]+=\" intel_iommu=on iommu=pt pm_async=off mem_sleep_default=deep\"\n",
		},
		Note:    "linux-t2, apple-t2-audio-config, apple-bcm-firmware-fetcher and t2fanrd come from the t2linux repository, not Arch's; add that repository or package them before this fix can install them",
		applies: func(m Machine) bool { return m.hasPCI(vendorApple, appleT2Bridges) },
	},
	{
		Name: "apple-brcmfmac-supplicant", Summary: "Macs with Broadcom Wi-Fi: the WPA handshake in software (brcmfmac feature_disable)",
		Source: "install/hardware/apple/fix-brcmfmac-supplicant.sh",
		Files:  map[string]string{"etc/modprobe.d/brcmfmac.conf": "# Subarchy hardware fix apple-brcmfmac-supplicant (ADR 0050)\noptions brcmfmac feature_disable=0x82000\n"},
		applies: func(m Machine) bool {
			return m.hasPCI(vendorApple, appleT2Bridges) ||
				(strings.HasPrefix(m.Facts.SysVendor, "Apple") && m.hasPCI(vendorBroadcom, appleBroadcomRadios))
		},
	},
	{
		Name: "apple-spi-keyboard", Summary: "MacBooks with the SPI keyboard and trackpad (2015 to 2017): the applespi driver in the initramfs",
		Source:  "install/hardware/apple/fix-spi-keyboard.sh",
		Files:   map[string]string{"etc/mkinitcpio.conf.d/macbook-spi.conf": "# Subarchy hardware fix apple-spi-keyboard (ADR 0050)\nMODULES+=(applespi intel_lpss_pci spi_pxa2xx_platform)\n"},
		Note:    "macbook12-spi-driver-dkms is not in Arch's repositories; package it under packaging/aur. The MacBook8,1 needs spi_pxa2xx_pci instead of intel_lpss_pci",
		applies: func(m Machine) bool { return appleSPIKeyboard.MatchString(m.Facts.ProductName) },
	},
	{
		Name: "apple-nvme-suspend", Summary: "MacBooks whose NVMe drive must stay out of D3cold for suspend to work",
		Source:   "install/hardware/apple/fix-suspend-nvme.sh",
		Services: []string{"subarchy-apple-nvme-suspend"},
		Files:    map[string]string{"etc/systemd/system/subarchy-apple-nvme-suspend.service": "# Subarchy hardware fix apple-nvme-suspend (ADR 0050)\n[Unit]\nDescription=Keep the MacBook's NVMe drive out of D3cold so suspend works\nConditionPathExists=/sys/bus/pci/devices/0000:01:00.0/d3cold_allowed\n\n[Service]\nType=oneshot\nExecStart=/bin/sh -c 'echo 0 > /sys/bus/pci/devices/0000:01:00.0/d3cold_allowed'\n\n[Install]\nWantedBy=multi-user.target\n"},
		applies:  func(m Machine) bool { return appleNVMeSuspend.MatchString(m.Facts.ProductName) },
	},
	{
		Name: "surface-firmware", Summary: "Microsoft Surface: the Marvell Wi-Fi firmware",
		Source: "install/hardware/surface.sh", Packages: []string{"linux-firmware-marvell"},
		applies: func(m Machine) bool { return matches(m, "surface") && m.Facts.Arch == "x86_64" },
	},
	{
		Name: "surface-keyboard", Summary: "Microsoft Surface: the aggregator and keyboard modules in the initramfs",
		Source:  "install/hardware/fix-surface-keyboard.sh",
		Files:   map[string]string{"etc/mkinitcpio.conf.d/surface-keyboard.conf": "# Subarchy hardware fix surface-keyboard (ADR 0050)\nMODULES+=(surface_aggregator surface_aggregator_registry surface_aggregator_hub surface_hid_core surface_hid surface_kbd intel_lpss_pci 8250_dw)\n"},
		Note:    "the pin-control module of the machine (pinctrl_*) must be added to this list by hand; Omarchy reads it from the running system, which the installer cannot",
		applies: func(m Machine) bool { return matches(m, "surface") && m.Facts.Arch == "x86_64" },
	},
	// Peripherals (issue #106).
	{
		Name: "broadcom-wl", Summary: "Broadcom BCM4360 and BCM4331 Wi-Fi through the wl driver (DKMS)",
		Source:   "install/hardware/fix-bcm43xx.sh",
		Packages: []string{"broadcom-wl-dkms", "linux-zen-headers", "linux-lts-headers"},
		applies:  func(m Machine) bool { return m.hasPCI(vendorBroadcom, broadcomWLRadios) },
	},
	{
		Name: "synaptics-intertouch", Summary: "Synaptics touchpads over RMI4 instead of PS/2 (psmouse synaptics_intertouch=1)",
		Source: "install/hardware/fix-synaptic-touchpad.sh",
		Files:  map[string]string{"etc/modprobe.d/psmouse-synaptics.conf": "# Subarchy hardware fix synaptics-intertouch (ADR 0050)\noptions psmouse synaptics_intertouch=1\n"},
		applies: func(m Machine) bool {
			return strings.Contains(strings.ToLower(m.Facts.Touchpad), "synaptics")
		},
	},
	{
		Name: "elgato-camlink-4k", Summary: "Elgato Cam Link 4K as a loopback camera (v4l2loopback, exclusive caps)",
		Source:   "install/hardware/fix-elgato-camlink-4k.sh",
		Packages: []string{"v4l2loopback-dkms", "v4l2loopback-utils", "linux-zen-headers", "linux-lts-headers"},
		Files: map[string]string{
			"etc/modprobe.d/v4l2loopback-exclusive-caps.conf": "# Subarchy hardware fix elgato-camlink-4k (ADR 0050)\noptions v4l2loopback exclusive_caps=1\n",
		},
		Note: "the relay that feeds the capture into the loopback device (v4l2-relayd and its unit) is not in Arch's repositories and is not ported yet",
		applies: func(m Machine) bool {
			for _, p := range m.Facts.USBProducts {
				if strings.Contains(p, "cam link 4k") {
					return true
				}
			}
			return false
		},
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
