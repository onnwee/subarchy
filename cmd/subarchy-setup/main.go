// Command subarchy-setup is the guided installer on the live ISO
// (ADR 0049). It asks for the disk, names, passwords, time zone and
// keyboard, checks each answer, writes a config for subarchy-install and
// runs it.
package main

import (
	"bufio"
	"errors"
	"flag"
	"fmt"
	"io"
	"os"
	"os/exec"
	"path/filepath"
	"strconv"
	"strings"
	"time"

	"golang.org/x/term"

	"git.subcult.tv/subculture-collective/subarchy/internal/setup"
)

type prompter struct {
	in     *bufio.Reader
	out    io.Writer
	secret func() (string, error) // reads a line without echo
}

func (p *prompter) line(question, def string) (string, error) {
	if def != "" {
		fmt.Fprintf(p.out, "%s [%s]: ", question, def)
	} else {
		fmt.Fprintf(p.out, "%s: ", question)
	}
	s, err := p.in.ReadString('\n')
	if err != nil && (s == "" || !errors.Is(err, io.EOF)) {
		return "", err
	}
	s = strings.TrimSpace(s)
	if s == "" {
		s = def
	}
	return s, nil
}

// ask repeats a question until check accepts the answer.
func (p *prompter) ask(question, def string, check func(string) error) (string, error) {
	for {
		s, err := p.line(question, def)
		if err != nil {
			return "", err
		}
		if err := check(s); err != nil {
			fmt.Fprintf(p.out, "  %v\n", err)
			continue
		}
		return s, nil
	}
}

func (p *prompter) askSecret(what string, min int) (string, error) {
	for {
		fmt.Fprintf(p.out, "%s: ", what)
		s, err := p.secret()
		fmt.Fprintln(p.out)
		if err != nil {
			return "", err
		}
		fmt.Fprintf(p.out, "%s again: ", what)
		again, err := p.secret()
		fmt.Fprintln(p.out)
		if err != nil {
			return "", err
		}
		if err := setup.ValidSecret(s, again, min); err != nil {
			fmt.Fprintf(p.out, "  %v\n", err)
			continue
		}
		return s, nil
	}
}

// yesNo asks a yes/no question; an empty answer is the default.
func (p *prompter) yesNo(question string, def bool) (bool, error) {
	hint := "y/N"
	if def {
		hint = "Y/n"
	}
	for {
		s, err := p.line(question+"? ("+hint+")", "")
		if err != nil {
			return false, err
		}
		switch strings.ToLower(s) {
		case "":
			return def, nil
		case "y", "yes":
			return true, nil
		case "n", "no":
			return false, nil
		}
		fmt.Fprintln(p.out, "  answer y or n")
	}
}

type env struct {
	lsblk        func() ([]byte, error)
	installMedia func() string
	zoneinfo     string
	keymaps      string
	// kbdModelMap is systemd's table from console keymaps to desktop
	// layouts (/usr/share/systemd/kbd-model-map).
	kbdModelMap string
	// localeGen lists the locales the installed system can use.
	localeGen string
	// loadKeymap makes the console use a keymap now (loadkeys).
	loadKeymap func(keymap string) error
	// browse shows a disk's filesystems read-only until the user leaves.
	// It first calls show with the partitions it opened and those it left
	// closed (with why); the browse goes ahead only if show returns true.
	browse func(d setup.Disk, show func(opened, closed []string) bool) error
	// logTail returns the last lines of the install log.
	logTail func(n int) []string
	// action runs one of "reboot", "poweroff", "log" (view the install
	// log) or "shell".
	action func(what string) error
	// screens is the full-screen interface, on a virtual console with
	// gum; nil means the plain prompts.
	screens *screens
	// installLog is where subarchy-install writes its output.
	installLog string
	// wifi is the live image's Wi-Fi; nil means no network page and
	// nothing carried over.
	wifi *wifi
}

