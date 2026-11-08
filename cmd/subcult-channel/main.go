// Command subcult-channel serves `subcult channel ...` (ADR 0026): `channel`
// shows the update channel, `channel set stable|edge` switches the Arch
// package source between the Arch Linux Archive at the shipped snapshot
// date and the mirrors directly, and `channel refresh` moves the stable
// mirrorlist to the shipped date (run by `subcult update`).
package main

import (
	"encoding/json"
	"flag"
	"fmt"
	"io"
	"os"
	"os/exec"
	"strings"

	"git.subcult.tv/subculture-collective/subarchy/internal/channel"
	"git.subcult.tv/subculture-collective/subarchy/internal/dispatch"
)

var routes = []dispatch.Described{
	{Words: []string{"channel"}, Metadata: dispatch.Metadata{
		Summary:  "Show the update channel: stable (an Arch snapshot) or edge (the mirrors)",
		Examples: []string{"subcult channel"}}},
	{Words: []string{"channel", "set"}, Metadata: dispatch.Metadata{
		Summary: "Switch the update channel", Args: "stable | edge", RequiresSudo: true,
		Examples: []string{"subcult channel set edge", "subcult channel set stable"}}},
	{Words: []string{"channel", "refresh"}, Metadata: dispatch.Metadata{
		Summary: "Move the stable mirrorlist to the shipped snapshot date (run by subcult update)",
		Args:    "[--quiet]", Hidden: true, RequiresSudo: true}},
}

// selfPath is what sudo re-runs for the root steps (and what sudoers names).
const selfPath = "/usr/bin/subcult-channel"

type app struct {
	stdout, stderr io.Writer
	euid           int
	// sudo re-runs the command as root; tests replace it.
	sudo func(args ...string) error
}

func (a *app) run(args []string) int {
	if len(args) == 1 && args[0] == dispatch.MetadataFlag {
		if err := json.NewEncoder(a.stdout).Encode(routes); err != nil {
			return 1
		}
		return 0
	}
	fs := flag.NewFlagSet("subcult channel", flag.ContinueOnError)
	fs.SetOutput(a.stderr)
	root := fs.String("root", "/", "the filesystem root (tests, the installer's chroot)")
	quiet := fs.Bool("quiet", false, "say nothing unless something is wrong")
	// Flags may follow the words (`channel set stable --quiet`).
	flags, rest := splitFlags(args)
	if err := fs.Parse(flags); err != nil {
		return 2
	}
	if len(rest) == 0 {
		st, err := channel.Current(*root)
		if err != nil {
			fmt.Fprintf(a.stderr, "subcult channel: %v\n", err)
			return 1
		}
		fmt.Fprintln(a.stdout, st)
		return 0
	}
	switch rest[0] {
	case "set":
		if len(rest) != 2 || !channel.Valid(rest[1]) {
			fmt.Fprintln(a.stderr, "Usage: subcult channel set stable | edge")
			return 2
		}
		if code, done := a.asRoot(*root, args); done {
			return code
		}
		warning, err := channel.Set(*root, rest[1])
		if err != nil {
			fmt.Fprintf(a.stderr, "subcult channel: %v\n", err)
			return 1
		}
		if warning != "" {
			fmt.Fprintln(a.stderr, "warning:", warning)
		}
		if !*quiet {
			st, _ := channel.Current(*root)
			fmt.Fprintln(a.stdout, st)
		}
		return 0
	case "refresh":
		if code, done := a.asRoot(*root, args); done {
			return code
		}
		changed, err := channel.Refresh(*root)
		if err != nil {
			fmt.Fprintf(a.stderr, "subcult channel: %v\n", err)
			return 1
		}
		if changed && !*quiet {
			st, _ := channel.Current(*root)
			fmt.Fprintln(a.stdout, "moved to", st)
		}
		return 0
	}
	fmt.Fprintln(a.stderr, "Usage: subcult channel | channel set stable|edge")
	return 2
}

// splitFlags separates --flags (and --root's value) from the words, so the
// flags may come in any position.
func splitFlags(args []string) (flags, words []string) {
	for i := 0; i < len(args); i++ {
		switch {
		case args[i] == "--root" && i+1 < len(args):
			flags = append(flags, args[i], args[i+1])
			i++
		case strings.HasPrefix(args[i], "-"):
			flags = append(flags, args[i])
		default:
			words = append(words, args[i])
		}
	}
	return flags, words
}

// asRoot re-runs the command through sudo when it writes to the real root
// without being root. done is true when the re-run happened (or failed).
func (a *app) asRoot(root string, args []string) (code int, done bool) {
	if root != "/" || a.euid == 0 {
		return 0, false
	}
	if err := a.sudo(args...); err != nil {
		if ee, ok := err.(*exec.ExitError); ok {
			return ee.ExitCode(), true
		}
		fmt.Fprintf(a.stderr, "subcult channel: %v\n", err)
		return 1, true
	}
	return 0, true
}

func main() {
	a := &app{stdout: os.Stdout, stderr: os.Stderr, euid: os.Geteuid()}
	a.sudo = func(args ...string) error {
		c := exec.Command("sudo", append([]string{selfPath}, args...)...)
		c.Stdin, c.Stdout, c.Stderr = os.Stdin, os.Stdout, os.Stderr
		return c.Run()
	}
	os.Exit(a.run(os.Args[1:]))
}
