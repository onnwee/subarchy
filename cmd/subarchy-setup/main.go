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
	"strconv"
	"strings"
	"syscall"

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

type env struct {
	lsblk        func() ([]byte, error)
	installMedia func() string
	zoneinfo     string
	keymaps      string
}

// collect asks every question and returns the answers.
func collect(p *prompter, e env, repo, cmdlineExtra string) (setup.Answers, error) {
	a := setup.Answers{Repo: repo, CmdlineExtra: cmdlineExtra}
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
	fmt.Fprintln(p.out, "\nDisks (the chosen one is erased; the others are not touched):")
	for i, d := range disks {
		fmt.Fprintf(p.out, "  %d) %s\n", i+1, d)
	}
	pick, err := p.ask("Install to disk number", "", func(s string) error {
		n, err := strconv.Atoi(s)
		if err != nil || n < 1 || n > len(disks) {
			return fmt.Errorf("enter a number from 1 to %d", len(disks))
		}
		return nil
	})
	if err != nil {
		return a, err
	}
	n, _ := strconv.Atoi(pick)
	a.Disk = disks[n-1].Path

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
	if a.Passphrase, err = p.askSecret("Disk passphrase", 8); err != nil {
		return a, err
	}
	if a.Timezone, err = p.ask("Time zone", "UTC", func(s string) error { return setup.ValidTimezone(e.zoneinfo, s) }); err != nil {
		return a, err
	}
	if a.Keymap, err = p.ask("Keyboard layout", "us", func(s string) error { return setup.ValidKeymap(e.keymaps, s) }); err != nil {
		return a, err
	}
	a.XKBLayout = xkbLayout(a.Keymap)
	return a, nil
}

// xkbLayout maps a console keymap to the desktop layout: "de-latin1" is
// "de", "uk" is "gb".
func xkbLayout(keymap string) string {
	layout, _, _ := strings.Cut(keymap, "-")
	if layout == "uk" {
		return "gb"
	}
	return layout
}

// confirm shows the summary and asks the user to type the disk's name.
func confirm(p *prompter, a setup.Answers) (bool, error) {
	name := strings.TrimPrefix(a.Disk, "/dev/")
	fmt.Fprintf(p.out, "\nInstalling Subarchy:\n  disk      %s (ALL DATA ON IT WILL BE ERASED)\n  computer  %s\n  user      %s\n  time zone %s\n  keyboard  %s\n\n",
		a.Disk, a.Hostname, a.Username, a.Timezone, a.Keymap)
	s, err := p.line(fmt.Sprintf("Type %s to erase it and install, anything else to stop", name), "")
	if err != nil {
		return false, err
	}
	return s == name, nil
}

func run(args []string, stdin io.Reader, stdout io.Writer, e env, secret func() (string, error), exec func(conf string) error) int {
	fs := flag.NewFlagSet("subarchy-setup", flag.ContinueOnError)
	fs.SetOutput(stdout)
	repo := fs.String("repo", "file:///opt/subarchy/repo", "pacman Server URL of the [subarchy] repository")
	cmdlineExtra := fs.String("cmdline-extra", "", "appended to the kernel command line")
	dir := fs.String("dir", "/run/subarchy-setup", "where the config and secret files are written")
	dryRun := fs.Bool("dry-run", false, "write the config and stop")
	cache := fs.String("package-cache", "", "pacman cache directory to reuse (tests)")
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
	fmt.Fprintln(stdout, "SUBCULT // Subarchy setup")
	a, err := collect(p, e, *repo, *cmdlineExtra)
	if err != nil {
		fmt.Fprintf(stdout, "subarchy-setup: %v\n", err)
		return 1
	}
	ok, err := confirm(p, a)
	if err != nil || !ok {
		fmt.Fprintln(stdout, "Stopped; nothing was changed.")
		return 1
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
	if err := exec(conf); err != nil {
		fmt.Fprintf(stdout, "subarchy-setup: %v\n", err)
		return 1
	}
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
			return exec.Command("lsblk", "-J", "-d", "-b", "-o", "NAME,PATH,SIZE,TYPE,MODEL,TRAN,RO").Output()
		},
		installMedia: installMedium,
		zoneinfo:     "/usr/share/zoneinfo",
		keymaps:      "/usr/share/kbd/keymaps",
	}
	installer := func(conf string) error {
		path, err := exec.LookPath("subarchy-install")
		if err != nil {
			return err
		}
		return syscall.Exec(path, []string{"subarchy-install", "--config", conf, "--yes"}, os.Environ())
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
