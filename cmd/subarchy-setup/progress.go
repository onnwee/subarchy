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

// draw paints one frame of the install view.
func (s *screens) drawProgress(permille int, label string, took time.Duration, tip string) {
	fmt.Fprint(s.out, "\x1b[H\n")
	for _, l := range strings.Split(strings.TrimRight(logo, "\n"), "\n") {
		s.line(colAcid, l)
	}
	width := logoWidth()
	fmt.Fprintf(s.out, "\n%*s\x1b[3%smInstalling Subarchy\x1b[0m\x1b[K\n\n", s.pad(), "", colPaper)
	fmt.Fprintf(s.out, "%*s\x1b[3%sm%s\x1b[3%sm %3d%%\x1b[0m\x1b[K\n\n", s.pad(), "", colAcid, bar(permille, width-6), colPaper, permille/10)
	fmt.Fprintf(s.out, "%*s%s%s  ·  %s\x1b[0m\x1b[K\n\n", s.pad(), "", sgr(colMuted), label, elapsed(took))
	fmt.Fprintf(s.out, "%*s\x1b[3%smTip: %s\x1b[0m\x1b[K\n", s.pad(), "", colViolet, tip)
}

// progress shows the install view until the returned stop is called. It
// reads the log from where it stood when the install started, since the
// log is appended to across runs.
func (s *screens) progress(logPath string) (stop func()) {
	offset := int64(0)
	if st, err := os.Stat(logPath); err == nil {
		offset = st.Size()
	}
	done, finished := make(chan struct{}), make(chan struct{})
	started := time.Now()
	fmt.Fprint(s.out, "\x1b[2J\x1b[?25l")
	go func() {
		defer close(finished)
		best := 0
		tick := time.NewTicker(500 * time.Millisecond)
		defer tick.Stop()
		for {
			log := ""
			if data, err := os.ReadFile(logPath); err == nil {
				if int64(len(data)) < offset {
					offset = 0 // the log was started afresh
				}
				log = string(data[offset:])
			}
			at, label := progressOf(log)
			if at < best {
				at = best // the bar never goes back
			}
			best = at
			took := time.Since(started)
			s.drawProgress(at, label, took, tips[int(took.Seconds()/8)%len(tips)])
			select {
			case <-done:
				return
			case <-tick.C:
			}
		}
	}()
	return func() {
		close(done)
		<-finished
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
