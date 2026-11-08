package hw

import (
	"fmt"
	"os"
	"path/filepath"
	"regexp"
	"slices"
	"strings"
	"testing"
)

type fixture struct {
	cpu     string
	pci     [][3]uint32 // vendor, device, class
	usb     [][3]uint32 // vendor, product, class
	vendor  string
	product string
	acpi    []string
}

func (f fixture) write(t *testing.T) string {
	t.Helper()
	root := t.TempDir()
	put := func(path, content string) {
		t.Helper()
		p := filepath.Join(root, path)
		if err := os.MkdirAll(filepath.Dir(p), 0o755); err != nil {
			t.Fatal(err)
		}
		if err := os.WriteFile(p, []byte(content), 0o644); err != nil {
			t.Fatal(err)
		}
	}
	put("proc/cpuinfo", "processor\t: 0\nvendor_id\t: "+f.cpu+"\nmodel name\t: x\n")
	for i, d := range f.pci {
		dir := fmt.Sprintf("sys/bus/pci/devices/0000:%02x:00.0/", i)
		put(dir+"vendor", fmt.Sprintf("0x%04x\n", d[0]))
		put(dir+"device", fmt.Sprintf("0x%04x\n", d[1]))
		put(dir+"class", fmt.Sprintf("0x%06x\n", d[2]))
	}
	for i, d := range f.usb {
		dir := fmt.Sprintf("sys/bus/usb/devices/3-%d/", i+1)
		put(dir+"idVendor", fmt.Sprintf("%04x\n", d[0]))
		put(dir+"idProduct", fmt.Sprintf("%04x\n", d[1]))
		put(dir+"bDeviceClass", fmt.Sprintf("%02x\n", d[2]))
	}
	if f.vendor != "" {
		put("sys/class/dmi/id/sys_vendor", f.vendor+"\n")
		put("sys/class/dmi/id/product_name", f.product+"\n")
	}
	for _, a := range f.acpi {
		put("sys/bus/acpi/devices/"+a+"/hid", a+"\n")
	}
	return root
}

// sputnik: Intel Alder Lake laptop with RTX 3050 Ti, read 2026-11-07.
var sputnik = fixture{
	cpu: "GenuineIntel",
	pci: [][3]uint32{
		{0x8086, 0x4641, 0x060000}, {0x8086, 0x46a6, 0x030000}, {0x8086, 0x461d, 0x118000},
		{0x8086, 0x51ed, 0x0c0330}, {0x8086, 0x51f0, 0x028000}, {0x8086, 0x51c8, 0x040380},
		{0x10de, 0x25a0, 0x030200}, {0xc0a9, 0x5407, 0x010802}, {0x10ec, 0x5765, 0x010802},
		{0x10ec, 0x5260, 0xff0000},
	},
	usb: [][3]uint32{{0x8087, 0x0033, 0xe0}, {0x0c45, 0x6732, 0xef}, {0x27c6, 0x63ac, 0xef}, {0x1d6b, 0x0002, 0x09}},
}

func TestSelectDisplayLink(t *testing.T) {
	dock := fixture{cpu: "GenuineIntel", pci: [][3]uint32{{0x8086, 0x46a6, 0x030000}}, usb: [][3]uint32{{0x17e9, 0x4301, 0x00}}}
	m, err := Detect(dock.write(t))
	if err != nil {
		t.Fatal(err)
	}
	if !m.DisplayLink() {
		t.Fatal("a 17e9 USB device is a DisplayLink adapter")
	}
	sel := Select(m)
	for _, want := range []string{"evdi-dkms", "displaylink", "linux-zen-headers"} {
		if !slices.Contains(sel.Packages, want) {
			t.Errorf("packages %v lack %s", sel.Packages, want)
		}
	}
	if !slices.Equal(sel.Services, []string{"displaylink"}) {
		t.Errorf("services = %v", sel.Services)
	}
	plain := fixture{cpu: "GenuineIntel", usb: [][3]uint32{{0x046d, 0xc52b, 0x00}}}
	m2, _ := Detect(plain.write(t))
	if sel2 := Select(m2); m2.DisplayLink() || len(sel2.Services) != 0 || slices.Contains(sel2.Packages, "displaylink") {
		t.Errorf("a Logitech receiver is not DisplayLink: %+v", sel2)
	}
}

