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

// fakeGum answers gum calls from a script: each entry is the value gum
// would print, or "<esc>" for Escape, "<no>" for the negative button.
type fakeGum struct {
	t       *testing.T
	answers []string
	calls   [][]string
}

func (g *fakeGum) run(args ...string) (string, int) {
	g.calls = append(g.calls, args)
	if len(g.answers) == 0 {
		g.t.Fatalf("gum asked more than scripted: %v", args)
	}
	a := g.answers[0]
	g.answers = g.answers[1:]
	switch a {
	case "<esc>":
		return "", 130
	case "<no>":
		return "", 1
	}
	return a, 0
}

func testScreens(t *testing.T, answers ...string) (*screens, *fakeGum, *bytes.Buffer) {
	g := &fakeGum{t: t, answers: answers}
	var out bytes.Buffer
	return &screens{out: &out, gum: g.run, width: func() int { return 120 }, key: func() bool { return true }}, g, &out
}

const partsJSON = `{"blockdevices":[
 {"name":"vda","path":"/dev/vda","size":25769803776,"type":"disk","model":null,"tran":null,"ro":false,"children":[
  {"path":"/dev/vda1","size":524288000,"type":"part","fstype":"vfat","label":"EFI"},
  {"path":"/dev/vda2","size":25000000000,"type":"part","fstype":"ntfs","label":"Windows"}]},
 {"name":"vdb","path":"/dev/vdb","size":64424509440,"type":"disk","model":"data","tran":null,"ro":false}]}`

func TestScreensInstall(t *testing.T) {
	e := testEnv(t)
	e.lsblk = func() ([]byte, error) { return []byte(partsJSON), nil }
	var loaded string
	e.loadKeymap = func(k string) error { loaded = k; return nil }
	var looked []string
	e.browse = func(d setup.Disk) error { looked = append(looked, d.Path); return nil }
	s, g, out := testScreens(t,
		"German",        // language, which preselects the German keyboard
		"German",        // keyboard
		"Europe/Berlin", // time zone
		"root", "pat",   // user name: refused, then accepted
		"secret-one", "secret-two", // password pair that differs
		"secret-one", "secret-one",
		"box",                                // computer name
		"<no>", "disk-pass-1", "disk-pass-1", // a separate disk passphrase
		"<row:/dev/vda>",            // disk
		"Browse it read-only first", // look
		"Install here",
		"<no>",                           // summary: no, change it -> back to the disk
		"<row:/dev/vda>", "Install here", // the disk again
		"",     // summary: yes
		"<no>", // erase? no -> back to the summary
		"", "", // summary: yes; erase: yes
	)
	// Rows carry the partition summary; pick them by prefix.
	real := s.gum
	s.gum = func(args ...string) (string, int) {
		out, code := real(args...)
		if p, ok := strings.CutPrefix(out, "<row:"); ok {
			for _, a := range args {
				if strings.HasPrefix(a, strings.TrimSuffix(p, ">")) {
					return a, code
				}
			}
			t.Fatalf("no row for %s in %v", out, args)
		}
		return out, code
	}
	e.screens = s
	dir := filepath.Join(t.TempDir(), "conf")
	var stdout bytes.Buffer
	code := run([]string{"--dir", dir, "--dry-run"}, strings.NewReader(""), &stdout, e, nil, nil)
	if code != 0 {
		t.Fatalf("exit %d:\n%s\n%s", code, stdout.String(), out.String())
	}
	if len(g.answers) != 0 {
		t.Errorf("unused answers: %v", g.answers)
	}
	conf, _ := os.ReadFile(filepath.Join(dir, "install.conf"))
	for _, want := range []string{"DISK=/dev/vda", "HOSTNAME=box", "USERNAME=pat", "TIMEZONE=Europe/Berlin", "KEYMAP=de-latin1", "XKB_LAYOUT=de", "LOCALE=de_DE.UTF-8"} {
		if !strings.Contains(string(conf), want+"\n") {
			t.Errorf("config lacks %q:\n%s", want, conf)
		}
	}
	pass, _ := os.ReadFile(filepath.Join(dir, "luks-passphrase"))
	if string(pass) != "disk-pass-1\n" {
		t.Errorf("passphrase = %q", pass)
	}
	if loaded != "de-latin1" || len(looked) != 1 || looked[0] != "/dev/vda" {
		t.Errorf("loaded %q, browsed %v", loaded, looked)
	}
	for _, want := range []string{"is a system account", "The two entries differ", `/dev/vda2  25 GB  ntfs "Windows"`,
		"Everything on /dev/vda will be erased.", "Install disk", "/dev/vda (erased)", "Does this look right", "Escape goes back"} {
		if !strings.Contains(out.String()+callText(g), want) {
			t.Errorf("screens lack %q", want)
		}
	}
	if !strings.Contains(callText(g), "--header Keyboard layout --padding 0 0 0 29 --cursor.foreground 2 --header.foreground 5 --selected.foreground 2 --selected German") {
		t.Error("choosing German did not preselect the German keyboard")
	}
	if !strings.Contains(callText(g), "[vfat EFI, ntfs Windows]") || !strings.Contains(callText(g), "[empty]") {
		t.Errorf("disk rows lack the partition summary: %s", callText(g))
	}
	// The erase question defaults to no.
	if !strings.Contains(callText(g), "Erase /dev/vda and install Subarchy? --affirmative Yes, erase and install --negative No, go back --default=false") {
		t.Error("erase confirm is not default-no")
	}
}

func callText(g *fakeGum) string {
	var b strings.Builder
	for _, c := range g.calls {
		b.WriteString(strings.Join(c, " ") + "\n")
	}
	return b.String()
}

