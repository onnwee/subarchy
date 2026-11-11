package main

import (
	"bytes"
	"errors"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"git.subcult.tv/subculture-collective/subarchy/internal/setup"
)

const lsblkJSON = `{"blockdevices":[
 {"name":"sr0","path":"/dev/sr0","size":1646600192,"type":"rom","model":"DVD","tran":"sata","ro":false},
 {"name":"vda","path":"/dev/vda","size":25769803776,"type":"disk","model":null,"tran":null,"ro":false},
 {"name":"vdb","path":"/dev/vdb","size":64424509440,"type":"disk","model":"data","tran":null,"ro":false}
]}`

func testEnv(t *testing.T) env {
	t.Helper()
	zi, km := t.TempDir(), t.TempDir()
	for _, f := range []string{filepath.Join(zi, "UTC"), filepath.Join(zi, "Europe", "Berlin"),
		filepath.Join(km, "i386", "qwerty", "us.map.gz"), filepath.Join(km, "i386", "qwertz", "de-latin1.map.gz")} {
		if err := os.MkdirAll(filepath.Dir(f), 0o755); err != nil {
			t.Fatal(err)
		}
		if err := os.WriteFile(f, nil, 0o644); err != nil {
			t.Fatal(err)
		}
	}
	gen := filepath.Join(t.TempDir(), "locale.gen")
	os.WriteFile(gen, []byte("#de_DE.UTF-8 UTF-8\nen_US.UTF-8 UTF-8\n#en_GB.UTF-8 UTF-8\n"), 0o644)
	return env{
		localeGen:    gen,
		lsblk:        func() ([]byte, error) { return []byte(lsblkJSON), nil },
		installMedia: func() string { return "/dev/sr0" },
		zoneinfo:     zi,
		keymaps:      km,
	}
}

// Answers: keymap, disk 3 (bad), 1, hostname default, bad user then pat,
// password twice (first pair mismatched), own passphrase, tz bad then
// Berlin.
const goodInput = "de-latin1\n3\n1\n\nroot\npat\nsecret-one\nsecret-two\nsecret-one\nsecret-one\n" +
	"n\ndisk-pass-1\ndisk-pass-1\nMars/Base\nEurope/Berlin\n"

func TestRunInstalls(t *testing.T) {
	dir := filepath.Join(t.TempDir(), "conf")
	var out bytes.Buffer
	var ran string
	code := run([]string{"--dir", dir, "--cmdline-extra", "console=ttyS0"}, strings.NewReader(goodInput+"y\n"), &out,
		testEnv(t), nil, func(conf string, _ bool) error { ran = conf; return nil })
	if code != 0 {
		t.Fatalf("exit %d:\n%s", code, out.String())
	}
	if ran != filepath.Join(dir, "install.conf") {
		t.Errorf("ran installer with %q", ran)
	}
	conf, _ := os.ReadFile(ran)
	for _, want := range []string{"DISK=/dev/vda", "HOSTNAME=subarchy", "USERNAME=pat", "TIMEZONE=Europe/Berlin",
		"KEYMAP=de-latin1", "XKB_LAYOUT=de", "SUBARCHY_REPO=file:///opt/subarchy/repo", "KERNEL_CMDLINE_EXTRA=console=ttyS0"} {
		if !strings.Contains(string(conf), want+"\n") {
			t.Errorf("config lacks %q", want)
		}
	}
	pw, _ := os.ReadFile(filepath.Join(dir, "user-password"))
	if string(pw) != "secret-one\n" {
		t.Errorf("password file = %q", pw)
	}
	for _, msg := range []string{"enter a number from 1 to 2", "is a system account", "the two entries differ",
		"unknown time zone", "/dev/vdb  64 GB  data"} {
		if !strings.Contains(out.String(), msg) {
			t.Errorf("output lacks %q", msg)
		}
	}
	if strings.Contains(out.String(), "/dev/sr0") {
		t.Error("offered the install medium")
	}
}

func TestRunStopsWithoutConfirmation(t *testing.T) {
	var out bytes.Buffer
	ran := false
	code := run([]string{"--dir", t.TempDir()}, strings.NewReader(goodInput+"\n"), &out, testEnv(t), nil,
		func(string, bool) error { ran = true; return nil })
	if code != 1 || ran || !strings.Contains(out.String(), "nothing was changed") {
		t.Errorf("exit %d, ran %v:\n%s", code, ran, out.String())
	}
}

func TestRunDryRun(t *testing.T) {
	var out bytes.Buffer
	code := run([]string{"--dir", t.TempDir(), "--dry-run"}, strings.NewReader(goodInput+"y\n"), &out, testEnv(t), nil,
		func(string, bool) error { t.Error("installer ran in dry run"); return nil })
	if code != 0 || !strings.Contains(out.String(), "Config written to") {
		t.Errorf("exit %d:\n%s", code, out.String())
	}
}

