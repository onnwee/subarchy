package main

// The full-screen installer (issue #124): one cleared screen per question
// with the SUBCULT mark on top, pick lists for the keyboard, time zone and
// disk, a summary table, and Escape to go back a step. The flow and the
// keyboard table follow Omarchy's installer (omarchy-iso's configurator
// and install/provisioning/setup-form.sh, MIT, (c) David Heinemeier
// Hansson); the code here is Subarchy's. gum draws the lists and inputs.
// The plain prompts in main.go stay for serial consoles.

import (
	_ "embed"
	"errors"
	"fmt"
	"io"
	"os"
	"os/exec"
	"path/filepath"
	"sort"
	"strings"
	"time"
	"unicode"

	"golang.org/x/term"

	"git.subcult.tv/subculture-collective/subarchy/internal/setup"
)

//go:embed logo.txt
var logo string

// errBack is a step's way of saying "go to the previous step".
var errBack = errors.New("back")

// The console palette, set once: SUBCULT's ink, paper, violet and acid in
// the slots gum's colour numbers pick from.
const (
	colRed    = "1"
	colAcid   = "2"
	colViolet = "5"
	colPaper  = "7"
	colMuted  = "8"
)

var palette = map[int]string{
	0: "100B19", 1: "FF5C7A", 2: "00FF88", 3: "FFD166", 4: "8B5CF6", 5: "8B5CF6", 6: "00FF88", 7: "F0ECE4",
	8: "6F6885", 9: "FF5C7A", 10: "00FF88", 11: "FFD166", 12: "A78BFA", 13: "A78BFA", 14: "00FF88", 15: "FFFFFF",
}

// gumFn runs gum with the terminal attached and returns what it printed
// and its exit status.
type gumFn func(args ...string) (out string, code int)

type screens struct {
	out   io.Writer
	gum   gumFn
	width func() int
	// key waits for Return (true) or Escape (false).
	key func() bool
}

func (s *screens) pad() int {
	p := (s.width() - logoWidth()) / 2
	if p < 0 {
		p = 0
	}
	return p
}

func logoWidth() int {
	w := 0
	for _, line := range strings.Split(logo, "\n") {
		if n := len([]rune(strings.TrimRight(line, " "))); n > w {
			w = n
		}
	}
	return w
}

func (s *screens) padding() string { return fmt.Sprintf("0 0 0 %d", s.pad()) }

func (s *screens) line(colour, text string) {
	fmt.Fprintf(s.out, "%*s\x1b[3%sm%s\x1b[0m\n", s.pad(), "", colour, text)
}

// page clears the screen and draws the mark, a title and body lines.
func (s *screens) page(title string, body ...string) {
	fmt.Fprint(s.out, "\x1b[2J\x1b[H\n")
	for _, l := range strings.Split(strings.TrimRight(logo, "\n"), "\n") {
		s.line(colAcid, l)
	}
	fmt.Fprintln(s.out)
	if title != "" {
		s.line(colPaper, title)
	}
	for _, l := range body {
		s.line(colMuted, l)
	}
	fmt.Fprintln(s.out)
}

// notice shows why an answer was refused, briefly, under the page.
func (s *screens) notice(msg string) {
	s.line(colRed, msg)
	time.Sleep(1200 * time.Millisecond)
}

func (s *screens) choose(header string, options []string, selected string) (string, error) {
	args := []string{"choose", "--height", "12", "--header", header, "--padding", s.padding(),
		"--cursor.foreground", colAcid, "--header.foreground", colViolet, "--selected.foreground", colAcid}
	if selected != "" {
		args = append(args, "--selected", selected)
	}
	out, code := s.gum(append(args, options...)...)
	if code != 0 || out == "" {
		return "", errBack
	}
	return out, nil
}