// Escape walks back one step at a time, and out of the installer from
// the greeter.
func TestScreensEscape(t *testing.T) {
	e := testEnv(t)
	s, _, _ := testScreens(t, "German", "German", "<esc>", "<esc>", "<esc>")
	keys := []bool{true, false} // greeter: start, then leave
	s.key = func() bool { k := keys[0]; keys = keys[1:]; return k }
	e.screens = s
	var stdout bytes.Buffer
	code := run([]string{"--dir", t.TempDir()}, strings.NewReader(""), &stdout, e, nil,
		func(string, bool) error { t.Error("installer ran"); return nil })
	if code != 1 || !strings.Contains(stdout.String(), "nothing was changed") || len(keys) != 0 {
		t.Errorf("exit %d, keys left %v:\n%s", code, keys, stdout.String())
	}
}

func TestFontFor(t *testing.T) {
	for pixels, want := range map[int]string{3840: "ter-v32b", 2880: "ter-v32b", 1920: "ter-v32b", 1600: "ter-v32b",
		1366: "ter-v24b", 1280: "ter-v24b", 1024: "ter-v20b", 800: "ter-v16b", 640: "ter-v16b"} {
		if _, got := fontFor(pixels); got != want {
			t.Errorf("fontFor(%d) = %s, want %s", pixels, got, want)
		}
	}
}

func TestZones(t *testing.T) {
	dir := t.TempDir()
	for _, f := range []string{"UTC", "Europe/Berlin", "America/Argentina/Salta", "posix/Europe/Berlin", "Etc/GMT+1", "zone.tab", "CET"} {
		os.MkdirAll(filepath.Dir(filepath.Join(dir, f)), 0o755)
		os.WriteFile(filepath.Join(dir, f), nil, 0o644)
	}
	if got := strings.Join(zones(dir), " "); got != "America/Argentina/Salta Europe/Berlin UTC" {
		t.Errorf("zones = %q", got)
	}
}

func TestProgressOf(t *testing.T) {
	for _, c := range []struct {
		log   string
		at    int
		label string
	}{
		{"", 0, "Starting"},
		{">> partitioning /dev/vda\n>> encrypting /dev/vda2 (LUKS2)\n", 15, "Encrypting the disk"},
		{">> installing packages\nresolving...\n", 50, "Installing packages"},
		{">> installing packages\nPackages (4) a-1  b-2\n\ninstalling a...\ninstalling b...\n", 375, "Installing packages (2 of 4)"},
		{">> installing packages\nPackages (2) a b\ninstalling a...\ninstalling b...\n>> configuring the system\n" +
			strings.Repeat("x\n", 180), 830, "Configuring the system"},
		{">> configuring the system\n" + strings.Repeat("x\n", 5000) + ">> finishing\n", 990, "Finishing"},
	} {
		if at, label := progressOf(c.log); at != c.at || label != c.label {
			t.Errorf("progressOf(%.40q) = %d, %q; want %d, %q", c.log, at, label, c.at, c.label)
		}
	}
	if bar(500, 10) != "█████░░░░░" {
		t.Errorf("bar = %q", bar(500, 10))
	}
}

// With screens, the install shows the progress view and ends on the
// finish screen (reboot) or the failure menu.
func TestScreensInstallEnd(t *testing.T) {
	answers := []string{"English (US)", "English (US)", "UTC", "pat", "secret-one", "secret-one", "", "", "<row:/dev/vda>", "Install here", "", ""}
	setupRun := func(extra []string, fail bool) (int, []string, string) {
		e := testEnv(t)
		e.installLog = filepath.Join(t.TempDir(), "install.log")
		os.WriteFile(e.installLog, []byte("old run\n>> finishing\n"), 0o644)
		e.logTail = func(int) []string { return []string{"error: target not found: nope"} }
		var did []string
		e.action = func(what string) error { did = append(did, what); return nil }
		s, g, out := testScreens(t, append(append([]string{}, answers...), extra...)...)
		real := g.run
		s.gum = func(args ...string) (string, int) {
			o, code := real(args...)
			if strings.HasPrefix(o, "<row:") {
				for _, a := range args {
					if strings.HasPrefix(a, "/dev/vda") {
						return a, code
					}
				}
			}
			return o, code
		}
		e.screens = s
		var stdout bytes.Buffer
		code := run([]string{"--dir", t.TempDir()}, strings.NewReader(""), &stdout, e, nil, func(_ string, quiet bool) error {
			if !quiet {
				t.Error("installer output not silenced under the install view")
			}
			os.WriteFile(e.installLog, []byte("old run\n>> finishing\n>> partitioning /dev/vda\n"), 0o644)
			time.Sleep(700 * time.Millisecond)
			if fail {
				return errors.New("exit status 1")
			}
			return nil
		})
		return code, did, out.String()
	}
	code, did, out := setupRun([]string{""}, false) // reboot: yes
	if code != 0 || len(did) != 1 || did[0] != "reboot" {
		t.Errorf("finish: exit %d, did %v", code, did)
	}
	// The old run's "finishing" line does not count; this run's partitioning does.
	for _, want := range []string{"Installing Subarchy", "Partitioning the disk", "Installed Subarchy in", "Tip: "} {
		if !strings.Contains(out, want) {
			t.Errorf("screens lack %q", want)
		}
	}
	if strings.Contains(out, "Finishing") {
		t.Error("progress read an earlier run's log")
	}
	code, did, out = setupRun([]string{"View the full log", "Open a shell"}, true)
	if code != 1 || len(did) != 1 || did[0] != "log" || !strings.Contains(out, "installation stopped: exit status 1") ||
		!strings.Contains(out, "target not found: nope") {
		t.Errorf("failure: exit %d, did %v:\n%s", code, did, out)
	}
}
