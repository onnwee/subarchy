package main

// The install view (issue #124): while subarchy-install runs, the screen
// shows the mark, a bar with a percentage, what is happening, the time
// so far and a rotating tip, in place of the raw command output. The
// output still goes to the install log, which is where the percentage
// is read from. The idea follows Omarchy's install dashboard.

import (
	"fmt"
	"os"
	"regexp"
	"strconv"
	"strings"
	"time"
)

var (
	packagesTotal = regexp.MustCompile(`(?m)^Packages \((\d+)\)`)
	installingPkg = regexp.MustCompile(`(?m)^installing [^ ]+\.\.\.`)
	// pacman prints " linux-zen-7.2.14... downloading..." with a space in front.
	downloading = regexp.MustCompile(`(?m)^ ?[^ ]+ downloading\.\.\.`)
	// pacman's hooks run after the last package unpacks, numbered
	// "( 3/29) Updating linux initcpios...". DKMS modules and the kernel
	// images are built here, which can take minutes.
	hooksStart = regexp.MustCompile(`(?m)^:: Running post-transaction hooks`)
	hookStep   = regexp.MustCompile(`(?m)^\( *(\d+)/(\d+)\) (.*)$`)
)

// slowHooks are the pacman hooks that build things: the DKMS modules
// and the boot images. Each takes slowShare times a quick hook's share
// of the bar, when the package that ships it is in the package list.
var slowHooks = []struct {
	pkg  *regexp.Regexp
	desc string
}{
	{regexp.MustCompile(`\sdkms-\d`), "Install DKMS modules"},
	{regexp.MustCompile(`\smkinitcpio-\d`), "Updating linux initcpios"},
}

const slowShare = 20

// creepTime is how long a hook can print nothing before the bar has
// crept half way to the next hook's share; it never gets there.
const creepTime = time.Minute

// The ">> installing packages" phase in per mille of the whole bar:
// pacman's checks up to unpackAt, unpacking up to hooksAt, and its hooks
// up to the next phase.
const (
	unpackAt = 100
	hooksAt  = 450
)

// pacmanSteps are what pacman prints between the package list and the
// first unpacked package, in order, with the bar's position and what the
// screen says meanwhile. Checking the packages can take half a minute
// from a USB stick.
var pacmanSteps = []struct {
	line  string
	at    int
	label string
}{
	{":: Retrieving packages...", 50, "Downloading packages"},
	{"checking keyring...", 72, "Checking the package keys"},
	{"checking package integrity...", 75, "Checking the packages"},
	{"loading package files...", 85, "Reading the packages"},
	{"checking for file conflicts...", 90, "Checking for file conflicts"},
	{"checking available disk space...", 95, "Checking the free space"},
	{":: Processing package changes...", unpackAt, "Installing packages"},
}

// configureLines is about how many lines the configure phase logs
// (mostly Pult's theme files); it only paces the bar.
const configureLines = 600

// phases are subarchy-install's ">> " lines, in order, with the bar's
// position when each starts (per mille) and what the screen calls it.
var phases = []struct {
	marker string
	start  int
	label  string
}{
	{">> partitioning", 5, "Partitioning the disk"},
	{">> encrypting", 15, "Encrypting the disk"},
	{">> creating btrfs subvolumes", 35, "Creating the filesystem"},
	{">> writing boot configuration", 40, "Preparing the boot setup"},
	{">> installing packages", 50, "Installing packages"},
	{">> configuring the system", 900, "Configuring the system"},
	{">> configuring snapper", 960, "Setting up snapshots"},
	{">> checking the boot entries", 975, "Checking the boot entries"},
	{">> finishing", 990, "Finishing"},
}

// progressOf reads the install log and returns how far the install is,
// in per mille below 1000, how far the bar may creep while the log says
// nothing new (see creep), and the current phase's label.
func progressOf(log string) (at, until int, label string) {
	at, label = 0, "Starting"
	for i, p := range phases {
		idx := strings.Index(log, p.marker)
		if idx < 0 {
			continue
		}
		at, until, label = p.start, 0, p.label
		next := 1000
		if i+1 < len(phases) {
			next = phases[i+1].start
		}
		rest := log[idx:]
		switch p.marker {
		case ">> installing packages":
			at, until, label = packagesProgress(rest, at, label, next)
		case ">> configuring the system":
			lines := strings.Count(rest, "\n")
			if lines > configureLines {
				lines = configureLines
			}
			at = p.start + (next-p.start)*lines/configureLines
		}
	}
	if at > 999 {
		at = 999
	}
	return at, max(at, until), label
}