func (s *screens) filter(header string, options []string, first string) (string, error) {
	// The likely answer goes first, so Return alone accepts it.
	list := []string{first}
	for _, o := range options {
		if o != first {
			list = append(list, o)
		}
	}
	args := []string{"filter", "--height", "12", "--header", header, "--padding", s.padding(),
		"--placeholder", "Type to search", "--indicator.foreground", colAcid, "--header.foreground", colViolet,
		"--match.foreground", colAcid}
	out, code := s.gum(append(args, list...)...)
	if code != 0 || out == "" {
		return "", errBack
	}
	return out, nil
}

func (s *screens) input(prompt, placeholder, value string, password bool) (string, error) {
	args := []string{"input", "--prompt", prompt + "> ", "--placeholder", placeholder, "--padding", s.padding(),
		"--prompt.foreground", colViolet, "--cursor.foreground", colAcid, "--width", "60"}
	if value != "" {
		args = append(args, "--value", value)
	}
	if password {
		args = append(args, "--password")
	}
	out, code := s.gum(args...)
	if code != 0 {
		return "", errBack
	}
	return out, nil
}

// confirm returns the answer; Escape counts as back.
func (s *screens) confirm(question, yes, no string, def bool) (bool, error) {
	out, code := s.gum("confirm", question, "--affirmative", yes, "--negative", no,
		fmt.Sprintf("--default=%t", def), "--padding", s.padding(),
		"--prompt.foreground", colPaper, "--selected.background", colAcid, "--selected.foreground", "0",
		"--unselected.foreground", colPaper, "--unselected.background", "0")
	_ = out
	switch code {
	case 0:
		return true, nil
	case 1:
		return false, nil
	}
	return false, errBack
}

// keyboards is Omarchy's labelled list of console keymaps, without the
// entries that need an input method. The four English ones lead.
var keyboards = [][2]string{
	{"English (US)", "us"}, {"English (UK)", "uk"}, {"English (US, Dvorak)", "dvorak"}, {"English (US, Colemak)", "colemak"},
	{"Belarusian", "by"}, {"Belgian", "be-latin1"}, {"Bulgarian", "bg-cp1251"}, {"Croatian", "croat"}, {"Czech", "cz"},
	{"Danish", "dk-latin1"}, {"Dutch", "nl"}, {"Estonian", "et"}, {"Finnish", "fi"}, {"French", "fr-latin1"},
	{"French (Canada)", "cf"}, {"French (Switzerland)", "fr_CH-latin1"}, {"Georgian", "ge"}, {"German", "de-latin1"},
	{"German (Switzerland)", "de_CH-latin1"}, {"Greek", "gr"}, {"Hebrew", "il"}, {"Hungarian", "hu"},
	{"Icelandic", "is-latin1"}, {"Irish", "ie"}, {"Italian", "it"}, {"Japanese", "jp106"}, {"Kazakh", "kazakh"},
	{"Kyrgyz", "kyrgyz"}, {"Latvian", "lv"}, {"Lithuanian", "lt"}, {"Macedonian", "mk-utf"}, {"Norwegian", "no-latin1"},
	{"Polish", "pl"}, {"Portuguese", "pt-latin1"}, {"Portuguese (Brazil)", "br-abnt2"}, {"Romanian", "ro"},
	{"Russian", "ru"}, {"Serbian", "sr-latin"}, {"Slovak", "sk-qwertz"}, {"Slovenian", "slovene"}, {"Spanish", "es"},
	{"Spanish (Latin American)", "la-latin1"}, {"Swedish", "sv-latin1"}, {"Tajik", "tj_alt-UTF8"}, {"Turkish", "trq"},
	{"Ukrainian", "ua"},
}