// collect asks every question and returns the answers.
func collect(p *prompter, e env, repo, cmdlineExtra string) (setup.Answers, error) {
	a := setup.Answers{Repo: repo, CmdlineExtra: cmdlineExtra}
	// Without a disk there is nothing to ask.
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
	// The keyboard is the first question, and loaded at once: the installed
	// system uses this layout at the disk prompt and the login screen, so
	// the password and passphrase below must be typed with it. Typed under
	// the live image's US layout, they would not unlock the new system on
	// any keyboard where those keys differ.
	if a.Keymap, err = p.ask("Keyboard layout", "us", func(s string) error { return setup.ValidKeymap(e.keymaps, s) }); err != nil {
		return a, err
	}
	a.XKBLayout, a.XKBVariant = xkbFor(e.kbdModelMap, a.Keymap)
	if e.loadKeymap != nil {
		if err := e.loadKeymap(a.Keymap); err != nil {
			fmt.Fprintf(p.out, "Could not switch this console to %s (%v); it still types as before.\n", a.Keymap, err)
		}
	}
	if err := p.network(e.wifi); err != nil {
		return a, err
	}
	for a.Disk == "" {
		fmt.Fprintln(p.out, "\nDisks (the chosen one is erased; the others are not touched):")
		for i, d := range disks {
			fmt.Fprintf(p.out, "  %d) %s\n", i+1, d)
			if len(d.Parts) == 0 {
				fmt.Fprintln(p.out, "       empty: no partitions")
			}
			for _, part := range d.Parts {
				fmt.Fprintf(p.out, "       %s\n", part)
			}
		}
		question := "Install to disk number"
		if e.browse != nil {
			question += " (or \"look 1\" to browse that disk read-only)"
		}
		var look bool
		var n int
		_, err := p.ask(question, "", func(s string) error {
			num, isLook := strings.CutPrefix(s, "look")
			n, err = strconv.Atoi(strings.TrimSpace(num))
			if err != nil || n < 1 || n > len(disks) || (isLook && e.browse == nil) {
				return fmt.Errorf("enter a number from 1 to %d", len(disks))
			}
			look = isLook
			return nil
		})
		if err != nil {
			return a, err
		}
		if !look {
			a.Disk = disks[n-1].Path
			break
		}
		d := disks[n-1]
		show := func(opened, closed []string) bool {
			title, body := lookPage(d.Path, opened, closed)
			fmt.Fprintln(p.out, "\n"+title)
			for _, l := range body {
				fmt.Fprintln(p.out, "  "+l)
			}
			if len(opened) == 0 {
				return false
			}
			ok, err := p.yesNo("Open the file manager", true)
			return err == nil && ok
		}
		if err := e.browse(d, show); err != nil {
			fmt.Fprintf(p.out, "  %v\n", err)
		}
	}

	if a.Hostname, err = p.ask("Computer name", "subarchy", setup.ValidHostname); err != nil {
		return a, err
	}
	if a.Username, err = p.ask("Your user name", "", setup.ValidUsername); err != nil {
		return a, err
	}
	if a.Password, err = p.askSecret("Password for "+a.Username, 8); err != nil {
		return a, err
	}
	fmt.Fprintln(p.out, "The disk passphrase unlocks the disk at every boot. Losing it loses the data.")
	same, err := p.yesNo("Use your password as the disk passphrase too", true)
	if err != nil {
		return a, err
	}
	if same {
		a.Passphrase = a.Password
	} else if a.Passphrase, err = p.askSecret("Disk passphrase", 8); err != nil {
		return a, err
	}
	if a.Timezone, err = p.ask("Time zone", "UTC", func(s string) error { return setup.ValidTimezone(e.zoneinfo, s) }); err != nil {
		return a, err
	}
	if note := carryWiFi(&a, e.wifi); note != "" {
		fmt.Fprintln(p.out, note)
	}
	return a, nil
}

