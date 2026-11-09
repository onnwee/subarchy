// Command subcult-idle serves `subcult idle ...` (ADR 0036): `idle` shows
// the idle settings, `idle config` prints the hypridle configuration they
// make, `idle apply` restarts the idle service after a change, and `idle
// run` (the service) writes the configuration and runs hypridle on it.
package main

import (
	"encoding/json"
	"flag"
	"fmt"
	"io"
	"os"
	"os/exec"
	"path/filepath"
	"syscall"

	"git.subcult.tv/subculture-collective/subarchy/internal/dispatch"
	"git.subcult.tv/subculture-collective/subarchy/internal/idle"
)

var routes = []dispatch.Described{
	{Words: []string{"idle"}, Metadata: dispatch.Metadata{
		Summary: "Show when the session locks, the display goes off and the machine suspends", Examples: []string{"subcult idle"}}},
	{Words: []string{"idle", "config"}, Metadata: dispatch.Metadata{
		Summary: "Print the hypridle configuration made from the idle settings", Examples: []string{"subcult idle config"}}},
	{Words: []string{"idle", "apply"}, Metadata: dispatch.Metadata{
		Summary: "Apply changed idle settings (restarts the idle service)", Examples: []string{"subcult idle apply"}}},
	{Words: []string{"idle", "run"}, Metadata: dispatch.Metadata{
		Summary: "Write the configuration and run hypridle on it (the idle service)", Hidden: true}},
}

type app struct {
	stdout, stderr io.Writer
	settingsPath   string
	runtimeDir     string
	// exec replaces the process (the service); restart runs systemctl. Tests swap them.
	exec    func(argv []string) error
	restart func() error
}

func (a *app) run(args []string) int {
	if len(args) == 1 && args[0] == dispatch.MetadataFlag {
		if err := json.NewEncoder(a.stdout).Encode(routes); err != nil {
			return 1
		}
		return 0
	}
	fs := flag.NewFlagSet("subcult idle", flag.ContinueOnError)
	fs.SetOutput(a.stderr)
	if err := fs.Parse(args); err != nil {
		return 2
	}
	s, err := idle.Load(a.settingsPath)
	if err != nil {
		fmt.Fprintf(a.stderr, "subcult idle: %v; using the defaults\n", err)
	}
	switch {
	case fs.NArg() == 0:
		fmt.Fprintln(a.stdout, idle.Summary(s))
		return 0
	case fs.Arg(0) == "config":
		fmt.Fprint(a.stdout, idle.Render(s))
		return 0
	case fs.Arg(0) == "apply":
		if err := a.restart(); err != nil {
			fmt.Fprintf(a.stderr, "subcult idle: %v\n", err)
			return 1
		}
		fmt.Fprintln(a.stdout, idle.Summary(s))
		return 0
	case fs.Arg(0) == "run":
		path := filepath.Join(a.runtimeDir, "subcult", "hypridle.conf")
		if err := os.MkdirAll(filepath.Dir(path), 0o700); err != nil {
			fmt.Fprintf(a.stderr, "subcult idle: %v\n", err)
			return 1
		}
		if err := os.WriteFile(path, []byte(idle.Render(s)), 0o600); err != nil {
			fmt.Fprintf(a.stderr, "subcult idle: %v\n", err)
			return 1
		}
		if err := a.exec([]string{"hypridle", "-c", path}); err != nil {
			fmt.Fprintf(a.stderr, "subcult idle: hypridle: %v\n", err)
			return 1
		}
		return 0
	}
	fmt.Fprintln(a.stderr, "Usage: subcult idle | idle config | idle apply")
	return 2
}

func main() {
	config := os.Getenv("XDG_CONFIG_HOME")
	if config == "" {
		config = filepath.Join(os.Getenv("HOME"), ".config")
	}
	runtime := os.Getenv("XDG_RUNTIME_DIR")
	if runtime == "" {
		runtime = os.TempDir()
	}
	a := &app{
		stdout: os.Stdout, stderr: os.Stderr,
		settingsPath: filepath.Join(config, "subcult", "idle.json"),
		runtimeDir:   runtime,
		exec: func(argv []string) error {
			path, err := exec.LookPath(argv[0])
			if err != nil {
				return err
			}
			return syscall.Exec(path, argv, os.Environ())
		},
		restart: func() error {
			c := exec.Command("systemctl", "--user", "restart", "subcult-idle.service")
			c.Stdout, c.Stderr = os.Stdout, os.Stderr
			return c.Run()
		},
	}
	os.Exit(a.run(os.Args[1:]))
}