// zones lists the time zones under dir ("Europe/Berlin"), sorted.
func zones(dir string) []string {
	var out []string
	filepath.WalkDir(dir, func(path string, d os.DirEntry, err error) error {
		if err != nil || d.IsDir() {
			return nil
		}
		rel, _ := filepath.Rel(dir, path)
		// Only real zones: "Region/City" names and UTC, not posix/, right/
		// or the tables beside them.
		first, _, nested := strings.Cut(rel, "/")
		if rel == "UTC" || (nested && first != "Etc" && unicode.IsUpper([]rune(first)[0])) {
			out = append(out, rel)
		}
		return nil
	})
	sort.Strings(out)
	return out
}

// collectScreens asks every question on full screens and returns the
// answers once the user has confirmed erasing the disk. errBack from the
// first step means the user left the installer.
func collectScreens(s *screens, e env, repo, cmdlineExtra string) (setup.Answers, error) {
	a := setup.Answers{Repo: repo, CmdlineExtra: cmdlineExtra, Hostname: "subarchy", Timezone: "UTC", Keymap: "us"}
	raw, err := e.lsblk()
	if err != nil {
		return a, fmt.Errorf("list disks: %w", err)
	}
	disks, err := setup.Disks(raw, e.installMedia())
	if err != nil {
		return a, err
	}
	if len(disks) == 0 {
		return a, fmt.Errorf("no disk of at least %s found", setup.HumanSize(setup.MinDiskBytes))
	}
	separate := false
	steps := []func() error{
		func() error { return s.greeter() },
		func() error { return s.keyboard(&a, e) },
		func() error { return s.account(&a, e, &separate) },
		func() error { return s.summary(a, separate) },
		func() error { return s.disk(&a, e, disks) },
	}
	for i := 0; i < len(steps); {
		err := steps[i]()
		switch {
		case err == nil:
			i++
		case errors.Is(err, errBack) && i > 0:
			i--
		default:
			return a, err
		}
	}
	return a, nil
}

func (s *screens) greeter() error {
	fmt.Fprint(s.out, "\x1b[2J\x1b[H\x1b[?25l\n\n\n\n")
	for _, l := range strings.Split(strings.TrimRight(logo, "\n"), "\n") {
		s.line(colAcid, l)
	}
	fmt.Fprintln(s.out)
	s.line(colPaper, "A SUBCULT system, built on Arch.")
	fmt.Fprintln(s.out)
	s.line(colMuted, "Press Return to start the install, or Escape for a shell.")
	ok := s.key()
	fmt.Fprint(s.out, "\x1b[?25h")
	if !ok {
		return errBack
	}
	return nil
}

func (s *screens) keyboard(a *setup.Answers, e env) error {
	s.page("Let's set up your machine.", "Escape goes back a step on every screen.")
	var labels []string
	selected := ""
	byLabel := map[string]string{}
	for _, k := range keyboards {
		if setup.ValidKeymap(e.keymaps, k[1]) != nil {
			continue
		}
		labels = append(labels, k[0])
		byLabel[k[0]] = k[1]
		if k[1] == a.Keymap {
			selected = k[0]
		}
	}
	label, err := s.choose("Keyboard layout", labels, selected)
	if err != nil {
		return err
	}
	a.Keymap = byLabel[label]
	a.XKBLayout, a.XKBVariant = xkbFor(e.kbdModelMap, a.Keymap)
	// Loaded now, so the password is typed under the layout the installed
	// system asks for it in.
	if e.loadKeymap != nil {
		if err := e.loadKeymap(a.Keymap); err != nil {
			s.notice(fmt.Sprintf("Could not switch this console to %s; it still types as before.", a.Keymap))
		}
	}
	return nil
}

// ask repeats an input until check accepts it.
func (s *screens) ask(title, prompt, placeholder, value string, check func(string) error) (string, error) {
	for {
		s.page(title)
		v, err := s.input(prompt, placeholder, value, false)
		if err != nil {
			return "", err
		}
		if v == "" {
			v = value
		}
		if err := check(v); err != nil {
			s.notice(capital(err.Error()))
			continue
		}
		return v, nil
	}
}

