// Package update implements `subcult update` (ADR 0026): snapshot, upgrade,
// DKMS check, migrations, optional firmware/AUR/mise updates, cleanup and a
// report of what needs a restart.
package update

import (
	"bytes"
	"context"
	"fmt"
	"io"
	"os"
	"os/exec"
	"strings"
)

// Runner runs the system commands the update needs. Run is for commands
// that change the system and are shown to the user; Output is for read-only
// queries.
type Runner interface {
	Run(ctx context.Context, argv ...string) error
	Output(ctx context.Context, argv ...string) (string, error)
	Has(name string) bool
}

// ExecRunner runs commands for real, passing stdio through for Run.
type ExecRunner struct {
	Stdin          io.Reader
	Stdout, Stderr io.Writer
}

// Run executes argv with the terminal attached.
//
// When ctx is cancelled (Ctrl+C, a closed terminal, SIGTERM) the command
// gets SIGINT and is waited for, not killed. These commands change the
// system: pacman finishes the package it is on and removes its lock on
// SIGINT, and a killed pacman leaves a half-installed package and
// /var/lib/pacman/db.lck behind.
func (r ExecRunner) Run(ctx context.Context, argv ...string) error {
	cmd := exec.CommandContext(ctx, argv[0], argv[1:]...)
	cmd.Cancel = func() error { return cmd.Process.Signal(os.Interrupt) }
	cmd.Stdin, cmd.Stdout, cmd.Stderr = r.Stdin, r.Stdout, r.Stderr
	if err := cmd.Run(); err != nil {
		return fmt.Errorf("%s: %w", strings.Join(argv, " "), err)
	}
	return nil
}

// Output executes argv and returns its standard output.
func (r ExecRunner) Output(ctx context.Context, argv ...string) (string, error) {
	var out bytes.Buffer
	cmd := exec.CommandContext(ctx, argv[0], argv[1:]...)
	cmd.Stdout = &out
	cmd.Stderr = os.Stderr
	err := cmd.Run()
	return out.String(), err
}

// Has reports whether name is on PATH.
func (r ExecRunner) Has(name string) bool {
	_, err := exec.LookPath(name)
	return err == nil
}

// DryRunner prints commands that would change the system and runs only the
// read-only queries.
type DryRunner struct {
	Runner
	Out io.Writer
}

// Run prints argv instead of running it.
func (d DryRunner) Run(_ context.Context, argv ...string) error {
	fmt.Fprintf(d.Out, "would run: %s\n", strings.Join(argv, " "))
	return nil
}