func TestRunErrors(t *testing.T) {
	e := testEnv(t)
	e.lsblk = func() ([]byte, error) { return []byte(`{"blockdevices":[]}`), nil }
	var out bytes.Buffer
	if code := run(nil, strings.NewReader(""), &out, e, nil, nil); code != 1 || !strings.Contains(out.String(), "no disk") {
		t.Errorf("no disks: exit %d, %s", code, out.String())
	}
	e.lsblk = func() ([]byte, error) { return nil, errors.New("boom") }
	out.Reset()
	if code := run(nil, strings.NewReader(""), &out, e, nil, nil); code != 1 || !strings.Contains(out.String(), "list disks") {
		t.Errorf("lsblk failure: exit %d, %s", code, out.String())
	}
	out.Reset()
	if code := run(nil, strings.NewReader("1\n"), &out, testEnv(t), nil, nil); code != 1 {
		t.Errorf("EOF mid-form: exit %d", code)
	}
	if code := run([]string{"--bogus"}, strings.NewReader(""), &out, testEnv(t), nil, nil); code != 2 {
		t.Errorf("bad flag: exit %d", code)
	}
	failing := func(string, bool) error { return errors.New("installer failed") }
	out.Reset()
	if code := run([]string{"--dir", t.TempDir()}, strings.NewReader(goodInput+"y\n"), &out, testEnv(t), nil, failing); code != 1 {
		t.Errorf("installer failure: exit %d", code)
	}
}

// The installed system asks for the passphrase and the password under the
// chosen layout, so both must be typed under it here too.
func TestKeyboardIsLoadedBeforeAnySecretIsTyped(t *testing.T) {
	var out bytes.Buffer
	var loaded, shownAtLoad string
	e := testEnv(t)
	e.loadKeymap = func(keymap string) error {
		loaded, shownAtLoad = keymap, out.String()
		return nil
	}
	dir := filepath.Join(t.TempDir(), "conf")
	if code := run([]string{"--dir", dir, "--dry-run"}, strings.NewReader(goodInput+"y\n"), &out, e, nil, nil); code != 0 {
		t.Fatalf("exit %d:\n%s", code, out.String())
	}
	if loaded != "de-latin1" {
		t.Fatalf("loaded keymap %q, want de-latin1", loaded)
	}
	for _, later := range []string{"Install to disk number", "Password for", "Disk passphrase"} {
		if strings.Contains(shownAtLoad, later) {
			t.Errorf("%q was asked before the keyboard was loaded", later)
		}
	}
	e.loadKeymap = func(string) error { return errors.New("no console") }
	out.Reset()
	if code := run([]string{"--dir", dir, "--dry-run"}, strings.NewReader(goodInput+"y\n"), &out, e, nil, nil); code != 0 {
		t.Fatalf("a console that cannot switch stopped the setup: exit %d", code)
	}
	if !strings.Contains(out.String(), "Could not switch this console") {
		t.Error("no warning when the keymap could not be loaded")
	}
}

func TestXKBFromSystemdsTable(t *testing.T) {
	table := filepath.Join(t.TempDir(), "kbd-model-map")
	os.WriteFile(table, []byte("# consolelayout\txlayout\txmodel\txvariant\txoptions\n"+
		"sv-latin1\t\tse\tpc105\t\t-\t\tterminate:ctrl_alt_bksp\n"+
		"la-latin1\t\tlatam\tpc105\t\t-\t\tterminate:ctrl_alt_bksp\n"+
		"et\t\t\tee\tpc105\t\t-\t\tterminate:ctrl_alt_bksp\n"+
		"sg-latin1\t\tch\tpc105\t\tde_nodeadkeys\tterminate:ctrl_alt_bksp\n"+
		"dvorak\t\t\tus\tpc105\t\tdvorak\t\tterminate:ctrl_alt_bksp\n"+
		"dvorak\t\t\tus\tpc105\t\tdvorak-alt-intl\tterminate:ctrl_alt_bksp\n"), 0o644)
	for keymap, want := range map[string][2]string{
		"sv-latin1": {"se", ""}, "la-latin1": {"latam", ""}, "et": {"ee", ""},
		"sg-latin1": {"ch", "de_nodeadkeys"}, "dvorak": {"us", "dvorak"},
		"de-latin1": {"de", ""}, // not in this table: the name's first part
	} {
		layout, variant := xkbFor(table, keymap)
		if layout != want[0] || variant != want[1] {
			t.Errorf("xkbFor(%q) = %q, %q; want %q, %q", keymap, layout, variant, want[0], want[1])
		}
	}
	if layout, variant := xkbFor(filepath.Join(t.TempDir(), "missing"), "uk"); layout != "gb" || variant != "" {
		t.Errorf("without the table: %q, %q", layout, variant)
	}
}

