package setup

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func TestValidUsername(t *testing.T) {
	for name, ok := range map[string]bool{
		"pat": true, "_svc": true, "a-b_c9": true,
		"": false, "Pat": false, "9lives": false, "root": false, "sddm": false,
		strings.Repeat("a", 33): false, "a b": false,
	} {
		if err := ValidUsername(name); (err == nil) != ok {
			t.Errorf("ValidUsername(%q) = %v", name, err)
		}
	}
}

func TestValidHostname(t *testing.T) {
	for name, ok := range map[string]bool{
		"sputnik": true, "a": true, "sub-1": true,
		"": false, "-a": false, "a-": false, "Sputnik": false, "a.b": false, strings.Repeat("a", 64): false,
	} {
		if err := ValidHostname(name); (err == nil) != ok {
			t.Errorf("ValidHostname(%q) = %v", name, err)
		}
	}
}

func TestValidSecret(t *testing.T) {
	tests := []struct {
		s, again string
		ok       bool
	}{
		{"correct horse", "correct horse", true},
		{"short", "short", false},
		{"long enough", "long enougH", false},
		{"line\nbreak!", "line\nbreak!", false},
	}
	for _, tt := range tests {
		if err := ValidSecret(tt.s, tt.again, 8); (err == nil) != tt.ok {
			t.Errorf("ValidSecret(%q) = %v", tt.s, err)
		}
	}
}

func TestValidTimezoneAndKeymap(t *testing.T) {
	zi := t.TempDir()
	if err := os.MkdirAll(filepath.Join(zi, "America"), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(zi, "America", "Chicago"), nil, 0o644); err != nil {
		t.Fatal(err)
	}
	for tz, ok := range map[string]bool{"America/Chicago": true, "America": false, "../etc": false, "Mars/Base": false, "": false} {
		if err := ValidTimezone(zi, tz); (err == nil) != ok {
			t.Errorf("ValidTimezone(%q) = %v", tz, err)
		}
	}
	km := t.TempDir()
	if err := os.MkdirAll(filepath.Join(km, "i386", "qwerty"), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(km, "i386", "qwerty", "us.map.gz"), nil, 0o644); err != nil {
		t.Fatal(err)
	}
	for name, ok := range map[string]bool{"us": true, "de": false, "": false, "../us": false} {
		if err := ValidKeymap(km, name); (err == nil) != ok {
			t.Errorf("ValidKeymap(%q) = %v", name, err)
		}
	}
}

const lsblk = `{"blockdevices":[
 {"name":"zram0","path":"/dev/zram0","size":33291239424,"type":"disk","model":null,"tran":null,"ro":false},
 {"name":"sr0","path":"/dev/sr0","size":1646600192,"type":"rom","model":"QEMU DVD-ROM","tran":"sata","ro":false},
 {"name":"nvme1n1","path":"/dev/nvme1n1","size":1000204886016,"type":"disk","model":"CT1000P5PSSD8","tran":"nvme","ro":false},
 {"name":"nvme0n1","path":"/dev/nvme0n1","size":1000204886016,"type":"disk","model":"SPCC M.2 PCIe SSD ","tran":"nvme","ro":false},
 {"name":"sda","path":"/dev/sda","size":64000000000,"type":"disk","model":"USB Stick","tran":"usb","ro":false},
 {"name":"sdb","path":"/dev/sdb","size":8000000000,"type":"disk","model":"tiny","tran":"usb","ro":false},
 {"name":"sdc","path":"/dev/sdc","size":64000000000,"type":"disk","model":"locked","tran":"usb","ro":true}
]}`

func TestDisks(t *testing.T) {
	disks, err := Disks([]byte(lsblk), "/dev/sda")
	if err != nil {
		t.Fatal(err)
	}
	var paths []string
	for _, d := range disks {
		paths = append(paths, d.Path)
	}
	if strings.Join(paths, " ") != "/dev/nvme0n1 /dev/nvme1n1" {
		t.Errorf("disks = %v", paths)
	}
	if got := disks[0].String(); got != "/dev/nvme0n1  1.0 TB  SPCC M.2 PCIe SSD, nvme" {
		t.Errorf("String = %q", got)
	}
	if _, err := Disks([]byte("{"), ""); err == nil {
		t.Error("want error for bad JSON")
	}
	if HumanSize(25769803776) != "26 GB" {
		t.Errorf("HumanSize = %q", HumanSize(25769803776))
	}
	if (Disk{Path: "/dev/vda", Size: 1}).String() != "/dev/vda  0 GB  unknown model" {
		t.Errorf("no-model String = %q", (Disk{Path: "/dev/vda", Size: 1}).String())
	}
}

