// Package setup holds the questions the guided installer asks (ADR 0049),
// the rules their answers must meet, and the config file it writes for
// install/subarchy-install. Rules borrowed from Omarchy's
// install/provisioning/setup-form.sh (MIT).
package setup

import (
	"encoding/json"
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"regexp"
	"sort"
	"strings"
	"unicode"
	"unicode/utf8"
)

// MinDiskBytes is the smallest disk offered: the 4 GiB ESP plus room for
// the system (about 6 GiB with the desktop), snapshots and a home directory.
const MinDiskBytes = 20 << 30

var (
	usernamePattern = regexp.MustCompile(`^[a-z_][a-z0-9_-]{0,31}$`)
	reservedUsers   = map[string]bool{}
	hostnamePattern = regexp.MustCompile(`^[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?$`)
)

func init() {
	for _, u := range strings.Fields(`root bin daemon mail ftp http nobody dbus systemd-coredump
		systemd-network systemd-oom systemd-journal-remote systemd-resolve systemd-timesync tss
		uuidd alpm git avahi cups cups-browsed lp _talkd polkitd rtkit qemu brltty gluster rpc
		libvirt-qemu pcscd nvidia-persistenced sddm`) {
		reservedUsers[u] = true
	}
}

// ValidUsername checks a login name.
func ValidUsername(name string) error {
	if !usernamePattern.MatchString(name) {
		return errors.New("use lowercase letters, digits, - and _, starting with a letter or _ (at most 32)")
	}
	if reservedUsers[name] {
		return fmt.Errorf("%q is a system account", name)
	}
	return nil
}

// ValidHostname checks a machine name.
func ValidHostname(name string) error {
	if !hostnamePattern.MatchString(name) {
		return errors.New("use lowercase letters, digits and -, not at the start or end (at most 63)")
	}
	return nil
}

// ValidSecret checks a password or passphrase and its confirmation.
func ValidSecret(secret, again string, min int) error {
	if len(secret) < min {
		return fmt.Errorf("use at least %d characters", min)
	}
	if strings.ContainsAny(secret, "\n\r") {
		return errors.New("no line breaks")
	}
	if secret != again {
		return errors.New("the two entries differ")
	}
	return nil
}

// ValidWiFiPassphrase checks a WPA passphrase: 8 to 63 printable ASCII
// characters, or the 64 hex digits of the key itself, which is what iwd
// and NetworkManager accept.
func ValidWiFiPassphrase(s string) error {
	if len(s) == 64 && strings.Trim(strings.ToLower(s), "0123456789abcdef") == "" {
		return nil
	}
	if len(s) < 8 || len(s) > 63 {
		return errors.New("a Wi-Fi passphrase has 8 to 63 characters")
	}
	for _, c := range []byte(s) {
		if c < 0x20 || c > 0x7e {
			return errors.New("a Wi-Fi passphrase has only letters, digits, punctuation and spaces from the US keyboard")
		}
	}
	return nil
}

// ValidSSID reports whether a network name can go into the install config
// on one line and be shown on the console: 1 to 32 bytes of UTF-8 and no
// control characters, not even C1 ones such as U+009B, which the Linux
// console reads as the start of an escape sequence.
func ValidSSID(s string) bool {
	if len(s) < 1 || len(s) > 32 || !utf8.ValidString(s) {
		return false
	}
	for _, r := range s {
		if unicode.IsControl(r) {
			return false
		}
	}
	return true
}

// ValidTimezone checks a zone name against the zoneinfo database at root.
func ValidTimezone(zoneinfo, tz string) error {
	if tz == "" || strings.Contains(tz, "..") || strings.HasPrefix(tz, "/") {
		return errors.New("not a time zone name")
	}
	info, err := os.Stat(filepath.Join(zoneinfo, tz))
	if err != nil || info.IsDir() {
		return fmt.Errorf("unknown time zone %q (for example Europe/Berlin or America/Chicago)", tz)
	}
	return nil
}

// ValidKeymap checks a console keymap name against the kbd keymaps tree.
func ValidKeymap(keymaps, name string) error {
	if name == "" || strings.ContainsAny(name, "/.") {
		return errors.New("not a keymap name")
	}
	found := false
	_ = filepath.WalkDir(keymaps, func(path string, d os.DirEntry, err error) error {
		if err == nil && !d.IsDir() && strings.TrimSuffix(d.Name(), ".map.gz") == name {
			found = true
			return filepath.SkipAll
		}
		return nil
	})
	if !found {
		return fmt.Errorf("unknown keymap %q (for example us, de-latin1, uk)", name)
	}
	return nil
}

