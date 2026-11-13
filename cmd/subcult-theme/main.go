// Command subcult-theme serves `subcult theme apply-system` (ADR 0037):
// the user's palette, which Pult writes, applied to the root-owned screens
// (SDDM, Plymouth, Limine) and Chromium's colour policy. The user half
// reads and checks the palette and hands the colours to a privileged run
// of this command through polkit (pkexec); the privileged half, the
// hidden `theme system-apply`, takes only colours as arguments, writes the
// files, and rebuilds the initramfs when the splash changed.
package main

import (
	"encoding/json"
	"flag"
	"fmt"
	"io"
	"os"
	"os/exec"
	"path/filepath"
	"strings"

	"git.subcult.tv/subculture-collective/subarchy/internal/dispatch"
	"git.subcult.tv/subculture-collective/subarchy/internal/systheme"
)

var routes = []dispatch.Described{
	{Words: []string{"theme", "apply-system"}, Metadata: dispatch.Metadata{
		Summary:      "Apply the user's palette to SDDM, Plymouth, Limine and Chromium's policy (asks for the password)",
		Args:         "[--dry-run] [--elevate pkexec|sudo]",
		RequiresSudo: true,
		Examples:     []string{"subcult theme apply-system", "subcult theme apply-system --dry-run"}}},
	{Words: []string{"theme", "system-apply"}, Metadata: dispatch.Metadata{
		Summary: "The privileged half of theme apply-system: write the files for the colours given",
		Args:    "--colors role=#rrggbb,... --appearance dark|light [--no-initramfs]", Hidden: true, RequiresSudo: true}},
}

// selfPath is what pkexec runs; the polkit action names it.
const selfPath = "/usr/bin/subcult-theme"

type app struct {
	stdout, stderr               io.Writer
	home, xdgConfig, subcultPath string
	// elevate runs the privileged half; tests replace it.
	elevate func(tool string, args ...string) error
	// initramfs rebuilds the initramfs; tests replace it.
	initramfs func() error
	// euid is the effective user; tests replace it.
	euid func() int
}

func (a *app) run(args []string) int {
	if len(args) == 1 && args[0] == dispatch.MetadataFlag {
		if err := json.NewEncoder(a.stdout).Encode(routes); err != nil {
			return 1
		}
		return 0
	}
	if len(args) == 0 {
		fmt.Fprintln(a.stderr, "Usage: subcult theme apply-system [--dry-run] [--elevate pkexec|sudo]")
		return 2
	}
	switch args[0] {
	case "apply-system":
		return a.applySystem(args[1:])
	case "system-apply":
		return a.systemApply(args[1:])
	}
	fmt.Fprintln(a.stderr, "Usage: subcult theme apply-system [--dry-run] [--elevate pkexec|sudo]")
	return 2
}

// palettePath is the user's palette when Pult wrote one, else Subarchy's.
func (a *app) palettePath() string {
	cfg := a.xdgConfig
	if cfg == "" {
		cfg = filepath.Join(a.home, ".config")
	}
	user := filepath.Join(cfg, "subcult/theme/palette.json")
	if _, err := os.Stat(user); err == nil {
		return user
	}
	sp := a.subcultPath
	if sp == "" {
		sp = "/usr/share/subcult"
	}
	return filepath.Join(sp, "default/theme/palette.json")
}

func (a *app) applySystem(args []string) int {
	fs := flag.NewFlagSet("subcult theme apply-system", flag.ContinueOnError)
	fs.SetOutput(a.stderr)
	dry := fs.Bool("dry-run", false, "show the colours and targets, change nothing")
	elevate := fs.String("elevate", "pkexec", "how to become root: pkexec (asks through polkit) or sudo")
	if err := fs.Parse(args); err != nil {
		return 2
	}
	if *elevate != "pkexec" && *elevate != "sudo" {
		fmt.Fprintln(a.stderr, "subcult theme: --elevate takes pkexec or sudo")
		return 2
	}
	path := a.palettePath()
	data, err := os.ReadFile(path)
	if err != nil {
		fmt.Fprintf(a.stderr, "subcult theme: %v\n", err)
		return 1
	}
	p, err := systheme.ParsePalette(data)
	if err != nil {
		fmt.Fprintf(a.stderr, "subcult theme: %s: %v\n", path, err)
		return 1
	}
	fmt.Fprintf(a.stdout, "palette: %s (%s, %d colours)\n", path, p.Appearance, len(p.Colors))
	privileged := []string{"system-apply", "--colors", p.Args(), "--appearance", p.Appearance}
	if *dry {
		fmt.Fprintln(a.stdout, "would run as root:", selfPath, strings.Join(privileged, " "))
		fmt.Fprintln(a.stdout, "targets: SDDM theme.conf, /boot/limine.conf colours, the Plymouth user theme (initramfs when it changes), Chromium's colour policy")
		return 0
	}
	if err := a.elevate(*elevate, append([]string{selfPath}, privileged...)...); err != nil {
		if ee, ok := err.(*exec.ExitError); ok {
			return ee.ExitCode()
		}
		fmt.Fprintf(a.stderr, "subcult theme: %v\n", err)
		return 1
	}
	return 0
}