func TestXKBLayout(t *testing.T) {
	for in, want := range map[string]string{"us": "us", "de-latin1": "de", "uk": "gb", "fr-latin1": "fr"} {
		if got := xkbLayout(in); got != want {
			t.Errorf("xkbLayout(%q) = %q, want %q", in, got, want)
		}
	}
}

func TestPasswordIsThePassphraseByDefault(t *testing.T) {
	dir := filepath.Join(t.TempDir(), "conf")
	var out bytes.Buffer
	in := "\n1\n\npat\nsecret-one\nsecret-one\n\n\ny\n"
	if code := run([]string{"--dir", dir, "--dry-run"}, strings.NewReader(in), &out, testEnv(t), nil, nil); code != 0 {
		t.Fatalf("exit %d:\n%s", code, out.String())
	}
	pass, _ := os.ReadFile(filepath.Join(dir, "luks-passphrase"))
	if string(pass) != "secret-one\n" {
		t.Errorf("passphrase file = %q", pass)
	}
}

func TestDiskContentsAndBrowse(t *testing.T) {
	e := testEnv(t)
	e.lsblk = func() ([]byte, error) {
		return []byte(`{"blockdevices":[
 {"name":"vda","path":"/dev/vda","size":25769803776,"type":"disk","model":null,"tran":null,"ro":false,"children":[
  {"path":"/dev/vda1","size":524288000,"type":"part","fstype":"vfat","label":"EFI"},
  {"path":"/dev/vda2","size":25000000000,"type":"part","fstype":"crypto_LUKS","label":null}]},
 {"name":"vdb","path":"/dev/vdb","size":64424509440,"type":"disk","model":"data","tran":null,"ro":false}]}`), nil
	}
	var looked []string
	e.browse = func(d setup.Disk) error { looked = append(looked, d.Path); return nil }
	var out bytes.Buffer
	in := "\nlook 1\n2\n\npat\nsecret-one\nsecret-one\n\n\ny\n"
	if code := run([]string{"--dir", t.TempDir(), "--dry-run"}, strings.NewReader(in), &out, e, nil, nil); code != 0 {
		t.Fatalf("exit %d:\n%s", code, out.String())
	}
	if len(looked) != 1 || looked[0] != "/dev/vda" {
		t.Errorf("browsed %v", looked)
	}
	for _, want := range []string{`/dev/vda1  524 MB  vfat "EFI"`, "/dev/vda2  25 GB  encrypted (LUKS)", "empty: no partitions"} {
		if !strings.Contains(out.String(), want) {
			t.Errorf("output lacks %q:\n%s", want, out.String())
		}
	}
	// --batch offers neither the browse nor a reboot.
	out.Reset()
	run([]string{"--dir", t.TempDir(), "--dry-run", "--batch"}, strings.NewReader(in), &out, e, nil, nil)
	if len(looked) != 1 || strings.Contains(out.String(), "browse that disk") {
		t.Errorf("batch mode offered the browse (browsed %v):\n%s", looked, out.String())
	}
}

func TestFinishAndFailureScreens(t *testing.T) {
	var did []string
	e := testEnv(t)
	e.action = func(what string) error { did = append(did, what); return nil }
	e.logTail = func(int) []string { return []string{"error: target not found: nope"} }
	var out bytes.Buffer
	// Enter at the reboot offer reboots.
	code := run([]string{"--dir", t.TempDir()}, strings.NewReader(goodInput+"y\n\n"), &out, e, nil, func(string, bool) error { return nil })
	if code != 0 || len(did) != 1 || did[0] != "reboot" || !strings.Contains(out.String(), "Installed Subarchy in 0s.") {
		t.Errorf("finish: exit %d, did %v:\n%s", code, did, out.String())
	}
	// A failure shows the log's end and a menu: view the log, then the shell.
	did, out = nil, bytes.Buffer{}
	code = run([]string{"--dir", t.TempDir()}, strings.NewReader(goodInput+"y\n1\n\n"), &out, e, nil,
		func(string, bool) error { return errors.New("exit status 1") })
	if code != 1 || len(did) != 1 || did[0] != "log" {
		t.Errorf("failure: exit %d, did %v:\n%s", code, did, out.String())
	}
	for _, want := range []string{"Subarchy installation stopped: exit status 1", "target not found: nope", "4) Power off"} {
		if !strings.Contains(out.String(), want) {
			t.Errorf("failure output lacks %q", want)
		}
	}
	if elapsed(192*time.Second) != "3m 12s" {
		t.Errorf("elapsed = %q", elapsed(192*time.Second))
	}
}