// Disk is an install target candidate.
type Disk struct {
	Path  string
	Size  int64
	Model string
	Tran  string
	// Removable is the kernel's removable flag: an SD card or a USB stick.
	Removable bool
	Parts     []Part
}

// External reports whether the disk is plugged in from outside: on USB or
// FireWire, or removable. The disk list puts these after the internal ones.
func (d Disk) External() bool {
	return d.Removable || d.Tran == "usb" || d.Tran == "ieee1394"
}

// Part is a partition already on a disk, shown so the user can tell the
// disks apart before one is erased.
type Part struct {
	Path   string
	Size   int64
	FSType string
	Label  string
}

// Closed says why the partition cannot be mounted read-only as it is, or
// "" when it can: it needs a filesystem, and must not be swap, an
// encrypted container or part of a RAID, LVM or ZFS set. It reads after
// String: `/dev/sda2  996 GB  encrypted (LUKS), left locked`.
func (p Part) Closed() string {
	switch p.FSType {
	case "":
		return "nothing to open"
	case "swap":
		return "holds no files"
	case "crypto_LUKS", "BitLocker":
		return "left locked"
	case "LVM2_member":
		return "part of an LVM volume group"
	case "linux_raid_member":
		return "part of a RAID set"
	case "zfs_member":
		return "part of a ZFS pool"
	}
	return ""
}

// String renders the partition for the picker.
func (p Part) String() string {
	return fmt.Sprintf("%s  %s  %s", p.Path, humanSmall(p.Size), p.Kind())
}

// Kind is what the partition holds and its label: `vfat "EFI"`.
func (p Part) Kind() string {
	what := p.FSType
	switch what {
	case "":
		what = "no filesystem"
	case "crypto_LUKS":
		what = "encrypted (LUKS)"
	case "BitLocker":
		what = "encrypted (BitLocker)"
	}
	if p.Label != "" {
		what += ` "` + p.Label + `"`
	}
	return what
}

// humanSmall is HumanSize with MB for partitions under a gigabyte.
func humanSmall(b int64) string {
	if b < 1e9 {
		return fmt.Sprintf("%.0f MB", float64(b)/1e6)
	}
	return HumanSize(b)
}

// String renders the disk for the picker.
func (d Disk) String() string {
	model := d.Model
	if model == "" {
		model = "unknown model"
	}
	tran := ""
	if d.Tran != "" {
		tran = ", " + d.Tran
	}
	return fmt.Sprintf("%s  %s  %s%s", d.Path, HumanSize(d.Size), model, tran)
}

// HumanSize renders bytes in GB or TB as disk makers count them.
func HumanSize(b int64) string {
	if b >= 1e12 {
		return fmt.Sprintf("%.1f TB", float64(b)/1e12)
	}
	return fmt.Sprintf("%.0f GB", float64(b)/1e9)
}

type lsblkOutput struct {
	Blockdevices []struct {
		Name     string  `json:"name"`
		Path     string  `json:"path"`
		Size     int64   `json:"size"`
		Type     string  `json:"type"`
		Model    *string `json:"model"`
		Tran     *string `json:"tran"`
		RO       bool    `json:"ro"`
		RM       bool    `json:"rm"`
		Children []struct {
			Path   string  `json:"path"`
			Size   int64   `json:"size"`
			Type   string  `json:"type"`
			FSType *string `json:"fstype"`
			Label  *string `json:"label"`
		} `json:"children"`
	} `json:"blockdevices"`
}