// creep moves the bar from at towards until while the log has said
// nothing new for quiet: a DKMS build can print nothing for minutes.
func creep(at, until int, quiet time.Duration) int {
	if until <= at || quiet <= 0 {
		return at
	}
	return at + int(int64(until-at)*int64(quiet)/int64(quiet+creepTime))
}

// packagesProgress follows pacstrap's output: pacman's checks, then the
// packages it unpacks, then its hooks, which end at next. When pacstrap
// runs a second time, the last run counts.
func packagesProgress(log string, at int, label string, next int) (int, int, string) {
	found := packagesTotal.FindAllStringSubmatchIndex(log, -1)
	if found == nil {
		return at, 0, label
	}
	last := found[len(found)-1]
	total, _ := strconv.Atoi(log[last[2]:last[3]])
	if total <= 0 {
		return at, 0, label
	}
	rest := log[last[0]:]
	if h := hooksStart.FindAllStringIndex(rest, -1); h != nil {
		list, _, _ := strings.Cut(rest, "\n")
		at, until, label := hooksProgress(rest[h[len(h)-1][1]:], list, next)
		return at, until, label
	}
	if done := len(installingPkg.FindAllStringIndex(rest, -1)); done > 0 {
		if done > total {
			done = total
		}
		return unpackAt + (hooksAt-unpackAt)*done/total, 0, fmt.Sprintf("Installing packages (%d of %d)", done, total)
	}
	// Before the first package unpacks: what pacman is doing.
	at, label = 50, "Getting the packages ready"
	for _, step := range pacmanSteps {
		if strings.Contains(rest, "\n"+step.line) {
			at, label = step.at, step.label
		}
	}
	if label == "Downloading packages" {
		got := len(downloading.FindAllStringIndex(rest, -1))
		if got > total {
			got = total
		}
		at += 20 * got / total
	}
	return at, 0, label
}

// hooksProgress places pacman's hooks between hooksAt and next. A quick
// hook gets one share, a slow one whose package is in the package list
// (list) slowShare; each line a hook prints moves the bar a little
// closer to the next hook's share, and until is where that share ends.
func hooksProgress(hooks, list string, next int) (at, until int, label string) {
	steps := hookStep.FindAllStringSubmatchIndex(hooks, -1)
	if steps == nil {
		return hooksAt, 0, "Setting up packages"
	}
	step := steps[len(steps)-1]
	n, _ := strconv.Atoi(hooks[step[2]:step[3]])
	m, _ := strconv.Atoi(hooks[step[4]:step[5]])
	if n < 1 || n > m {
		return hooksAt, 0, "Setting up packages"
	}
	share := func(desc string) int {
		for _, h := range slowHooks {
			if strings.HasPrefix(desc, h.desc) && h.pkg.MatchString(list) {
				return slowShare
			}
		}
		return 1
	}
	shares := m
	for _, h := range slowHooks {
		if h.pkg.MatchString(list) {
			shares += slowShare - 1
		}
	}
	done := n - 1
	for _, s := range steps[:len(steps)-1] {
		done += share(hooks[s[6]:s[7]]) - 1
	}
	this := share(hooks[step[6]:step[7]])
	if done+this > shares {
		shares = done + this // a slow hook from a package not in the list
	}
	lines := strings.Count(hooks[step[1]:], "\n")
	span := next - hooksAt
	at = hooksAt + span*(done*(lines+8)+this*lines)/(shares*(lines+8))
	until = hooksAt + span*(done+this)/shares
	return at, until, fmt.Sprintf("Setting up packages (%d of %d)", n, m)
}

