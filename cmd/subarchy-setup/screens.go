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
	"regexp"
	"sort"
	"strings"
	"time"
	"unicode"

	"golang.org/x/sys/unix"
	"golang.org/x/term"

	"git.subcult.tv/subculture-collective/subarchy/internal/setup"
)

// logo is the SUBCULT mark as ANSI art, in the installer's palette: the
// letters in acid, their highlights in paper.
//
//go:embed logo.ans
var logo string

var ansi = regexp.MustCompile("\x1b\\[[0-9;]*m")

func logoLines() []string { return strings.Split(strings.TrimRight(logo, "\n"), "\n") }

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
	// height is the screen's height in rows; nil counts as unknown.
	height func() int
	// key waits for Return (true) or Escape (false).
	key func() bool
	// poll starts reading single key presses without waiting: next
	// returns 0 when none is pending, and restore puts the terminal back.
	// nil means no keys are read during the install.
	poll func() (next func() byte, restore func())
	// fit sets a console font that suits the screen's resolution; nil in
	// tests.
	fit func()
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
	for _, line := range logoLines() {
		if n := len([]rune(ansi.ReplaceAllString(line, ""))); n > w {
			w = n
		}
	}
	return w
}

// drawLogo prints the mark at the column's left edge.
func (s *screens) drawLogo() {
	for _, l := range logoLines() {
		fmt.Fprintf(s.out, "%*s%s\x1b[0m\x1b[K\n", s.pad(), "", l)
	}
}

// top is how many blank lines go above a block that many lines tall to
// put it in the middle of the screen.
func (s *screens) top(block int) int {
	rows := 0
	if s.height != nil {
		rows = s.height()
	}
	if t := (rows - block) / 2; t > 1 {
		return t
	}
	return 1
}

// questionBlock is the height a question screen is centred as: the mark,
// a title with a few lines of text, and a list.
const questionBlock = 30

func (s *screens) padding() string { return fmt.Sprintf("0 0 0 %d", s.pad()) }

// sgr is the escape sequence for a palette colour as text colour: 30-37
// for the first eight, 90-97 for the bright eight.
func sgr(colour string) string {
	n := int(colour[0] - '0')
	if len(colour) > 1 || n > 7 {
		return fmt.Sprintf("\x1b[9%dm", n-8)
	}
	return fmt.Sprintf("\x1b[3%dm", n)
}

func (s *screens) line(colour, text string) {
	fmt.Fprintf(s.out, "%*s%s%s\x1b[0m\n", s.pad(), "", sgr(colour), text)
}

