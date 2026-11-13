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
	var opens []bool
	e.browse = func(d setup.Disk, show func(opened, closed []string) bool) error {
		looked = append(looked, d.Path)
		opens = append(opens, show([]string{d.Parts[0].String()}, []string{"/dev/vda3  1 GB  swap, holds no files"}))
		return nil
	}
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
	// Rows carry the partition summary; pick them by prefix. Each question
	// is noted with the heading on the screen when it was asked.
	real := s.gum
	headings := map[string]string{}
	s.gum = func(args ...string) (string, int) {
		for _, q := range []string{"Time zone", "Computer name> ", "User name> ", "Password> "} {
			if strings.Contains(strings.Join(args, "\x00"), "\x00"+q) {
				text := out.String()
				if i := strings.LastIndex(text, "Let's set up your "); i >= 0 {
					headings[q] = text[i : i+strings.Index(text[i:], ".")+1]
				} else {
					headings[q] = ""
				}
			}
		}
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
	if loaded != "de-latin1" || len(looked) != 1 || looked[0] != "/dev/vda" || !opens[0] {
		t.Errorf("loaded %q, browsed %v, opened %v", loaded, looked, opens)
	}
	for _, want := range []string{"is a system account", "The two entries differ", `/dev/vda2  25 GB  ntfs "Windows"`,
		"Browsing /dev/vda read-only", `  /dev/vda1  524 MB  vfat "EFI"`, "Not opened:", "  /dev/vda3  1 GB  swap, holds no files",
		"press q, or Esc and then 0,", "or F10 (Fn+F10 on many laptops).", "Press Return to open it, or Escape to go back.",
		"Everything on /dev/vda will be erased.", "Install disk", "/dev/vda (erased)", "Does this look right", "Escape goes back"} {
		if !strings.Contains(out.String()+callText(g), want) {
			t.Errorf("screens lack %q", want)
		}
	}
	if !strings.Contains(callText(g), "--header Keyboard layout --padding 0 0 0 26 --cursor.foreground 2 --header.foreground 5 --selected.foreground 2 --selected=German --") {
		t.Error("choosing German did not preselect the German keyboard")
	}
	// Offline (no lookup here), the time zone list opens on the language's zone.
	if !strings.Contains(callText(g), "--no-fuzzy Europe/Berlin UTC") || !strings.Contains(out.String(), "Guessed from the language you chose.") {
		t.Error("choosing German did not put Europe/Berlin first in the time zone list")
	}
	if !strings.Contains(callText(g), `[vfat "EFI", ntfs "Windows"]`) || !strings.Contains(callText(g), "[empty]") {
		t.Errorf("disk rows lack the partition summary: %s", callText(g))
	}
	// Back from the summary, the disk list opens on the disk chosen, its
	// commas escaped for gum.
	if !strings.Contains(callText(g), `--selected=/dev/vda  26 GB  unknown model  [vfat "EFI"\, ntfs "Windows"]`) {
		t.Errorf("disk list did not reopen on the chosen disk: %s", callText(g))
	}
	// The secrets are not shown, nor their lengths.
	if strings.Contains(out.String(), "****") || !strings.Contains(ansi.ReplaceAllString(out.String(), ""), "Disk passphrase  set (hidden)") {
		t.Error("summary shows the password's length")
	}
	// The time zone and computer name are machine questions; the user
	// name and password are the account's.
	for q, want := range map[string]string{"Time zone": "machine", "Computer name> ": "machine", "User name> ": "account", "Password> ": "account"} {
		if headings[q] != "Let's set up your "+want+"." {
			t.Errorf("%q asked under %q", q, headings[q])
		}
	}
	// confirm's questions and buttons start at the page's left edge.
	if !strings.Contains(callText(g), "--prompt.margin 0 --selected.margin 0 2 0 0 --unselected.margin 0 2 0 0") {
		t.Error("confirm keeps gum's left margins")
	}
	// The erase question defaults to no.
	if !strings.Contains(callText(g), "Erase /dev/vda and install Subarchy? --affirmative Yes, erase and install --negative No, go back --default=false") {
		t.Error("erase confirm is not default-no")
	}
}