// tips rotate under the bar while the install runs. Each fits the
// column under the mark with "Tip: " in front.
var tips = []string{
	"Super + Return opens a terminal.",
	"Super + Space opens the launcher.",
	"Super + W closes the window in front.",
	"Super + 1 to 9 switches workspaces; Shift moves a window.",
	"Super + F makes a window full screen.",
	"Super + S shows the scratchpad workspace.",
	"Super + Ctrl + V opens the clipboard history.",
	"subcult update takes a snapshot, then updates the system.",
	"A bad update can be undone: pick a snapshot in the boot menu.",
	"pult apply <theme> recolours the shell, lock and windows.",
	"subcult disk tpm lets the TPM unlock the disk at boot.",
}

// escapes are terminal escape sequences in the log: CSI (colours),
// OSC, and the two-byte ones.
var escapes = regexp.MustCompile("\x1b(\\[[0-?]*[ -/]*[@-~]|\\][^\x07\x1b]*(\x07|\x1b\\\\)?|[@-_])")

// plainLine is a log line as text the screen can show: no escape
// sequences or control bytes, which would colour the screen or move the
// cursor.
func plainLine(l string) string {
	return strings.Map(func(r rune) rune {
		if r < 0x20 || r == 0x7f {
			return -1
		}
		return r
	}, escapes.ReplaceAllString(l, ""))
}

// clip cuts a line to width columns, with an ellipsis where it was cut.
func clip(l string, width int) string {
	if r := []rune(l); len(r) > width && width > 0 {
		return string(r[:width-1]) + "…"
	}
	return l
}

func bar(permille, width int) string {
	full := width * permille / 1000
	return strings.Repeat("█", full) + strings.Repeat("░", width-full)
}

// logWindow is how many lines of the log the install view shows when
// the log is switched on.
const logWindow = 12

// boxLines is what the log box adds around its lines: a gap above it and
// its top and bottom edges.
const boxLines = 3

// centre pads text to sit in the middle of a column that wide.
func centre(text string, width int) string {
	n := len([]rune(text))
	if n >= width {
		return text
	}
	return strings.Repeat(" ", (width-n)/2) + text
}

// drawProgress paints one frame of the install view, in the middle of
// the screen: the mark; "Installing Subarchy" with the time so far at
// the column's right edge; the bar; the status and a tip, centred; and,
// when switched on, the end of the install log under them.
func (s *screens) drawProgress(permille int, label string, took time.Duration, tip string, logLines []string, showLog bool) {
	width, pad := logoWidth(), s.pad()
	// What fits: on a short screen the log window shrinks, and gives way
	// to nothing before the mark does only if even three lines will not fit.
	const below = 10 // the heading, bar, status, tip and hint with their gaps
	rows, withLogo, logRows := 0, true, 0
	if s.height != nil {
		rows = s.height()
	}
	block := len(logoLines()) + below
	if showLog {
		logRows = logWindow
		if rows > 0 && block+logRows+boxLines > rows-1 {
			logRows = rows - 1 - block - boxLines
		}
		if logRows < 3 {
			// Not with the mark on screen: the log takes its place.
			withLogo, block = false, below
			logRows = logWindow
			if rows > 0 && block+logRows+boxLines > rows-1 {
				logRows = rows - 1 - block - boxLines
			}
			if logRows < 0 {
				logRows = 0
			}
		}
		block += logRows + boxLines
	}
	top := s.top(block)
	if rows > 0 && top+block > rows-1 {
		top = 0 // a full screen: no margin, and never a line too many
	}
	fmt.Fprint(s.out, "\x1b[H"+strings.Repeat("\x1b[K\n", top))
	if withLogo {
		s.drawLogo()
	}
	const heading = "Installing Subarchy"
	timer := elapsed(took)
	gap := width - len(heading) - len(timer)
	if gap < 1 {
		gap = 1
	}
	fmt.Fprintf(s.out, "\x1b[K\n%*s%s%s%*s%s%s\x1b[0m\x1b[K\n\x1b[K\n", pad, "", sgr(colPaper), heading, gap, "", sgr(colMuted), timer)
	fmt.Fprintf(s.out, "%*s%s%s%s %3d%%\x1b[0m\x1b[K\n\x1b[K\n", pad, "", sgr(colAcid), bar(permille, width-5), sgr(colPaper), permille/10)
	fmt.Fprintf(s.out, "%*s%s%s\x1b[0m\x1b[K\n\x1b[K\n", pad, "", sgr(colPaper), centre(label, width))
	fmt.Fprintf(s.out, "%*s%s%s\x1b[0m\x1b[K\n\x1b[K\n", pad, "", sgr(colViolet), centre("Tip: "+tip, width))
	if s.poll != nil {
		hint := "Press L to show the log"
		if showLog {
			hint = "Press L to hide the log"
		}
		fmt.Fprintf(s.out, "%*s%s%s\x1b[0m\x1b[K\n", pad, "", sgr(colMuted), centre(hint, width))
	}
	if showLog {
		// The log is wider than the column: it gets most of the screen.
		wide := s.width() - 8
		if wide > 140 {
			wide = 140
		}
		if wide < width {
			wide = width
		}
		left := (s.width() - wide) / 2
		if left < 0 {
			left = 0
		}
		// A box with the log's name set into its top edge.
		inner := wide - 4
		const name = " install log "
		edge := sgr(colViolet)
		fmt.Fprintf(s.out, "\x1b[K\n%*s%s┌─%s%s%s%s┐\x1b[0m\x1b[K\n", left, "", edge, sgr(colMuted), name, edge,
			strings.Repeat("─", wide-3-len(name)))
		if len(logLines) > logRows {
			logLines = logLines[len(logLines)-logRows:]
		}
		for i := 0; i < logRows; i++ {
			l := ""
			if i < len(logLines) {
				l = clip(plainLine(logLines[i]), inner)
			}
			fmt.Fprintf(s.out, "%*s%s│ %s%-*s %s│\x1b[0m\x1b[K\n", left, "", edge, sgr(colMuted), inner, l, edge)
		}
		fmt.Fprintf(s.out, "%*s%s└%s┘\x1b[0m\x1b[K\n", left, "", edge, strings.Repeat("─", wide-2))
	}
	fmt.Fprint(s.out, "\x1b[J")
}