// xkbFor maps a console keymap to the desktop layout and variant, from
// systemd's table: "sv-latin1" is "se", "la-latin1" is "latam", "dvorak"
// is "us" with the variant "dvorak". Cutting the name at its dash gives
// "la", which is Lao. Without the table or an entry, that cut is all
// there is.
func xkbFor(modelMap, keymap string) (layout, variant string) {
	if data, err := os.ReadFile(modelMap); err == nil {
		for _, line := range strings.Split(string(data), "\n") {
			f := strings.Fields(line)
			if len(f) >= 4 && f[0] == keymap {
				if f[3] != "-" {
					variant = f[3]
				}
				return f[1], variant
			}
		}
	}
	return xkbLayout(keymap), ""
}

// xkbLayout guesses the desktop layout from a console keymap's name:
// "de-latin1" is "de", "uk" is "gb".
func xkbLayout(keymap string) string {
	layout, _, _ := strings.Cut(keymap, "-")
	if layout == "uk" {
		return "gb"
	}
	return layout
}

// confirm shows the summary and asks whether to erase the disk. No is
// the default, so Enter alone changes nothing.
func confirm(p *prompter, a setup.Answers) (bool, error) {
	fmt.Fprintf(p.out, "\nInstalling Subarchy:\n  disk      %s (ALL DATA ON IT WILL BE ERASED)\n  computer  %s\n  user      %s\n  time zone %s\n  keyboard  %s\n",
		a.Disk, a.Hostname, a.Username, a.Timezone, a.Keymap)
	if a.WiFiSSID != "" {
		fmt.Fprintf(p.out, "  Wi-Fi     %s (joined at first boot)\n", a.WiFiSSID)
	}
	fmt.Fprintln(p.out)
	return p.yesNo(fmt.Sprintf("Erase %s and install", a.Disk), false)
}

// elapsed renders a duration as "3m 12s".
func elapsed(d time.Duration) string {
	s := int(d.Round(time.Second).Seconds())
	if s < 60 {
		return fmt.Sprintf("%ds", s)
	}
	return fmt.Sprintf("%dm %ds", s/60, s%60)
}

// finished is the last screen of a good install: how long it took, and
// an offer to reboot.
func finished(p *prompter, e env, took time.Duration) {
	fmt.Fprintf(p.out, "\nInstalled Subarchy in %s.\nYou can remove the install medium once the computer restarts.\n\n", elapsed(took))
	if e.action == nil {
		return
	}
	if yes, err := p.yesNo("Reboot now", true); err == nil && yes {
		if err := e.action("reboot"); err != nil {
			fmt.Fprintf(p.out, "  %v\n", err)
		}
	}
}

// failed is the last screen of a failed install: what the log ended
// with, and what to do next. It returns when the user picks the shell.
func failed(p *prompter, e env, cause error) {
	fmt.Fprintf(p.out, "\nSubarchy installation stopped: %v\n", cause)
	if e.logTail != nil {
		if lines := e.logTail(12); len(lines) > 0 {
			fmt.Fprintln(p.out, "Last log lines:")
			for _, l := range lines {
				fmt.Fprintf(p.out, "  %s\n", l)
			}
		}
	}
	fmt.Fprintln(p.out, "Nothing is left mounted; run subarchy-setup to try again.")
	if e.action == nil {
		return
	}
	choices := []string{"log", "shell", "reboot", "poweroff"}
	for {
		fmt.Fprintln(p.out, "\n  1) View the full log\n  2) Open a shell\n  3) Reboot\n  4) Power off")
		s, err := p.line("What would you like to do", "2")
		if err != nil {
			return
		}
		n, err := strconv.Atoi(s)
		if err != nil || n < 1 || n > len(choices) {
			fmt.Fprintln(p.out, "  enter a number from 1 to 4")
			continue
		}
		if choices[n-1] == "shell" {
			return
		}
		if err := e.action(choices[n-1]); err != nil {
			fmt.Fprintf(p.out, "  %v\n", err)
		}
	}
}