func capital(msg string) string {
	if msg == "" {
		return msg
	}
	return strings.ToUpper(msg[:1]) + msg[1:]
}

// askSecret asks for a secret twice.
func (s *screens) askSecret(title, prompt, placeholder string) (string, error) {
	for {
		s.page(title)
		v, err := s.input(prompt, placeholder, "", true)
		if err != nil {
			return "", err
		}
		again, err := s.input("Confirm", "Type it again", "", true)
		if err != nil {
			return "", err
		}
		if err := setup.ValidSecret(v, again, 8); err != nil {
			s.notice(capital(err.Error()))
			continue
		}
		return v, nil
	}
}

func (s *screens) account(a *setup.Answers, e env, separate *bool) error {
	const title = "Let's set up your account."
	s.page(title)
	tz, err := s.filter("Time zone", zones(e.zoneinfo), a.Timezone)
	if err != nil {
		return err
	}
	a.Timezone = tz
	if a.Username, err = s.ask(title, "User name", "Lowercase letters and digits (like pat)", a.Username, setup.ValidUsername); err != nil {
		return err
	}
	if a.Password, err = s.askSecret(title, "Password", "At least 8 characters"); err != nil {
		return err
	}
	if a.Hostname, err = s.ask(title, "Computer name", "Letters, digits and dashes", a.Hostname, setup.ValidHostname); err != nil {
		return err
	}
	s.page("The disk is always encrypted.", "Its passphrase unlocks the disk at every boot. Losing it loses the data.")
	same, err := s.confirm("Use your password to unlock the disk too?", "Yes, one password", "No, a separate passphrase", true)
	if err != nil {
		return err
	}
	*separate = !same
	a.Passphrase = a.Password
	if !same {
		if a.Passphrase, err = s.askSecret("The disk is always encrypted.", "Disk passphrase", "At least 8 characters"); err != nil {
			return err
		}
	}
	return nil
}

func (s *screens) summary(a setup.Answers, separate bool) error {
	s.page("Here is what you chose.")
	passphrase := "same as the password"
	if separate {
		passphrase = strings.Repeat("*", len(a.Passphrase))
	}
	for _, row := range [][2]string{
		{"Keyboard", a.Keymap}, {"Time zone", a.Timezone}, {"User name", a.Username},
		{"Password", strings.Repeat("*", len(a.Password))}, {"Computer name", a.Hostname}, {"Disk passphrase", passphrase},
	} {
		fmt.Fprintf(s.out, "%*s\x1b[3%sm%-17s\x1b[3%sm%s\x1b[0m\n", s.pad(), "", colViolet, row[0], colPaper, row[1])
	}
	fmt.Fprintln(s.out)
	ok, err := s.confirm("Does this look right?", "Yes", "No, change it", true)
	if err != nil || !ok {
		return errBack
	}
	return nil
}

// disk picks the target, shows what is on it, offers the read-only
// browse, and asks before erasing.
func (s *screens) disk(a *setup.Answers, e env, disks []setup.Disk) error {
	for {
		s.page("Where should Subarchy go?", "The disk you choose is erased. The others are not touched.")
		var rows []string
		byRow := map[string]setup.Disk{}
		for _, d := range disks {
			row := d.String() + "  [" + contents(d) + "]"
			rows = append(rows, row)
			byRow[row] = d
		}
		row, err := s.choose("Install disk", rows, "")
		if err != nil {
			return err
		}
		d := byRow[row]
		const install, look, other = "Install here", "Browse it read-only first", "Choose a different disk"
		for chosen := false; !chosen; {
			var body []string
			if len(d.Parts) == 0 {
				body = append(body, "It has no partitions.")
			}
			for _, p := range d.Parts {
				body = append(body, p.String())
			}
			s.page("On "+d.Path+" now:", body...)
			options := []string{install, other}
			if e.browse != nil {
				options = []string{install, look, other}
			}
			what, err := s.choose(d.String(), options, "")
			if err != nil || what == other {
				break
			}
			if what == look {
				if err := e.browse(d); err != nil {
					s.notice(capital(err.Error()))
				}
				continue
			}
			s.page("Everything on "+d.Path+" will be erased.", "There is no way to get it back.")
			yes, err := s.confirm("Erase "+d.Path+" and install Subarchy?", "Yes, erase and install", "No, go back", false)
			if err == nil && yes {
				a.Disk = d.Path
				return nil
			}
			chosen = true
		}
	}
}

