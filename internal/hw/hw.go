// Package hw detects the machine's hardware from sysfs and /proc/cpuinfo
// and picks the packages it needs (ADR 0005, 0006, 0050): CPU microcode,
// the linux-firmware split packages, audio firmware and GPU drivers.
//
// Devices are matched by class as well as vendor, so an Intel chipset alone
// does not pull in Intel Wi-Fi firmware. A network or display device from a
// vendor not in the tables falls back to the full linux-firmware package.
package hw

import (
	"fmt"
	"os"
	"path/filepath"
	"sort"
	"strconv"
	"strings"
)

// Device is one PCI or USB device.
type Device struct {
	Bus    string // "pci" or "usb"
	Vendor uint16
	Device uint16
	Class  uint32 // PCI: 0xCCSSPP; USB: device class in the low byte
}

// Kind classifies a device for package selection.
func (d Device) Kind() string {
	if d.Bus == "usb" {
		if d.Class == 0xe0 || btUSBVendors[d.Vendor] {
			return "bluetooth"
		}
		return ""
	}
	switch d.Class >> 16 {
	case 0x02:
		return "network"
	case 0x03:
		return "display"
	case 0x04:
		if (d.Class>>8)&0xff == 0x01 || (d.Class>>8)&0xff == 0x03 {
			return "audio"
		}
	case 0x0d:
		return "wireless"
	}
	return ""
}

// Firmware packages by vendor for network, wireless and Bluetooth devices.
var radioFirmware = map[uint16]string{
	0x8086: "linux-firmware-intel", 0x8087: "linux-firmware-intel",
	0x10ec: "linux-firmware-realtek", 0x0bda: "linux-firmware-realtek",
	0x14c3: "linux-firmware-mediatek", 0x0e8d: "linux-firmware-mediatek",
	0x14e4: "linux-firmware-broadcom", 0x0a5c: "linux-firmware-broadcom",
	0x168c: "linux-firmware-atheros", 0x17cb: "linux-firmware-atheros", 0x0cf3: "linux-firmware-atheros",
	0x11ab: "linux-firmware-marvell", 0x1b4b: "linux-firmware-marvell",
}

// USB vendors whose devices on laptops are Bluetooth radios even when the
// device class is vendor-specific.
var btUSBVendors = map[uint16]bool{0x8087: true, 0x0cf3: true}

const (
	vendorIntel       = 0x8086
	vendorAMD         = 0x1002
	vendorNVIDIA      = 0x10de
	vendorDisplayLink = 0x17e9 // USB graphics adapters (the evdi driver)
)

// NVIDIA driver generations by PCI device ID (ADR 0006).
const (
	nvidiaTuring  = 0x1e00 // RTX 20 / GTX 16 and newer: nvidia-open
	nvidiaMaxwell = 0x1340 // GTX 900 / 10 series: the 580xx branch
)

// Machine is what detection found.
type Machine struct {
	CPUVendor string // GenuineIntel, AuthenticAMD
	Devices   []Device
	VM        string // hypervisor vendor from DMI, empty on hardware
	CirrusAmp bool   // Cirrus Logic speaker amplifiers (ACPI CSC3551)
	Facts     Facts  // what the matchers read (match.go)
}

// Hybrid reports an integrated GPU together with an NVIDIA GPU.
func (m Machine) Hybrid() bool {
	var integrated, nvidia bool
	for _, d := range m.Devices {
		if d.Kind() != "display" {
			continue
		}
		switch d.Vendor {
		case vendorIntel, vendorAMD:
			integrated = true
		case vendorNVIDIA:
			nvidia = true
		}
	}
	return integrated && nvidia
}

// DisplayLink reports a DisplayLink USB graphics adapter (sputnik's dock).
func (m Machine) DisplayLink() bool {
	for _, d := range m.Devices {
		if d.Bus == "usb" && d.Vendor == vendorDisplayLink {
			return true
		}
	}
	return false
}

// Selection is the package set, the system services the installer enables
// for it, and the reasons.
type Selection struct {
	Packages []string
	Services []string
	Notes    []string
}