func run(args []string, stdin io.Reader, stdout io.Writer, e env, secret func() (string, error), exec func(conf string, quiet bool) error) int {
	fs := flag.NewFlagSet("subarchy-setup", flag.ContinueOnError)
	fs.SetOutput(stdout)
	repo := fs.String("repo", "file:///opt/subarchy/repo", "pacman Server URL of the [subarchy] repository")
	cmdlineExtra := fs.String("cmdline-extra", "", "appended to the kernel command line")
	dir := fs.String("dir", "/run/subarchy-setup", "where the config and secret files are written")
	dryRun := fs.Bool("dry-run", false, "write the config and stop")
	cache := fs.String("package-cache", "", "pacman cache directory to reuse (tests)")
	batch := fs.Bool("batch", false, "plain prompts; do not offer to browse disks, reboot or the failure menu (tests)")
	plain := fs.Bool("plain", false, "plain prompts instead of full screens")
	if err := fs.Parse(args); err != nil {
		return 2
	}
	p := &prompter{in: bufio.NewReader(stdin), out: stdout, secret: secret}
	if secret == nil {
		p.secret = func() (string, error) {
			s, err := p.in.ReadString('\n')
			if err != nil && (s == "" || !errors.Is(err, io.EOF)) {
				return "", err
			}
			return strings.TrimRight(s, "\r\n"), nil
		}
	}
	if *plain {
		e.screens = nil
	}
	if *batch {
		e.browse, e.action, e.screens, e.wifi = nil, nil, nil, nil
	}
	var a setup.Answers
	var err error
	if e.screens != nil {
		a, err = collectScreens(e.screens, e, *repo, *cmdlineExtra)
		fmt.Fprint(stdout, "\x1b[2J\x1b[H")
		if errors.Is(err, errBack) {
			fmt.Fprintln(stdout, "Stopped; nothing was changed. Run subarchy-setup to start again.")
			return 1
		}
		if err != nil {
			fmt.Fprintf(stdout, "subarchy-setup: %v\n", err)
			return 1
		}
	} else {
		fmt.Fprintln(stdout, "SUBCULT // Subarchy setup")
		if a, err = collect(p, e, *repo, *cmdlineExtra); err != nil {
			fmt.Fprintf(stdout, "subarchy-setup: %v\n", err)
			return 1
		}
		ok, err := confirm(p, a)
		if err != nil || !ok {
			fmt.Fprintln(stdout, "Stopped; nothing was changed.")
			return 1
		}
	}
	a.PackageCache = *cache
	conf, err := a.WriteConfig(*dir)
	if err != nil {
		fmt.Fprintf(stdout, "subarchy-setup: %v\n", err)
		return 1
	}
	if *dryRun {
		fmt.Fprintf(stdout, "Config written to %s.\n", conf)
		return 0
	}
	started := time.Now()
	if e.screens != nil {
		// Full screen: the install view in place of the raw output.
		stop := e.screens.progress(e.installLog)
		err := exec(conf, true)
		stop()
		if err != nil {
			e.screens.failedScreen(e, err)
			return 1
		}
		e.screens.finishedScreen(e, time.Since(started))
		return 0
	}
	if err := exec(conf, false); err != nil {
		failed(p, e, err)
		return 1
	}
	finished(p, e, time.Since(started))
	return 0
}

func main() {
	if os.Geteuid() != 0 {
		fmt.Fprintln(os.Stderr, "subarchy-setup: run as root on the live ISO")
		os.Exit(1)
	}
	stdinFd := int(os.Stdin.Fd())
	var secret func() (string, error)
	if term.IsTerminal(stdinFd) {
		secret = func() (string, error) {
			b, err := term.ReadPassword(stdinFd)
			return string(b), err
		}
	}
	e := env{
		lsblk: func() ([]byte, error) {
			return exec.Command("lsblk", "-J", "-b", "-o", "NAME,PATH,SIZE,TYPE,MODEL,TRAN,RO,FSTYPE,LABEL").Output()
		},
		installMedia: installMedium,
		zoneinfo:     "/usr/share/zoneinfo",
		keymaps:      "/usr/share/kbd/keymaps",
		kbdModelMap:  "/usr/share/systemd/kbd-model-map",
		localeGen:    "/etc/locale.gen",
		loadKeymap: func(keymap string) error {
			return exec.Command("loadkeys", keymap).Run()
		},
		browse:     browse,
		installLog: installLog,
		logTail:    logTail,
		action:     action,
		wifi:       realWiFi(),
	}
	if onConsole() {
		prepareConsole(os.Stdout)
		e.screens = realScreens()
	}
	// The installer runs as a child so its result can be shown: the time
	// it took and a reboot offer, or the failure menu.
	installer := func(conf string, quiet bool) error {
		cmd := exec.Command("subarchy-install", "--config", conf, "--yes")
		if !quiet {
			cmd.Stdin, cmd.Stdout, cmd.Stderr = os.Stdin, os.Stdout, os.Stderr
		}
		return cmd.Run()
	}
	os.Exit(run(os.Args[1:], os.Stdin, os.Stdout, e, secret, installer))
}