// contents is the one-line summary of a disk's partitions for the list.
func contents(d setup.Disk) string {
	if len(d.Parts) == 0 {
		return "empty"
	}
	var kinds []string
	for _, p := range d.Parts {
		kind := p.FSType
		switch kind {
		case "":
			continue
		case "crypto_LUKS":
			kind = "encrypted"
		case "BitLocker":
			kind = "BitLocker"
		}
		if p.Label != "" {
			kind += " " + p.Label
		}
		kinds = append(kinds, kind)
	}
	if len(kinds) == 0 {
		return fmt.Sprintf("%d partitions", len(d.Parts))
	}
	return strings.Join(kinds, ", ")
}

// onConsole reports whether stdin is a Linux virtual console (tty1…),
// where the full-screen installer can draw; a serial line or an SSH
// session gets the plain prompts.
func onConsole() bool {
	name, err := os.Readlink("/proc/self/fd/0")
	if err != nil || !strings.HasPrefix(name, "/dev/tty") {
		return false
	}
	rest := strings.TrimPrefix(name, "/dev/tty")
	if rest == "" || rest[0] < '0' || rest[0] > '9' {
		return false
	}
	_, err = exec.LookPath("gum")
	return err == nil
}

// prepareConsole sets the palette and a readable font.
func prepareConsole(out io.Writer) {
	for i := 0; i < 16; i++ {
		fmt.Fprintf(out, "\x1b]P%X%s", i, palette[i])
	}
	fmt.Fprint(out, "\x1b[37;40m\x1b[2J\x1b[H")
	font := "ter-v16b"
	if w, _, err := term.GetSize(int(os.Stdout.Fd())); err == nil && w >= 240 {
		font = "ter-v32b" // a high-density screen under the kernel's small font
	}
	exec.Command("setfont", font).Run()
}

func realScreens() *screens {
	fd := int(os.Stdin.Fd())
	return &screens{
		out: os.Stdout,
		gum: func(args ...string) (string, int) {
			cmd := exec.Command("gum", args...)
			cmd.Stdin, cmd.Stderr = os.Stdin, os.Stderr
			cmd.Env = append(os.Environ(), "GUM_CHOOSE_SHOW_HELP=false", "GUM_FILTER_SHOW_HELP=false",
				"GUM_INPUT_SHOW_HELP=false", "GUM_CONFIRM_SHOW_HELP=false")
			out, err := cmd.Output()
			code := 0
			var exit *exec.ExitError
			if errors.As(err, &exit) {
				code = exit.ExitCode()
			} else if err != nil {
				code = 127
			}
			return strings.TrimRight(string(out), "\r\n"), code
		},
		width: func() int {
			if w, _, err := term.GetSize(int(os.Stdout.Fd())); err == nil {
				return w
			}
			return 80
		},
		key: func() bool {
			state, err := term.MakeRaw(fd)
			if err != nil {
				return true
			}
			defer term.Restore(fd, state)
			buf := make([]byte, 8)
			for {
				n, err := os.Stdin.Read(buf)
				if err != nil {
					return false
				}
				// A lone Escape leaves; an escape sequence (arrow keys) does not.
				if n == 1 && buf[0] == 0x1b {
					return false
				}
				if n >= 1 && (buf[0] == '\r' || buf[0] == '\n') {
					return true
				}
			}
		},
	}
}
