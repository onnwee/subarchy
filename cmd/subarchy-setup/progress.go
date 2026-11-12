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
)

// configureLines is about how many lines the configure phase logs
// (hooks, the two kernel images); it only paces the bar.
const configureLines = 360

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
	{">> configuring the system", 700, "Configuring the system"},
	{">> configuring snapper", 960, "Setting up snapshots"},
	{">> checking the boot entries", 975, "Checking the boot entries"},
	{">> finishing", 990, "Finishing"},
}

// progressOf reads the install log and returns how far the install is,
// in per mille below 1000, and the current phase's label.
func progressOf(log string) (int, string) {
	at, label := 0, "Starting"
	for i, p := range phases {
		idx := strings.Index(log, p.marker)
		if idx < 0 {
			continue
		}
		at, label = p.start, p.label
		next := 1000
		if i+1 < len(phases) {
			next = phases[i+1].start
		}
		rest := log[idx:]
		switch p.marker {
		case ">> installing packages":
			if m := packagesTotal.FindStringSubmatch(rest); m != nil {
				total, _ := strconv.Atoi(m[1])
				done := len(installingPkg.FindAllStringIndex(rest, -1))
				if total > 0 {
					if done > total {
						done = total
					}
					at = p.start + (next-p.start)*done/total
					label = fmt.Sprintf("Installing packages (%d of %d)", done, total)
				}
			}
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
	return at, label
}

// tips rotate under the bar while the install runs.
var tips = []string{
	"Super + Return opens a terminal.",
	"Super + Space opens the launcher.",
	"Super + W closes the window in front.",
	"Super + 1 to 9 switches workspaces; add Shift to move a window there.",
	"Super + F makes a window full screen.",
	"Super + S shows the scratchpad workspace.",
	"Super + Ctrl + V opens the clipboard history.",
	"`subcult update` updates the system and takes a snapshot first.",
	"A bad update can be undone: pick a snapshot in the boot menu.",
	"`pult apply <theme>` recolours the shell, the lock and the windows.",
	"The disk passphrase is asked at every boot; `subcult disk tpm` can let the TPM unlock it.",
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
				l = strings.Map(func(r rune) rune {
					if r < 0x20 || r == 0x7f {
						return -1 // control bytes would move the cursor
					}
					return r
				}, logLines[i])
				if r := []rune(l); len(r) > inner {
					l = string(r[:inner])
				}
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

// progress shows the install view until the returned stop is called. It
// reads the log from where it stood when the install started, since the
// log is appended to across runs. L switches the log window on and off.
func (s *screens) progress(logPath string) (stop func()) {
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
	go func() {
		defer close(finished)
		best, showLog := 0, false
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
			if k := next(); k == 'l' || k == 'L' {
				showLog = !showLog
			}
			at, label := progressOf(log)
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
	return func() {
		close(done)
		<-finished
		restore()
		fmt.Fprint(s.out, "\x1b[?25h")
	}
}

// finishedScreen is the last screen of a good install.
func (s *screens) finishedScreen(e env, took time.Duration) {
	s.page("Installed Subarchy in "+elapsed(took)+".", "You can remove the install medium once the computer restarts.")
	if e.action == nil {
		return
	}
	if yes, err := s.confirm("Reboot now?", "Reboot now", "Stay in the live system", true); err == nil && yes {
		if err := e.action("reboot"); err != nil {
			s.notice(capital(err.Error()))
		}
	}
	fmt.Fprint(s.out, "\x1b[2J\x1b[H")
}

// failedScreen is the last screen of a failed install. It returns when
// the user picks the shell.
func (s *screens) failedScreen(e env, cause error) {
	const view, shell, reboot, off = "View the full log", "Open a shell", "Reboot", "Power off"
	actions := map[string]string{view: "log", reboot: "reboot", off: "poweroff"}
	for {
		s.page("")
		s.line(colRed, fmt.Sprintf("Subarchy installation stopped: %v", cause))
		fmt.Fprintln(s.out)
		if e.logTail != nil {
			width := s.width() - s.pad() - 2
			for _, l := range e.logTail(10) {
				if r := []rune(l); len(r) > width && width > 0 {
					l = string(r[:width])
				}
				s.line(colMuted, l)
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
			fmt.Fprint(s.out, "\x1b[2J\x1b[H")
			return
		}
		if err := e.action(actions[what]); err != nil {
			s.notice(capital(err.Error()))
		}
	}
}