// installMedium returns the disk the live system booted from, if any.
func installMedium() string {
	src, err := exec.Command("findmnt", "-no", "SOURCE", "/run/archiso/bootmnt").Output()
	if err != nil {
		return ""
	}
	dev := strings.TrimSpace(string(src))
	parent, err := exec.Command("lsblk", "-no", "PKNAME", dev).Output()
	if err == nil && strings.TrimSpace(string(parent)) != "" {
		return "/dev/" + strings.TrimSpace(string(parent))
	}
	return dev
}

const installLog = "/var/log/subarchy-install.log"

// interactive runs a program on this terminal.
func interactive(name string, args ...string) error {
	cmd := exec.Command(name, args...)
	cmd.Stdin, cmd.Stdout, cmd.Stderr = os.Stdin, os.Stdout, os.Stderr
	return cmd.Run()
}

func action(what string) error {
	switch what {
	case "reboot", "poweroff":
		// Only emergencies on the console from here: the watchdog and
		// console warnings of a normal shutdown stay in the journal, and
		// SIGRTMIN+21 turns off systemd's own "Stopped ..." lines.
		level, _ := os.ReadFile("/proc/sys/kernel/printk")
		exec.Command("dmesg", "-n", "1").Run()
		exec.Command("kill", "-s", "RTMIN+21", "1").Run()
		err := exec.Command("systemctl", what).Run()
		if f := strings.Fields(string(level)); err != nil && len(f) > 0 {
			exec.Command("dmesg", "-n", f[0]).Run() // still in the live system
		}
		return err
	case "log":
		return interactive("less", "+G", installLog)
	}
	return fmt.Errorf("unknown action %q", what)
}

func logTail(n int) []string {
	data, err := os.ReadFile(installLog)
	if err != nil {
		return nil
	}
	lines := strings.Split(strings.TrimRight(string(data), "\n"), "\n")
	if len(lines) > n {
		lines = lines[len(lines)-n:]
	}
	return lines
}

// browse mounts each plain filesystem on the disk read-only under
// /run/subarchy-look and calls show with what it opened and what it left
// closed. When show returns true it opens a file manager there, and it
// unmounts again when that exits.
func browse(d setup.Disk, show func(opened, closed []string) bool) error {
	const root = "/run/subarchy-look"
	var mounted, opened, closed []string
	defer func() {
		for _, dir := range mounted {
			exec.Command("umount", dir).Run()
			os.Remove(dir)
		}
		os.Remove(root)
	}()
	for _, part := range d.Parts {
		if why := part.Closed(); why != "" {
			closed = append(closed, part.String()+", "+why)
			continue
		}
		dir := root + "/" + strings.TrimPrefix(part.Path, "/dev/")
		if err := os.MkdirAll(dir, 0o700); err != nil {
			return err
		}
		if exec.Command("mount", "-o", lookMountOptions(part.FSType), part.Path, dir).Run() != nil {
			os.Remove(dir)
			closed = append(closed, part.String()+", could not be mounted")
			continue
		}
		mounted = append(mounted, dir)
		opened = append(opened, part.String())
	}
	if !show(opened, closed) || len(opened) == 0 {
		return nil
	}
	profile, err := os.MkdirTemp("", "subarchy-look-mc-")
	if err != nil {
		return err
	}
	defer os.RemoveAll(profile)
	if err := writeLookProfile(profile); err != nil {
		return err
	}
	cmd := lookCommand(root, profile)
	cmd.Stdin, cmd.Stdout, cmd.Stderr = os.Stdin, os.Stdout, os.Stderr
	return cmd.Run()
}