// page clears the screen and draws the mark, a title and body lines.
func (s *screens) page(title string, body ...string) {
	if s.fit != nil {
		s.fit()
	}
	fmt.Fprint(s.out, "\x1b[2J\x1b[H"+strings.Repeat("\n", s.top(questionBlock)))
	s.drawLogo()
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
		// gum splits --selected on commas and drops a backslash in front of
		// any character, so a comma or backslash in the row is escaped.
		args = append(args, "--selected", strings.NewReplacer(`\`, `\\`, ",", `\,`).Replace(selected))
	}
	out, code := s.gum(append(args, options...)...)
	if code != 0 || out == "" {
		return "", errBack
	}
	return out, nil
}

// filter is a list to search by typing. What is typed matches as a
// substring, in list order, not fuzzily, so "chi" lists America/Chicago
// first rather than a name that merely starts with a C.
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
		"--match.foreground", colAcid, "--no-fuzzy"}
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
	// gum's own margins would put the question and the first button a
	// column right of the page's text; the buttons keep their gap.
	out, code := s.gum("confirm", question, "--affirmative", yes, "--negative", no,
		fmt.Sprintf("--default=%t", def), "--padding", s.padding(),
		"--prompt.margin", "0", "--selected.margin", "0 2 0 0", "--unselected.margin", "0 2 0 0",
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

// languages are the system languages offered: name, locale, and the
// keyboard most people with that language use, which becomes the
// keyboard screen's preselection. Only languages the installed fonts
// cover are listed.
var languages = [][3]string{
	{"English (US)", "en_US.UTF-8", "us"}, {"English (UK)", "en_GB.UTF-8", "uk"},
	{"Bulgarian", "bg_BG.UTF-8", "bg-cp1251"}, {"Catalan", "ca_ES.UTF-8", "es"}, {"Croatian", "hr_HR.UTF-8", "croat"},
	{"Czech", "cs_CZ.UTF-8", "cz"}, {"Danish", "da_DK.UTF-8", "dk-latin1"}, {"Dutch", "nl_NL.UTF-8", "nl"},
	{"Estonian", "et_EE.UTF-8", "et"}, {"Finnish", "fi_FI.UTF-8", "fi"}, {"French", "fr_FR.UTF-8", "fr-latin1"},
	{"French (Canada)", "fr_CA.UTF-8", "cf"}, {"German", "de_DE.UTF-8", "de-latin1"},
	{"German (Switzerland)", "de_CH.UTF-8", "de_CH-latin1"}, {"Greek", "el_GR.UTF-8", "gr"},
	{"Hungarian", "hu_HU.UTF-8", "hu"}, {"Icelandic", "is_IS.UTF-8", "is-latin1"}, {"Italian", "it_IT.UTF-8", "it"},
	{"Latvian", "lv_LV.UTF-8", "lv"}, {"Lithuanian", "lt_LT.UTF-8", "lt"}, {"Norwegian", "nb_NO.UTF-8", "no-latin1"},
	{"Polish", "pl_PL.UTF-8", "pl"}, {"Portuguese", "pt_PT.UTF-8", "pt-latin1"},
	{"Portuguese (Brazil)", "pt_BR.UTF-8", "br-abnt2"}, {"Romanian", "ro_RO.UTF-8", "ro"},
	{"Russian", "ru_RU.UTF-8", "ru"}, {"Slovak", "sk_SK.UTF-8", "sk-qwertz"}, {"Slovenian", "sl_SI.UTF-8", "slovene"},
	{"Spanish", "es_ES.UTF-8", "es"}, {"Spanish (Latin America)", "es_MX.UTF-8", "la-latin1"},
	{"Swedish", "sv_SE.UTF-8", "sv-latin1"}, {"Turkish", "tr_TR.UTF-8", "trq"}, {"Ukrainian", "uk_UA.UTF-8", "ua"},
}

// language picks the installed system's language. The installer itself
// stays in English.
func (s *screens) language(a *setup.Answers, e env) error {
	s.page("Let's set up your machine.", "This sets the language of the installed system; the installer stays in English.",
		"Escape goes back a step on every screen.")
	var labels []string
	selected := ""
	byLabel := map[string][3]string{}
	for _, l := range languages {
		if !setup.HasLocale(e.localeGen, l[1]) {
			continue
		}
		labels = append(labels, l[0])
		byLabel[l[0]] = l
		if l[1] == a.Locale {
			selected = l[0]
		}
	}
	if len(labels) < 2 {
		return nil // nothing to choose from: English it is
	}
	label, err := s.choose("Language", labels, selected)
	if err != nil {
		return err
	}
	if l := byLabel[label]; l[1] != a.Locale {
		// A new language moves the keyboard preselection to its usual layout.
		a.Locale = l[1]
		if setup.ValidKeymap(e.keymaps, l[2]) == nil {
			a.Keymap = l[2]
		}
	}
	return nil
}

// zones lists the time zones under dir ("Europe/Berlin"), sorted. The
// list comes from tzdata's zone.tab and zone1970.tab, which name each
// country's zones by a city, so the old alias names (US/Central,
// Canada/Eastern) stay out of it. Without those tables, every zone file
// counts.
func zones(dir string) []string {
	seen := map[string]bool{"UTC": true}
	for _, table := range []string{"zone.tab", "zone1970.tab"} {
		data, err := os.ReadFile(filepath.Join(dir, table))
		if err != nil {
			continue
		}
		for _, line := range strings.Split(string(data), "\n") {
			f := strings.Fields(line)
			if len(f) < 3 || strings.HasPrefix(f[0], "#") {
				continue
			}
			if info, err := os.Stat(filepath.Join(dir, f[2])); err == nil && !info.IsDir() {
				seen[f[2]] = true
			}
		}
	}
	if len(seen) > 1 {
		out := make([]string, 0, len(seen))
		for z := range seen {
			out = append(out, z)
		}
		sort.Strings(out)
		return out
	}
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
	a := setup.Answers{Repo: repo, CmdlineExtra: cmdlineExtra, Hostname: "subarchy", Timezone: "UTC", Keymap: "us", Locale: "en_US.UTF-8"}
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
		func() error { return s.language(&a, e) },
		func() error { return s.keyboard(&a, e) },
		func() error { return s.account(&a, e, &separate) },
		func() error { return s.disk(&a, e, disks) },
		func() error { return s.summary(a, separate) },
		func() error { return s.erase(a) },
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
	if s.fit != nil {
		s.fit()
	}
	fmt.Fprint(s.out, "\x1b[2J\x1b[H\x1b[?25l"+strings.Repeat("\n", s.top(len(logoLines())+4)))
	s.drawLogo()
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
	s.page("Let's set up your machine.")
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
	// The time zone and the computer name belong to the machine, not the
	// account; they keep their places in the order.
	const title, machine = "Let's set up your account.", "Let's set up your machine."
	s.page(machine)
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
	if a.Hostname, err = s.ask(machine, "Computer name", "Letters, digits and dashes", a.Hostname, setup.ValidHostname); err != nil {
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
	// Secrets show as set, never as one star per character: the length
	// would be on the screen.
	const hidden = "set (hidden)"
	passphrase := "same as the password"
	if separate {
		passphrase = hidden
	}
	for _, row := range [][2]string{
		{"Language", a.Locale}, {"Keyboard", a.Keymap}, {"Time zone", a.Timezone}, {"User name", a.Username},
		{"Password", hidden}, {"Computer name", a.Hostname}, {"Disk passphrase", passphrase},
		{"Install disk", a.Disk + " (erased)"},
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

// disk picks the target, shows what is on it and offers the read-only
// browse. The summary and the erase question come after it.
func (s *screens) disk(a *setup.Answers, e env, disks []setup.Disk) error {
	// The list opens on the disk looked at last, or chosen before the
	// summary; on the first visit, at the top.
	last := a.Disk
	for {
		s.page("Where should Subarchy go?", "The disk you choose is erased. The others are not touched.")
		var rows []string
		selected := ""
		byRow := map[string]setup.Disk{}
		for _, d := range disks {
			row := d.String() + "  [" + contents(d) + "]"
			rows = append(rows, row)
			byRow[row] = d
			if d.Path == last {
				selected = row
			}
		}
		row, err := s.choose("Install disk", rows, selected)
		if err != nil {
			return err
		}
		d := byRow[row]
		last = d.Path
		const install, look, other = "Install here", "Browse it read-only first", "Choose a different disk"
		for {
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
				if err := e.browse(d, s.beforeLook(d.Path)); err != nil {
					s.notice(capital(err.Error()))
				}
				continue
			}
			a.Disk = d.Path
			return nil
		}
	}
}

// beforeLook is the page before the browse: what it opens, what it
// leaves closed and how to come back. Return opens the file manager.
func (s *screens) beforeLook(path string) func(opened, closed []string) bool {
	return func(opened, closed []string) bool {
		title, body := lookPage(path, opened, closed)
		s.page(title, body...)
		if len(opened) == 0 {
			s.line(colPaper, "Press Return to go back.")
			s.key()
			return false
		}
		s.line(colPaper, "Press Return to open it, or Escape to go back.")
		return s.key()
	}
}

// erase is the last question, after the summary: the only one whose
// default is no.
func (s *screens) erase(a setup.Answers) error {
	s.page("Everything on "+a.Disk+" will be erased.", "There is no way to get it back.")
	yes, err := s.confirm("Erase "+a.Disk+" and install Subarchy?", "Yes, erase and install", "No, go back", false)
	if err != nil || !yes {
		return errBack
	}
	return nil
}

// contents is the one-line summary of a disk's partitions for the list.
func contents(d setup.Disk) string {
	if len(d.Parts) == 0 {
		return "empty"
	}
	var kinds []string
	for _, p := range d.Parts {
		if p.FSType != "" {
			kinds = append(kinds, p.Kind()) // as the disk's own screen writes it
		}
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

// terminus is the Terminus console fonts by glyph width in pixels. The
// "i" set (code page 437) is the one with the half blocks and the dark
// shade the mark is drawn with; the wider "v" set shows them as "#".
var terminus = []struct {
	width int
	name  string
}{{16, "ter-i32b"}, {14, "ter-i28b"}, {12, "ter-i24b"}, {11, "ter-i22b"}, {10, "ter-i20b"}, {8, "ter-i16b"}}

// fontFor picks the largest Terminus font that still leaves 100 columns
// on a screen that many pixels wide: 32 px tall on a 1920 or 4K panel,
// 24 px at 1280.
func fontFor(pixels int) (width int, name string) {
	for _, f := range terminus {
		if pixels/f.width >= 100 {
			return f.width, f.name
		}
	}
	last := terminus[len(terminus)-1]
	return last.width, last.name
}

// fitFont sets the console font from the framebuffer's width. It runs
// before every screen, not once: the graphics driver can take the
// console over after the installer has started, which puts the kernel's
// small font back.
func fitFont() {
	data, err := os.ReadFile("/sys/class/graphics/fb0/virtual_size")
	if err != nil {
		return
	}
	var pixels, height int
	if _, err := fmt.Sscanf(strings.TrimSpace(string(data)), "%d,%d", &pixels, &height); err != nil || pixels == 0 {
		return
	}
	cols, _, err := term.GetSize(int(os.Stdout.Fd()))
	if err != nil || cols == 0 {
		return
	}
	width, name := fontFor(pixels)
	if pixels/cols == width {
		return
	}
	args := []string{name}
	if tty, err := os.Readlink("/proc/self/fd/0"); err == nil {
		args = []string{"-C", tty, name}
	}
	exec.Command("setfont", args...).Run()
}

// prepareConsole sets the palette.
func prepareConsole(out io.Writer) {
	for i := 0; i < 16; i++ {
		fmt.Fprintf(out, "\x1b]P%X%s", i, palette[i])
	}
	fmt.Fprint(out, "\x1b[37;40m\x1b[2J\x1b[H")
}

// restoreConsole undoes prepareConsole before the installer hands the
// console on: the default attributes, the console's default palette
// (Linux's "ESC ] R"), and a clear screen.
func restoreConsole(out io.Writer) {
	fmt.Fprint(out, "\x1b[0m\x1b]R\x1b[2J\x1b[H")
}

func realScreens() *screens {
	fd := int(os.Stdin.Fd())
	return &screens{
		fit: func() {
			fitFont()
			// The palette goes with the font: a console the graphics
			// driver has just taken over has the default colours again.
			for i := 0; i < 16; i++ {
				fmt.Fprintf(os.Stdout, "\x1b]P%X%s", i, palette[i])
			}
		},
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
		height: func() int {
			if _, h, err := term.GetSize(int(os.Stdout.Fd())); err == nil {
				return h
			}
			return 0
		},
		poll: pollKeys,
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

// pollKeys puts the terminal in a mode where a read returns at once, with
// a key if one was pressed, so the install view can watch for a key
// between frames without a reader left blocked on the terminal afterwards.
func pollKeys() (next func() byte, restore func()) {
	fd := int(os.Stdin.Fd())
	state, err := term.MakeRaw(fd)
	if err != nil {
		return func() byte { return 0 }, func() {}
	}
	if t, err := unix.IoctlGetTermios(fd, unix.TCGETS); err == nil {
		t.Cc[unix.VMIN], t.Cc[unix.VTIME] = 0, 0
		// Output processing back on: the frames use plain newlines.
		t.Oflag |= unix.OPOST | unix.ONLCR
		unix.IoctlSetTermios(fd, unix.TCSETS, t)
	}
	buf := make([]byte, 16)
	return func() byte {
			n, _ := unix.Read(fd, buf)
			if n < 1 {
				return 0
			}
			return buf[n-1]
		}, func() {
			term.Restore(fd, state)
		}
}