func TestPartClosed(t *testing.T) {
	for fs, want := range map[string]string{"vfat": "", "ext4": "", "ntfs": "", "": "nothing to open", "swap": "holds no files",
		"crypto_LUKS": "left locked", "BitLocker": "left locked", "LVM2_member": "part of an LVM volume group",
		"linux_raid_member": "part of a RAID set", "zfs_member": "part of a ZFS pool"} {
		if got := (Part{FSType: fs}).Closed(); got != want {
			t.Errorf("Closed(%q) = %q, want %q", fs, got, want)
		}
	}
}

func TestWriteConfig(t *testing.T) {
	dir := filepath.Join(t.TempDir(), "setup")
	a := Answers{
		Disk: "/dev/vda", Hostname: "box", Username: "pat", Password: "pw-123456", Passphrase: "disk-secret",
		Timezone: "UTC", Keymap: "us", XKBLayout: "us", Repo: "file:///opt/subarchy/repo", CmdlineExtra: "console=ttyS0",
	}
	path, err := a.WriteConfig(dir)
	if err != nil {
		t.Fatal(err)
	}
	conf, _ := os.ReadFile(path)
	for _, want := range []string{"DISK=/dev/vda", "USERNAME=pat", "SUBARCHY_REPO=file:///opt/subarchy/repo",
		"USER_PASSWORD_FILE=" + filepath.Join(dir, "user-password"), "KERNEL_CMDLINE_EXTRA=console=ttyS0"} {
		if !strings.Contains(string(conf), want+"\n") {
			t.Errorf("config lacks %q:\n%s", want, conf)
		}
	}
	if strings.Contains(string(conf), "pw-123456") || strings.Contains(string(conf), "disk-secret") {
		t.Error("config contains a secret")
	}
	for _, name := range []string{"user-password", "luks-passphrase", "install.conf"} {
		info, err := os.Stat(filepath.Join(dir, name))
		if err != nil || info.Mode().Perm() != 0o600 {
			t.Errorf("%s: mode %v, %v", name, info.Mode().Perm(), err)
		}
	}
	if strings.Contains(string(conf), "WIFI_") {
		t.Errorf("config names a Wi-Fi network nobody chose:\n%s", conf)
	}
}

func TestWriteConfigWiFi(t *testing.T) {
	dir := filepath.Join(t.TempDir(), "setup")
	a := Answers{Disk: "/dev/vda", Hostname: "box", Username: "pat", Password: "pw-123456", Passphrase: "pw-123456",
		Timezone: "UTC", Keymap: "us", XKBLayout: "us", Repo: "file:///opt/subarchy/repo",
		WiFiSSID: "Cafe Wi-Fi", WiFiPSK: "wifi-secret-1"}
	path, err := a.WriteConfig(dir)
	if err != nil {
		t.Fatal(err)
	}
	conf, _ := os.ReadFile(path)
	for _, want := range []string{"WIFI_SSID=Cafe Wi-Fi", "WIFI_PSK_FILE=" + filepath.Join(dir, "wifi-psk")} {
		if !strings.Contains(string(conf), want+"\n") {
			t.Errorf("config lacks %q:\n%s", want, conf)
		}
	}
	if strings.Contains(string(conf), "wifi-secret-1") {
		t.Error("config contains the Wi-Fi passphrase")
	}
	psk, err := os.ReadFile(filepath.Join(dir, "wifi-psk"))
	info, _ := os.Stat(filepath.Join(dir, "wifi-psk"))
	if err != nil || string(psk) != "wifi-secret-1\n" || info.Mode().Perm() != 0o600 {
		t.Errorf("wifi-psk: %q, %v", psk, err)
	}
	// An open network has a name and no passphrase file.
	a.WiFiPSK = ""
	dir = filepath.Join(t.TempDir(), "open")
	path, _ = a.WriteConfig(dir)
	conf, _ = os.ReadFile(path)
	if !strings.Contains(string(conf), "WIFI_SSID=Cafe Wi-Fi\n") || strings.Contains(string(conf), "WIFI_PSK_FILE") {
		t.Errorf("open network config:\n%s", conf)
	}
	if _, err := os.Stat(filepath.Join(dir, "wifi-psk")); err == nil {
		t.Error("wrote a passphrase file for an open network")
	}
}

func TestValidWiFi(t *testing.T) {
	for _, ok := range []string{"12345678", strings.Repeat("x", 63), "pass word!", strings.Repeat("aF", 32)} {
		if err := ValidWiFiPassphrase(ok); err != nil {
			t.Errorf("%q refused: %v", ok, err)
		}
	}
	for _, bad := range []string{"short", strings.Repeat("x", 64), "pässwort1", "tab\there1"} {
		if ValidWiFiPassphrase(bad) == nil {
			t.Errorf("%q accepted", bad)
		}
	}
	for ssid, want := range map[string]bool{"Home": true, " spaced ": true, "Кафе": true, "": false,
		strings.Repeat("n", 33): false, "line\nbreak": false, "\x1b[2Jclear": false, "csi\u009b2J": false, "bad\xffbyte": false} {
		if ValidSSID(ssid) != want {
			t.Errorf("ValidSSID(%q) = %v", ssid, !want)
		}
	}
}
