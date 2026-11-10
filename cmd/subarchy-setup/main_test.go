package main

import (
	"bytes"
	"errors"
	"os"
	"path/filepath"
	"strings"
	"testing"
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
	return env{
		lsblk:        func() ([]byte, error) { return []byte(lsblkJSON), nil },
		installMedia: func() string { return "/dev/sr0" },
		zoneinfo:     zi,
		keymaps:      km,
	}
}

// Answers: keymap, disk 3 (bad), 1, hostname default, bad user then pat,
// password twice (first pair mismatched), passphrase, tz bad then Berlin.
const goodInput = "de-latin1\n3\n1\n\nroot\npat\nsecret-one\nsecret-two\nsecret-one\nsecret-one\n" +
	"disk-pass-1\ndisk-pass-1\nMars/Base\nEurope/Berlin\n"

func TestRunInstalls(t *testing.T) {
	dir := filepath.Join(t.TempDir(), "conf")
	var out bytes.Buffer
	var ran string
	code := run([]string{"--dir", dir, "--cmdline-extra", "console=ttyS0"}, strings.NewReader(goodInput+"vda\n"), &out,
		testEnv(t), nil, func(conf string) error { ran = conf; return nil })
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
	code := run([]string{"--dir", t.TempDir()}, strings.NewReader(goodInput+"yes\n"), &out, testEnv(t), nil,
		func(string) error { ran = true; return nil })
	if code != 1 || ran || !strings.Contains(out.String(), "nothing was changed") {
		t.Errorf("exit %d, ran %v:\n%s", code, ran, out.String())
	}
}

func TestRunDryRun(t *testing.T) {
	var out bytes.Buffer
	code := run([]string{"--dir", t.TempDir(), "--dry-run"}, strings.NewReader(goodInput+"vda\n"), &out, testEnv(t), nil,
		func(string) error { t.Error("installer ran in dry run"); return nil })
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
	failing := func(string) error { return errors.New("installer failed") }
	out.Reset()
	if code := run([]string{"--dir", t.TempDir()}, strings.NewReader(goodInput+"vda\n"), &out, testEnv(t), nil, failing); code != 1 {
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
	if code := run([]string{"--dir", dir, "--dry-run"}, strings.NewReader(goodInput+"vda\n"), &out, e, nil, nil); code != 0 {
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
	if code := run([]string{"--dir", dir, "--dry-run"}, strings.NewReader(goodInput+"vda\n"), &out, e, nil, nil); code != 0 {
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