// Disks parses `lsblk -J -b -o NAME,PATH,SIZE,TYPE,MODEL,TRAN,RO,RM,FSTYPE,LABEL`
// and returns whole, writable disks of at least MinDiskBytes, leaving out
// zram, loop and optical devices and the install medium. Internal disks
// come first, then the external ones, each by path.
func Disks(lsblkJSON []byte, installMedium string) ([]Disk, error) {
	var out lsblkOutput
	if err := json.Unmarshal(lsblkJSON, &out); err != nil {
		return nil, fmt.Errorf("lsblk output: %w", err)
	}
	var disks []Disk
	for _, d := range out.Blockdevices {
		if d.Type != "disk" || d.RO || d.Size < MinDiskBytes || strings.HasPrefix(d.Name, "zram") {
			continue
		}
		if installMedium != "" && d.Path == installMedium {
			continue
		}
		disk := Disk{Path: d.Path, Size: d.Size, Removable: d.RM}
		if d.Model != nil {
			disk.Model = strings.TrimSpace(*d.Model)
		}
		if d.Tran != nil {
			disk.Tran = *d.Tran
		}
		for _, c := range d.Children {
			if c.Type != "part" {
				continue
			}
			part := Part{Path: c.Path, Size: c.Size}
			if c.FSType != nil {
				part.FSType = *c.FSType
			}
			if c.Label != nil {
				part.Label = strings.TrimSpace(*c.Label)
			}
			disk.Parts = append(disk.Parts, part)
		}
		disks = append(disks, disk)
	}
	sort.Slice(disks, func(i, j int) bool {
		if a, b := disks[i].External(), disks[j].External(); a != b {
			return b
		}
		return disks[i].Path < disks[j].Path
	})
	return disks, nil
}

func (a Answers) localeOrDefault() string {
	if a.Locale == "" {
		return "en_US.UTF-8"
	}
	return a.Locale
}

// HasLocale reports whether locale.gen lists the locale ("de_DE.UTF-8"),
// commented out or not, which is what subarchy-install requires.
func HasLocale(localeGen, locale string) bool {
	data, err := os.ReadFile(localeGen)
	if err != nil {
		return false
	}
	for _, line := range strings.Split(string(data), "\n") {
		if strings.HasPrefix(strings.TrimPrefix(line, "#"), locale+" ") {
			return true
		}
	}
	return false
}

// Answers is everything the guided installer collects.
type Answers struct {
	Disk         string
	Hostname     string
	Username     string
	Password     string
	Passphrase   string
	Timezone     string
	Locale       string
	Keymap       string
	XKBLayout    string
	XKBVariant   string
	Repo         string
	CmdlineExtra string
	PackageCache string
	// WiFiSSID is the Wi-Fi network the installed system joins; empty for
	// none. WiFiPSK is its passphrase, empty for an open network.
	WiFiSSID string
	WiFiPSK  string
}

// WriteConfig writes the secrets into private files in dir and returns the
// path of the subarchy-install config that references them.
func (a Answers) WriteConfig(dir string) (string, error) {
	if err := os.MkdirAll(dir, 0o700); err != nil {
		return "", fmt.Errorf("config: %w", err)
	}
	secrets := map[string]string{"user-password": a.Password, "luks-passphrase": a.Passphrase}
	if a.WiFiPSK != "" {
		secrets["wifi-psk"] = a.WiFiPSK
	}
	for name, value := range secrets {
		if err := os.WriteFile(filepath.Join(dir, name), []byte(value+"\n"), 0o600); err != nil {
			return "", fmt.Errorf("config: %w", err)
		}
	}
	lines := []string{
		"# Written by subarchy-setup.",
		"DISK=" + a.Disk,
		"HOSTNAME=" + a.Hostname,
		"USERNAME=" + a.Username,
		"USER_PASSWORD_FILE=" + filepath.Join(dir, "user-password"),
		"LUKS_PASSPHRASE_FILE=" + filepath.Join(dir, "luks-passphrase"),
		"TIMEZONE=" + a.Timezone,
		"LOCALE=" + a.localeOrDefault(),
		"KEYMAP=" + a.Keymap,
		"XKB_LAYOUT=" + a.XKBLayout,
		"SUBARCHY_REPO=" + a.Repo,
	}
	if a.XKBVariant != "" {
		lines = append(lines, "XKB_VARIANT="+a.XKBVariant)
	}
	if a.PackageCache != "" {
		lines = append(lines, "PACKAGE_CACHE="+a.PackageCache)
	}
	if a.CmdlineExtra != "" {
		lines = append(lines, "KERNEL_CMDLINE_EXTRA="+a.CmdlineExtra)
	}
	if a.WiFiSSID != "" {
		lines = append(lines, "WIFI_SSID="+a.WiFiSSID)
		if a.WiFiPSK != "" {
			lines = append(lines, "WIFI_PSK_FILE="+filepath.Join(dir, "wifi-psk"))
		}
	}
	path := filepath.Join(dir, "install.conf")
	if err := os.WriteFile(path, []byte(strings.Join(lines, "\n")+"\n"), 0o600); err != nil {
		return "", fmt.Errorf("config: %w", err)
	}
	return path, nil
}