// gum drops a backslash in front of any character in --selected, so a
// backslash in a row is doubled as well as a comma escaped.
func TestChooseSelectedEscapes(t *testing.T) {
	s, g, _ := testScreens(t, "")
	row := `/dev/vda  1 TB  Model\x20One  [vfat, ext4]`
	s.choose("Install disk", []string{row}, row)
	if want := `--selected=/dev/vda  1 TB  Model\\x20One  [vfat\, ext4]`; !strings.Contains(callText(g), want) {
		t.Errorf("gum call lacks %q: %s", want, callText(g))
	}
}

// The page before the browse: Escape skips the file manager, and with
// nothing to open there is only a way back.
func TestBeforeLook(t *testing.T) {
	s, _, out := testScreens(t)
	s.key = func() bool { return false }
	if s.beforeLook("/dev/vda")([]string{"/dev/vda1  1 GB  ext4"}, nil) {
		t.Error("Escape on the browse page opened the file manager")
	}
	s.key = func() bool { return true }
	if s.beforeLook("/dev/vda")(nil, []string{"/dev/vda1  1 GB  encrypted (LUKS), left locked"}) {
		t.Error("opened the file manager with nothing mounted")
	}
	for _, want := range []string{"Press Return to open it, or Escape to go back.", "Nothing on /dev/vda can be opened read-only.",
		"/dev/vda1  1 GB  encrypted (LUKS), left locked", "Press Return to go back."} {
		if !strings.Contains(out.String(), want) {
			t.Errorf("pages lack %q:\n%s", want, out.String())
		}
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
	for pixels, want := range map[int]string{3840: "ter-i32b", 2880: "ter-i32b", 1920: "ter-i32b", 1600: "ter-i32b",
		1366: "ter-i24b", 1280: "ter-i24b", 1024: "ter-i20b", 800: "ter-i16b", 640: "ter-i16b"} {
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
	// With tzdata's tables, the old alias names are left out.
	for _, f := range []string{"America/Chicago", "Europe/Oslo", "US/Central", "Canada/Eastern", "Chile/EasterIsland"} {
		os.MkdirAll(filepath.Dir(filepath.Join(dir, f)), 0o755)
		os.WriteFile(filepath.Join(dir, f), nil, 0o644)
	}
	os.WriteFile(filepath.Join(dir, "zone.tab"), []byte("# comment\nNO\t+5955+01045\tEurope/Oslo\nUS\t+415100-0873900\tAmerica/Chicago\tCentral (most areas)\n"), 0o644)
	os.WriteFile(filepath.Join(dir, "zone1970.tab"), []byte("DE,DK,NO\t+5230+01322\tEurope/Berlin\nXX\t+0000+00000\tNowhere/Gone\n"), 0o644)
	if got := strings.Join(zones(dir), " "); got != "America/Chicago Europe/Berlin Europe/Oslo UTC" {
		t.Errorf("zones from the tables = %q", got)
	}
}

// A failed install's reason comes from its log: subarchy-install's own
// fatal message, not a note it carried on after or the cleanup note
// after it, else the last tool error near the end, but not a mirror
// error from long before.
func TestFailReason(t *testing.T) {
	mirror := "error: failed retrieving file 'a.pkg' from mirror : timed out\n"
	quiet := strings.Repeat("installing x...\n", failTail)
	for _, c := range []struct{ log, step, why string }{
		{"", "", ""},
		{">> partitioning /dev/vda\n>> encrypting\nsubarchy-install: error: partitions did not appear\n" +
			"subarchy-install: could not close the encrypted volume; before another try run: cryptsetup close root\n",
			"Encrypting the disk", "partitions did not appear"},
		{">> installing packages\n" + mirror + "Packages (2) a b\n" + quiet + "\x1b[1m==> ERROR:\x1b[0m module not found\n",
			"Installing packages (2 of 2)", "module not found"},
		{">> installing packages\n" + mirror + quiet, "Installing packages", ""},
		{"subarchy-install: error: DISK /dev/vda has mounted partitions\n", "", "DISK /dev/vda has mounted partitions"},
		// A warning shortly before the fatal message is not the reason.
		{"subarchy-install: pult apply failed; run it after login\n>> configuring snapper\n>> checking the boot entries\n" +
			"subarchy-install: error: linux-zen UKI missing\n", "Checking the boot entries", "linux-zen UKI missing"},
		// Nor before a tool error that ends the run without one.
		{">> installing packages\nsubarchy-install: subcult-hw not found; installing all firmware and microcode\n" +
			"error: target not found: nope\n", "Installing packages", "target not found: nope"},
		{">> installing packages\nerror: target not found: nope\n" +
			"subarchy-install: installing from the mirrors failed; trying again from the image's repository alone\n" +
			"error: target not found: nope\n", "Installing packages", "target not found: nope"},
	} {
		step, why := failReason(c.log)
		if step != c.step || why != c.why {
			t.Errorf("failReason(%.40q) = %q, %q; want %q, %q", c.log, step, why, c.step, c.why)
		}
	}
	got := wrap("Subarchy installation stopped: an encrypted volume named root is already open", 30)
	want := []string{"Subarchy installation stopped:", "an encrypted volume named root", "is already open"}
	if strings.Join(got, "|") != strings.Join(want, "|") {
		t.Errorf("wrap = %q", got)
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
		// Before the first package unpacks, what pacman is doing, not "0 of 4".
		{">> installing packages\nPackages (4) a-1  b-2\n", 50, "Getting the packages ready"},
		// pacman's download lines start with a space.
		{">> installing packages\nPackages (4) a-1  b-2\n:: Retrieving packages...\n a-1 downloading...\n b-2 downloading...\n", 60, "Downloading packages"},
		{">> installing packages\nPackages (4) a-1  b-2\n:: Retrieving packages...\nchecking keyring...\nchecking package integrity...\n", 75, "Checking the packages"},
		{">> installing packages\nPackages (4) a-1  b-2\n\ninstalling a...\ninstalling b...\n", 275, "Installing packages (2 of 4)"},
		// pacstrap's second try counts afresh.
		{">> installing packages\nPackages (4) a\ninstalling a...\ninstalling b...\nPackages (4) a\nchecking keyring...\n", 72, "Checking the package keys"},
		// The hooks after the last package keep the bar moving.
		{">> installing packages\nPackages (2) a b\ninstalling a...\ninstalling b...\n:: Running post-transaction hooks...\n", 450, "Setting up packages"},
		{">> installing packages\nPackages (2) a b\ninstalling a...\ninstalling b...\n:: Running post-transaction hooks...\n" +
			"( 1/10) Creating system user accounts...\n(10/10) Signing EFI binaries...\n", 860, "Setting up packages (10 of 10)"},
		{">> installing packages\nPackages (2) a b\ninstalling a...\ninstalling b...\n:: Running post-transaction hooks...\n" +
			"(1/2) Install DKMS modules\n==> dkms install nvidia -k lts\n==> dkms install nvidia -k zen\n", 511, "Setting up packages (1 of 2)"},
		// With dkms in the package list, its hook takes most of the bar's
		// share for the hooks, and the quick hooks after it the rest.
		{">> installing packages\nPackages (3) dkms-3.2-1  nvidia-open-dkms-580-1  b\ninstalling a...\n:: Running post-transaction hooks...\n" +
			"(1/3) Install DKMS modules\n==> dkms install nvidia -k lts\n==> dkms install nvidia -k zen\n", 561, "Setting up packages (1 of 3)"},
		{">> installing packages\nPackages (3) dkms-3.2-1  nvidia-open-dkms-580-1  b\ninstalling a...\n:: Running post-transaction hooks...\n" +
			"(1/3) Install DKMS modules\n==> dkms install nvidia -k lts\n(2/3) Updating fontconfig cache...\n", 861, "Setting up packages (2 of 3)"},
		{">> installing packages\nPackages (2) a b\ninstalling a...\ninstalling b...\n>> configuring the system\n" +
			strings.Repeat("x\n", 180), 918, "Configuring the system"},
		{">> configuring the system\n" + strings.Repeat("x\n", 5000) + ">> finishing\n", 990, "Finishing"},
	} {
		if at, _, label := progressOf(c.log); at != c.at || label != c.label {
			t.Errorf("progressOf(%.40q) = %d, %q; want %d, %q", c.log, at, label, c.at, c.label)
		}
	}
	// A hook that prints nothing: the bar creeps towards the end of its
	// share, and never reaches it.
	log := ">> installing packages\nPackages (2) dkms-3.2-1  b\ninstalling a...\n:: Running post-transaction hooks...\n(1/2) Install DKMS modules\n"
	at, until, _ := progressOf(log)
	if until <= at {
		t.Fatalf("progressOf: at %d, until %d", at, until)
	}
	if creep(at, until, 0) != at || creep(at, until, creepTime) != at+(until-at)/2 || creep(at, until, time.Hour) >= until {
		t.Errorf("creep(%d, %d): %d, %d, %d", at, until, creep(at, until, 0), creep(at, until, creepTime), creep(at, until, time.Hour))
	}
	// Unpacking moves per package; it does not creep.
	if at, until, _ := progressOf(">> installing packages\nPackages (2) a b\ninstalling a...\n"); until != at {
		t.Errorf("unpacking at %d creeps to %d", at, until)
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
		e.logTail = func(int) []string {
			t.Error("the failure screen read the whole log, earlier runs included")
			return nil
		}
		var did []string
		s, g, out := testScreens(t, append(append([]string{}, answers...), extra...)...)
		e.action = func(what string) error {
			// Rebooting and powering off hand over a console in its own colours.
			if what != "log" && !strings.HasSuffix(out.String(), "\x1b[0m\x1b]R\x1b[2J\x1b[H") {
				t.Errorf("%s with the installer's palette still loaded", what)
			}
			did = append(did, what)
			return nil
		}
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
			// Appended, as subarchy-install does (tee -a). Rewriting the file
			// truncates it first, and a frame drawn at that moment takes the
			// log for a fresh one and reads the old run's lines.
			f, err := os.OpenFile(e.installLog, os.O_APPEND|os.O_WRONLY, 0o644)
			if err != nil {
				t.Fatal(err)
			}
			f.WriteString(">> partitioning /dev/vda\n")
			if fail {
				f.WriteString("\x1b[1;33mWARNING\x1b[0m: colour\nerror: target not found: nope\n")
			}
			f.Close()
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
	code, did, out = setupRun([]string{"View the full log", "Power off", "Open a shell"}, true)
	// The reason is what the log said, not the exit status, and the log
	// lines shown are this run's.
	if code != 1 || len(did) != 2 || did[0] != "log" || did[1] != "poweroff" ||
		!strings.Contains(out, "installation stopped: target not found: nope") ||
		!strings.Contains(out, "It stopped at this step: Partitioning the disk") || !strings.Contains(out, "WARNING: colour") ||
		strings.Contains(out, "[1;33m") || strings.Contains(out, "old run") || strings.Contains(out, "exit status 1") {
		t.Errorf("failure: exit %d, did %v:\n%s", code, did, out)
	}
	if !strings.HasSuffix(out, "\x1b]R\x1b[2J\x1b[H") {
		t.Error("the shell gets the installer's palette")
	}
}

// The install view: the heading with the timer at the column's right
// edge, the status and tip centred, and the log window on L.
func TestInstallViewLayout(t *testing.T) {
	s, _, out := testScreens(t)
	s.height = func() int { return 60 }
	plain := func() []string {
		text := ansi.ReplaceAllString(out.String(), "")
		text = strings.NewReplacer("\x1b[K", "", "\x1b[J", "", "\x1b[H", "").Replace(text)
		return strings.Split(text, "\n")
	}
	find := func(lines []string, part string) string {
		for _, l := range lines {
			if strings.Contains(l, part) {
				return l
			}
		}
		t.Fatalf("no line with %q in:\n%s", part, strings.Join(lines, "\n"))
		return ""
	}
	s.poll = func() (func() byte, func()) { return func() byte { return 0 }, func() {} }
	s.drawProgress(420, "Installing packages (3 of 9)", 75*time.Second, "A tip.", []string{"line one", "line two"}, false)
	lines := plain()
	pad, width := s.pad(), logoWidth()
	heading := find(lines, "Installing Subarchy")
	if !strings.HasPrefix(heading, strings.Repeat(" ", pad)+"Installing Subarchy") || !strings.HasSuffix(heading, "1m 15s") ||
		len([]rune(heading)) != pad+width {
		t.Errorf("heading line = %q (pad %d, width %d)", heading, pad, width)
	}
	status := find(lines, "Installing packages (3 of 9)")
	if left := len(status) - len(strings.TrimLeft(status, " ")); left != pad+(width-len("Installing packages (3 of 9)"))/2 {
		t.Errorf("status starts at %d: %q", left, status)
	}
	find(lines, "Press L to show the log")
	if strings.Contains(out.String(), "line one") {
		t.Error("log shown while switched off")
	}
	// The mark sits in the middle: as many blank lines above as the rows allow.
	if blank := s.top(len(logoLines()) + 10); blank != 20 || strings.TrimSpace(strings.Join(lines[:blank], "")) != "" || strings.TrimSpace(lines[blank]) == "" {
		t.Errorf("mark not centred: top %d", blank)
	}
	out.Reset()
	long := "Boot0004* UEFI SSD " + strings.Repeat("HD(1,GPT,7d992193)/", 10) + `\EFI\Boot\BootX64.efi`
	s.drawProgress(420, "x", time.Second, "A tip.", []string{"line one", "bad\x1b[2Jline", "\x1b[1;33mWARNING:\x1b[0m order \x1b]0;title\x07changed", long}, true)
	lines = plain()
	find(lines, "Press L to hide the log")
	find(lines, "line one")
	if box := find(lines, "line one"); !strings.HasPrefix(strings.TrimLeft(box, " "), "│ line one") || !strings.HasSuffix(box, "│") {
		t.Errorf("log line not in a box: %q", box)
	}
	find(lines, "┌─ install log ─")
	find(lines, "└─")
	if strings.Contains(out.String(), "bad\x1b[2J") || strings.Contains(out.String(), "[2J") || strings.Contains(out.String(), "[1;33m") {
		t.Error("control bytes from the log reached the screen")
	}
	find(lines, "│ badline ")
	find(lines, "│ WARNING: order changed ")
	// A line too long for the box is cut with an ellipsis, and the box's
	// right edge stays in line.
	cut, first := find(lines, "Boot0004*"), find(lines, "line one")
	if !strings.HasSuffix(cut, "… │") || len([]rune(cut)) != len([]rune(first)) {
		t.Errorf("long log line = %q", cut)
	}
	if got := tail("a\n\n  \nb\rc\r\nd\n", 2); len(got) != 2 || got[0] != "c\r" && got[0] != "c" || got[1] != "d" {
		t.Errorf("tail = %q", got)
	}
	// On a short screen the log window shrinks to fit under the mark, and
	// the frame never has more lines than the screen.
	s.height = func() int { return 33 }
	out.Reset()
	s.drawProgress(420, "x", time.Second, "A tip.", strings.Fields(strings.Repeat("logline ", 12)), true)
	lines = plain()
	if n := strings.Count(strings.Join(lines, "\n"), "logline"); n != 33-1-20-3 || len(lines)-1 > 32 || !strings.Contains(out.String(), "\x1b[0;32m") {
		t.Errorf("short screen: %d log lines, %d lines in the frame", n, len(lines))
	}
	s.height = func() int { return 24 } // too short for both: the log replaces the mark
	out.Reset()
	s.drawProgress(420, "x", time.Second, "A tip.", strings.Fields(strings.Repeat("logline ", 12)), true)
	if n := strings.Count(out.String(), "logline"); n != 24-1-10-3 || strings.Contains(out.String(), "\x1b[0;32m") || len(plain())-1 > 23 {
		t.Errorf("very short screen: %d log lines, mark drawn: %v", n, strings.Contains(out.String(), "\x1b[0;32m"))
	}
	if centre("ab", 6) != "  ab" || centre("abcdef", 4) != "abcdef" {
		t.Error("centre")
	}
	// Every tip fits the column, so it is centred under the bar.
	for _, tip := range tips {
		if n := len([]rune("Tip: " + tip)); n > logoWidth() || strings.Contains(tip, "`") {
			t.Errorf("tip %q: %d columns (the column is %d), or Markdown", tip, n, logoWidth())
		}
	}
}

// L during the install switches the log window on.
func TestInstallViewLogToggle(t *testing.T) {
	s, _, out := testScreens(t)
	keys := []byte{'l'}
	s.poll = func() (func() byte, func()) {
		return func() byte {
			if len(keys) == 0 {
				return 0
			}
			k := keys[0]
			keys = keys[1:]
			return k
		}, func() {}
	}
	log := filepath.Join(t.TempDir(), "install.log")
	os.WriteFile(log, nil, 0o644)
	stop := s.progress(log)
	os.WriteFile(log, []byte(">> partitioning /dev/vda\nsgdisk says hello\n"), 0o644)
	stop() // draws a last frame, with the log as it now is
	if !strings.Contains(out.String(), "Press L to hide the log") || !strings.Contains(out.String(), "sgdisk says hello") {
		t.Errorf("log window not shown after L:\n%s", out.String())
	}
}