// tail returns the last n lines of the log, without blank ones.
func tail(log string, n int) []string {
	var lines []string
	for _, l := range strings.Split(log, "\n") {
		// pacman redraws progress with carriage returns; keep the last state.
		if i := strings.LastIndex(strings.TrimRight(l, "\r"), "\r"); i >= 0 {
			l = l[i+1:]
		}
		if strings.TrimSpace(l) != "" {
			lines = append(lines, l)
		}
	}
	if len(lines) > n {
		lines = lines[len(lines)-n:]
	}
	return lines
}

// installMessage is a line where the install says why it stopped:
// subarchy-install's own fatal message (its die), or an error from
// pacman, pacstrap or mkinitcpio. subarchy-install's other lines are
// notes it carries on after (pult apply failed, a mirror fallback, the
// cleanup), so they never count as the reason.
var installMessage = regexp.MustCompile(`(?m)^(subarchy-install: error: |error: |==> ERROR: )(.+)$`)

// failTail is how many lines at the end of the log failReason looks at
// for an error: pacman reports mirrors that failed mid-download as
// errors, and an earlier one of those is not why the install stopped.
const failTail = 40

// failReason reads the log of an install that failed: the step it was
// on and why it stopped, each "" when the log does not say.
// subarchy-install's own fatal message comes first, then the last error
// from the tools it ran.
func failReason(log string) (step, why string) {
	if _, _, label := progressOf(log); label != "Starting" {
		step = label
	}
	lines := strings.Split(strings.TrimRight(log, "\n"), "\n")
	if len(lines) > failTail {
		lines = lines[len(lines)-failTail:]
	}
	own, tool := "", ""
	for _, l := range lines {
		m := installMessage.FindStringSubmatch(plainLine(l))
		switch {
		case m == nil:
		case m[1] == "subarchy-install: error: ":
			own = m[2]
		default:
			tool = m[2]
		}
	}
	if own != "" {
		return step, own
	}
	return step, tool
}

// wrap breaks text into lines at most width columns wide, at spaces.
func wrap(text string, width int) []string {
	var lines []string
	line := ""
	for _, word := range strings.Fields(text) {
		if line != "" && len([]rune(line))+1+len([]rune(word)) > width {
			lines = append(lines, line)
			line = ""
		}
		if line != "" {
			line += " "
		}
		line += word
	}
	if line != "" {
		lines = append(lines, line)
	}
	return lines
}