// lookMountOptions are the mount options for a filesystem the browse
// opens. noload, norecovery and nologreplay keep a journal from being
// replayed, so nothing on the disk changes. noexec stops Return in mc from
// running a file as root: vfat and ntfs3 mark every file executable.
func lookMountOptions(fstype string) string {
	opts := "ro,noexec,nosuid,nodev"
	switch fstype {
	case "ext3", "ext4":
		opts += ",noload"
	case "xfs":
		opts += ",norecovery"
	case "btrfs":
		opts += ",rescue=nologreplay"
	}
	return opts
}

// lookKeys is how to leave the file manager. F10 is a media key on many
// laptops, so the two other ways come first. Each line stays within the
// logo's width, so it does not wrap on an 80-column console.
var lookKeys = []string{"To come back here, press q, or Esc and then 0,", "or F10 (Fn+F10 on many laptops)."}

// lookPage is the text shown before the browse: what is opened, what is
// left closed and why, and how to come back.
func lookPage(path string, opened, closed []string) (title string, body []string) {
	if len(opened) == 0 {
		title = "Nothing on " + path + " can be opened read-only."
		if len(closed) == 0 {
			return title, []string{"It has no partitions."}
		}
	} else {
		title = "Browsing " + path + " read-only"
		body = append(body, "Opened read-only, in a file manager:")
		for _, o := range opened {
			body = append(body, "  "+o)
		}
	}
	if len(closed) > 0 {
		body = append(body, "Not opened:")
		for _, c := range closed {
			body = append(body, "  "+c)
		}
	}
	if len(opened) > 0 {
		body = append(body, "", "Arrow keys and Return move between folders.", "F3 shows a file, and q closes it.")
		body = append(body, lookKeys...)
	}
	return title, body
}

// The file manager's settings for the browse, in a temporary profile so
// the live system's own mc settings are not used or changed. The command
// line is hidden, so typed letters search the panel instead of becoming
// a root command. Return on an executable file asks first (the mounts are
// noexec as well). q quits: mc hands a key the panel does not act on to
// the file manager's keys. Ctrl-O, which shows an empty screen without a
// subshell, does nothing. F2 does nothing either: mc would read a
// .mc.menu from the browsed directory, and a root-owned file on a
// read-only disk passes its trust check. The nicedark skin keeps text on the ink
// background: the installer palette makes cyan the same acid green as
// green, and mc's default skin draws white and yellow menu text on cyan.
const (
	lookIni = `[Midnight-Commander]
skin=nicedark
confirm_exit=false
confirm_execute=true
[Layout]
command_prompt=false
message_visible=false
`
	lookKeymap = `[filemanager]
Quit = f10; q
Shell =
UserMenu =
[panel]
Quit = q
`
)

// writeLookProfile writes the browse's mc settings under dir, the mc
// profile root. The user menu is empty, so Command > User menu has
// nothing of the live system's to run.
func writeLookProfile(dir string) error {
	conf := filepath.Join(dir, ".config", "mc")
	if err := os.MkdirAll(conf, 0o700); err != nil {
		return err
	}
	for name, text := range map[string]string{"ini": lookIni, "mc.keymap": lookKeymap, "menu": ""} {
		if err := os.WriteFile(filepath.Join(conf, name), []byte(text), 0o600); err != nil {
			return err
		}
	}
	return nil
}

// lookCommand is Midnight Commander with both panels on root, no
// subshell, and the settings under profile.
func lookCommand(root, profile string) *exec.Cmd {
	cmd := exec.Command("mc", "--nosubshell", root, root)
	cmd.Env = append(os.Environ(), "MC_PROFILE_ROOT="+profile)
	return cmd
}