// Select picks packages for the machine.
func Select(m Machine) Selection {
	set := map[string]bool{}
	var notes []string
	add := func(pkgs ...string) {
		for _, p := range pkgs {
			set[p] = true
		}
	}
	switch m.CPUVendor {
	case "GenuineIntel":
		add("intel-ucode", "thermald") // thermald: ADR 0021
	case "AuthenticAMD":
		add("amd-ucode")
	}
	fullFirmware := false
	for _, d := range m.Devices {
		switch d.Kind() {
		case "network", "wireless", "bluetooth":
			if fw, ok := radioFirmware[d.Vendor]; ok {
				add(fw)
			} else if d.Kind() != "bluetooth" && !virtualVendor(d.Vendor) {
				fullFirmware = true
				notes = append(notes, fmt.Sprintf("unknown %s device %04x:%04x: installing all of linux-firmware", d.Kind(), d.Vendor, d.Device))
			}
		case "audio":
			if d.Vendor == vendorIntel {
				add("sof-firmware")
			}
		case "display":
			switch {
			case d.Vendor == vendorIntel:
				add("linux-firmware-intel", "vulkan-intel", "intel-media-driver")
			case d.Vendor == vendorAMD:
				add("linux-firmware-amdgpu", "vulkan-radeon")
			case d.Vendor == vendorNVIDIA && d.Device >= nvidiaTuring:
				add("linux-firmware-nvidia", "nvidia-open-dkms", "nvidia-utils", "libva-nvidia-driver",
					"linux-zen-headers", "linux-lts-headers")
			case d.Vendor == vendorNVIDIA && d.Device >= nvidiaMaxwell:
				add("linux-firmware-nvidia")
				notes = append(notes, fmt.Sprintf("NVIDIA %04x needs the 580xx driver branch, which is not packaged yet; using nouveau", d.Device))
			case d.Vendor == vendorNVIDIA:
				add("linux-firmware-nvidia")
				notes = append(notes, fmt.Sprintf("NVIDIA %04x predates the supported drivers; using nouveau", d.Device))
			case !virtualVendor(d.Vendor):
				fullFirmware = true
				notes = append(notes, fmt.Sprintf("unknown display device %04x:%04x: installing all of linux-firmware", d.Vendor, d.Device))
			}
		}
	}
	if m.CirrusAmp {
		add("linux-firmware-cirrus")
	}
	var services []string
	if m.DisplayLink() {
		// The evdi module is built by DKMS, so the kernel headers come too.
		add("evdi-dkms", "displaylink", "linux-zen-headers", "linux-lts-headers")
		services = append(services, "displaylink")
		notes = append(notes, "DisplayLink adapter: evdi (DKMS) and the DisplayLink manager; displaylink.service is enabled")
	}
	if fullFirmware {
		for p := range set {
			if strings.HasPrefix(p, "linux-firmware-") {
				delete(set, p)
			}
		}
		add("linux-firmware")
	}
	if m.Hybrid() {
		notes = append(notes, "hybrid graphics: the integrated GPU draws the desktop; NVIDIA runs apps on request (ADR 0006)")
	}
	if m.VM != "" {
		notes = append(notes, "virtual machine: "+m.VM)
	}
	pkgs := make([]string, 0, len(set))
	for p := range set {
		pkgs = append(pkgs, p)
	}
	sort.Strings(pkgs)
	return Selection{Packages: pkgs, Services: services, Notes: notes}
}

// virtualVendor reports emulated devices that need no firmware.
func virtualVendor(v uint16) bool {
	switch v {
	case 0x1af4, 0x1b36, 0x1234, 0x15ad, 0x80ee, 0x1414: // virtio, QEMU, Bochs, VMware, VirtualBox, Hyper-V
		return true
	}
	return false
}

// Detect reads the machine from a root directory ("/" normally).
func Detect(root string) (Machine, error) {
	var m Machine
	cpuinfo, err := os.ReadFile(filepath.Join(root, "proc/cpuinfo"))
	if err != nil {
		return m, fmt.Errorf("cpuinfo: %w", err)
	}
	for _, line := range strings.Split(string(cpuinfo), "\n") {
		if k, v, ok := strings.Cut(line, ":"); ok && strings.TrimSpace(k) == "vendor_id" {
			m.CPUVendor = strings.TrimSpace(v)
			break
		}
	}
	pci, _ := filepath.Glob(filepath.Join(root, "sys/bus/pci/devices/*"))
	for _, dir := range pci {
		d := Device{Bus: "pci"}
		v, err1 := readHex(filepath.Join(dir, "vendor"))
		id, err2 := readHex(filepath.Join(dir, "device"))
		class, err3 := readHex(filepath.Join(dir, "class"))
		if err1 != nil || err2 != nil || err3 != nil {
			continue
		}
		d.Vendor, d.Device, d.Class = uint16(v), uint16(id), uint32(class)
		m.Devices = append(m.Devices, d)
	}
	usb, _ := filepath.Glob(filepath.Join(root, "sys/bus/usb/devices/*"))
	for _, dir := range usb {
		v, err1 := readHex(filepath.Join(dir, "idVendor"))
		id, err2 := readHex(filepath.Join(dir, "idProduct"))
		if err1 != nil || err2 != nil {
			continue
		}
		class, _ := readHex(filepath.Join(dir, "bDeviceClass"))
		m.Devices = append(m.Devices, Device{Bus: "usb", Vendor: uint16(v), Device: uint16(id), Class: uint32(class)})
	}
	if vendor, err := os.ReadFile(filepath.Join(root, "sys/class/dmi/id/sys_vendor")); err == nil {
		product, _ := os.ReadFile(filepath.Join(root, "sys/class/dmi/id/product_name"))
		switch v := strings.TrimSpace(string(vendor)); {
		case v == "QEMU", v == "VMware, Inc.", v == "innotek GmbH", v == "Xen":
			m.VM = v
		case v == "Microsoft Corporation" && strings.TrimSpace(string(product)) == "Virtual Machine":
			m.VM = "Hyper-V" // Surface laptops share the vendor string
		}
	}
	if amps, _ := filepath.Glob(filepath.Join(root, "sys/bus/acpi/devices/CSC3551*")); len(amps) > 0 {
		m.CirrusAmp = true
	}
	m.Facts = readFacts(root)
	return m, nil
}

func readHex(path string) (uint64, error) {
	b, err := os.ReadFile(path)
	if err != nil {
		return 0, err
	}
	return strconv.ParseUint(strings.TrimPrefix(strings.TrimSpace(string(b)), "0x"), 16, 32)
}