// progress shows the install view until the returned stop is called. It
// reads the log from where it stood when the install started, since the
// log is appended to across runs. L switches the log window on and off.
// stop returns what this run added to the log.
func (s *screens) progress(logPath string) (stop func() string) {
	offset := int64(0)
	if st, err := os.Stat(logPath); err == nil {
		offset = st.Size()
	}
	done, finished := make(chan struct{}), make(chan struct{})
	started := time.Now()
	if s.fit != nil {
		s.fit()
	}
	fmt.Fprint(s.out, "\x1b[2J\x1b[?25l")
	next, restore := func() byte { return 0 }, func() {}
	if s.poll != nil {
		next, restore = s.poll()
	}
	runLog := ""
	go func() {
		defer close(finished)
		best, showLog := 0, false
		seen, since := -1, time.Now() // where the log last put the bar, and when
		tick := time.NewTicker(200 * time.Millisecond)
		defer tick.Stop()
		// One more frame is drawn after stop is called, so the view always
		// ends on what the log last said, however the frames fell.
		for last := false; ; {
			log := ""
			if data, err := os.ReadFile(logPath); err == nil {
				if int64(len(data)) < offset {
					offset = 0 // the log was started afresh
				}
				log = string(data[offset:])
			}
			runLog = log
			if k := next(); k == 'l' || k == 'L' {
				showLog = !showLog
			}
			at, until, label := progressOf(log)
			if at != seen {
				seen, since = at, time.Now()
			}
			at = creep(at, until, time.Since(since))
			if at < best {
				at = best // the bar never goes back
			}
			best = at
			took := time.Since(started)
			s.drawProgress(at, label, took, tips[int(took.Seconds()/8)%len(tips)], tail(log, logWindow), showLog)
			if last {
				return
			}
			select {
			case <-done:
				last = true
			case <-tick.C:
			}
		}
	}()
	return func() string {
		close(done)
		<-finished
		restore()
		fmt.Fprint(s.out, "\x1b[?25h")
		return runLog
	}
}

// finishedScreen is the last screen of a good install.
func (s *screens) finishedScreen(e env, took time.Duration) {
	s.page("Installed Subarchy in "+elapsed(took)+".", "You can remove the install medium once the computer restarts.")
	if e.action == nil {
		return
	}
	yes, err := s.confirm("Reboot now?", "Reboot now", "Stay in the live system", true)
	// The console's own colours back, whichever way: the shutdown
	// messages or the live shell come next.
	restoreConsole(s.out)
	if err == nil && yes {
		if err := e.action("reboot"); err != nil {
			s.notice(capital(err.Error()))
		}
	}
}

// failedScreen is the last screen of a failed install: why it stopped
// and at which step, the end of this run's log (runLog), and a menu. It
// returns when the user picks the shell.
func (s *screens) failedScreen(e env, cause error, runLog string) {
	const view, shell, reboot, off = "View the full log", "Open a shell", "Reboot", "Power off"
	actions := map[string]string{view: "log", reboot: "reboot", off: "poweroff"}
	step, why := failReason(runLog)
	if why == "" {
		why = cause.Error() // what subarchy-install said before its log began, or its exit status
	}
	width := s.width() - s.pad() - 2
	if width < 20 {
		width = 20
	}
	for {
		s.page("")
		for _, l := range wrap("Subarchy installation stopped: "+why, width) {
			s.line(colRed, l)
		}
		if step != "" {
			s.line(colPaper, "It stopped at this step: "+step)
		}
		fmt.Fprintln(s.out)
		// This run's lines only: an earlier run's would look like the reason.
		if lines := tail(runLog, 10); len(lines) > 0 {
			for _, l := range lines {
				s.line(colMuted, clip(plainLine(l), width))
			}
			fmt.Fprintln(s.out)
		}
		s.line(colPaper, "Nothing is left mounted; run subarchy-setup to try again.")
		fmt.Fprintln(s.out)
		if e.action == nil {
			return
		}
		what, err := s.choose("What would you like to do?", []string{view, shell, reboot, off}, shell)
		if err != nil || what == shell {
			restoreConsole(s.out)
			return
		}
		if what != view {
			restoreConsole(s.out)
		}
		if err := e.action(actions[what]); err != nil {
			s.notice(capital(err.Error()))
		}
	}
}