func TestSelect(t *testing.T) {
	tests := []struct {
		name   string
		f      fixture
		want   []string
		hybrid bool
		note   string
	}{
		{
			name: "sputnik", f: sputnik, hybrid: true, note: "hybrid graphics",
			want: []string{"intel-media-driver", "intel-ucode", "libva-nvidia-driver", "linux-firmware-intel",
				"linux-firmware-nvidia", "linux-lts-headers", "linux-zen-headers", "nvidia-open-dkms", "nvidia-utils",
				"sof-firmware", "thermald", "vulkan-intel"},
		},
		{
			name: "AMD laptop with MediaTek Wi-Fi",
			f: fixture{cpu: "AuthenticAMD", pci: [][3]uint32{
				{0x1022, 0x14e8, 0x060000}, {0x1002, 0x15bf, 0x030000}, {0x14c3, 0x0616, 0x028000}, {0x1022, 0x15e3, 0x040300}}},
			want: []string{"amd-ucode", "linux-firmware-amdgpu", "linux-firmware-mediatek", "vulkan-radeon"},
		},
		{
			name: "QEMU guest",
			f: fixture{cpu: "GenuineIntel", vendor: "QEMU", product: "Standard PC (Q35 + ICH9, 2009)", pci: [][3]uint32{
				{0x8086, 0x29c0, 0x060000}, {0x1234, 0x1111, 0x030000}, {0x1af4, 0x1041, 0x020000}, {0x8086, 0x2922, 0x010601}}},
			want: []string{"intel-ucode", "thermald"}, note: "virtual machine: QEMU",
		},
		{
			name: "unknown network card falls back to all firmware",
			f: fixture{cpu: "GenuineIntel", pci: [][3]uint32{
				{0x8086, 0x46a6, 0x030000}, {0x1d6a, 0x07b1, 0x020000}}},
			want: []string{"intel-media-driver", "intel-ucode", "linux-firmware", "thermald", "vulkan-intel"},
			note: "unknown network device 1d6a:07b1",
		},
		{
			name: "Pascal NVIDIA desktop",
			f:    fixture{cpu: "AuthenticAMD", pci: [][3]uint32{{0x10de, 0x1b80, 0x030000}, {0x10ec, 0x8168, 0x020000}}},
			want: []string{"amd-ucode", "linux-firmware-nvidia", "linux-firmware-realtek"},
			note: "580xx",
		},
		{
			name: "very old NVIDIA",
			f:    fixture{cpu: "GenuineIntel", pci: [][3]uint32{{0x10de, 0x0a20, 0x030000}}},
			want: []string{"intel-ucode", "linux-firmware-nvidia", "thermald"}, note: "predates",
		},
		{
			name: "Surface is not a VM; Cirrus amps",
			f: fixture{cpu: "GenuineIntel", vendor: "Microsoft Corporation", product: "Surface Laptop 5",
				pci: [][3]uint32{{0x8086, 0xa7a0, 0x030000}}, acpi: []string{"CSC3551:00"}},
			want: []string{"intel-media-driver", "intel-ucode", "linux-firmware-cirrus", "linux-firmware-intel", "thermald", "vulkan-intel"},
		},
		{
			name: "Hyper-V guest",
			f:    fixture{cpu: "AuthenticAMD", vendor: "Microsoft Corporation", product: "Virtual Machine", pci: [][3]uint32{{0x1414, 0x5353, 0x030000}}},
			want: []string{"amd-ucode"}, note: "virtual machine: Hyper-V",
		},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			m, err := Detect(tt.f.write(t))
			if err != nil {
				t.Fatal(err)
			}
			sel := Select(m)
			if !slices.Equal(sel.Packages, tt.want) {
				t.Errorf("packages\n got %q\nwant %q", sel.Packages, tt.want)
			}
			if m.Hybrid() != tt.hybrid {
				t.Errorf("hybrid = %v", m.Hybrid())
			}
			if tt.note != "" && !strings.Contains(strings.Join(sel.Notes, "\n"), tt.note) {
				t.Errorf("notes %q lack %q", sel.Notes, tt.note)
			}
		})
	}
}

func TestDetectErrors(t *testing.T) {
	if _, err := Detect(t.TempDir()); err == nil {
		t.Error("want error without cpuinfo")
	}
	root := fixture{cpu: "GenuineIntel"}.write(t)
	bad := filepath.Join(root, "sys/bus/pci/devices/0000:09:00.0")
	if err := os.MkdirAll(bad, 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(bad, "vendor"), []byte("zz\n"), 0o644); err != nil {
		t.Fatal(err)
	}
	m, err := Detect(root)
	if err != nil || len(m.Devices) != 0 {
		t.Errorf("unreadable device kept: %+v, %v", m.Devices, err)
	}
}

// Every package name Select adds is in the catalog, so the install image's
// offline repository carries whatever Select may pick.
func TestCatalogCoversSelect(t *testing.T) {
	src, err := os.ReadFile("hw.go")
	if err != nil {
		t.Fatal(err)
	}
	body := string(src)
	start := strings.Index(body, "func Select(")
	if start < 0 {
		t.Fatal("no Select")
	}
	body = body[start:]
	catalog := map[string]bool{}
	for _, p := range Catalog() {
		catalog[p] = true
	}
	for _, m := range regexp.MustCompile(`add\(([^)]*)\)`).FindAllStringSubmatch(body, -1) {
		for _, q := range regexp.MustCompile(`"([^"]+)"`).FindAllStringSubmatch(m[1], -1) {
			if !catalog[q[1]] {
				t.Errorf("Select adds %q, which the catalog lacks", q[1])
			}
		}
	}
	for _, fw := range radioFirmware {
		if !catalog[fw] {
			t.Errorf("radio firmware %q missing from the catalog", fw)
		}
	}
	if len(Catalog()) < 20 {
		t.Errorf("catalog too short: %d", len(Catalog()))
	}
}