func (a *app) systemApply(args []string) int {
	fs := flag.NewFlagSet("subcult theme system-apply", flag.ContinueOnError)
	fs.SetOutput(a.stderr)
	colors := fs.String("colors", "", "role=#rrggbb,...")
	appearance := fs.String("appearance", "dark", "dark or light")
	root := fs.String("root", "/", "the filesystem root (tests)")
	noInitramfs := fs.Bool("no-initramfs", false, "do not rebuild the initramfs when the splash changed")
	if err := fs.Parse(args); err != nil {
		return 2
	}
	p, err := systheme.ParseArgs(*colors, *appearance)
	if err != nil {
		fmt.Fprintf(a.stderr, "subcult theme system-apply: %v\n", err)
		return 2
	}
	if *root == "/" && a.euid() != 0 {
		fmt.Fprintln(a.stderr, "subcult theme system-apply: run as root (subcult theme apply-system does that through polkit)")
		return 1
	}
	// The polkit action allows this program, not its arguments: as root,
	// another root would let the caller choose the files root rewrites.
	if *root != "/" && a.euid() == 0 {
		fmt.Fprintln(a.stderr, "subcult theme system-apply: --root is for tests and is refused as root")
		return 2
	}
	rep, err := systheme.Apply(*root, p)
	for _, w := range rep.Written {
		fmt.Fprintln(a.stdout, "wrote", "/"+w)
	}
	for _, u := range rep.Unchanged {
		fmt.Fprintln(a.stdout, "unchanged", "/"+u)
	}
	for _, s := range rep.Skipped {
		fmt.Fprintln(a.stdout, "skipped:", s)
	}
	if err != nil {
		fmt.Fprintf(a.stderr, "subcult theme system-apply: %v\n", err)
		return 1
	}
	if rep.PlymouthChanged {
		if *noInitramfs || *root != "/" {
			fmt.Fprintln(a.stdout, "the splash changed; rebuild the boot images with limine-mkinitcpio for it to show at boot")
		} else {
			fmt.Fprintln(a.stdout, "the splash changed; rebuilding the initramfs (limine-mkinitcpio)")
			if err := a.initramfs(); err != nil {
				fmt.Fprintf(a.stderr, "subcult theme system-apply: limine-mkinitcpio: %v\n", err)
				return 1
			}
		}
	} else {
		fmt.Fprintln(a.stdout, "the splash is unchanged; no initramfs rebuild")
	}
	return 0
}

func main() {
	a := &app{
		stdout: os.Stdout, stderr: os.Stderr,
		home: os.Getenv("HOME"), xdgConfig: os.Getenv("XDG_CONFIG_HOME"), subcultPath: os.Getenv("SUBCULT_PATH"),
		elevate: func(tool string, args ...string) error {
			cmd := exec.Command(tool, args...)
			cmd.Stdin, cmd.Stdout, cmd.Stderr = os.Stdin, os.Stdout, os.Stderr
			return cmd.Run()
		},
		// limine-mkinitcpio rebuilds each kernel's UKI and its Limine entry,
		// which is what boots. Installs have no mkinitcpio presets, so
		// `mkinitcpio -P` fails, and under pkexec's PATH it skips the
		// /usr/local/bin wrapper that would have run limine-mkinitcpio.
		initramfs: func() error {
			cmd := exec.Command("/usr/bin/limine-mkinitcpio")
			cmd.Stdout, cmd.Stderr = os.Stdout, os.Stderr
			return cmd.Run()
		},
		euid: os.Geteuid,
	}
	os.Exit(a.run(os.Args[1:]))
}
