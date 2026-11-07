// Command subcult-update serves `subcult update` (ADR 0026): snapshot,
// upgrade, DKMS check, migrations, optional firmware/AUR/mise updates,
// cleanup and a report; `subcult update check` counts available updates;
// `subcult update migrate` runs or lists pending migrations.
package main

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"os"
	"os/exec"
	"os/signal"
	"strings"

	"git.subcult.tv/subculture-collective/subarchy/internal/dispatch"
	"git.subcult.tv/subculture-collective/subarchy/internal/update"
)

var routes = []dispatch.Described{
	{Words: []string{"update"}, Metadata: dispatch.Metadata{
		Summary: "Update the system: snapshot, packages, migrations, cleanup",
		Args:    "[--yes] [--no-snapshot] [--dry-run]", RequiresSudo: true,
		Examples: []string{"subcult update", "subcult update --dry-run"}}},
	{Words: []string{"update", "check"}, Metadata: dispatch.Metadata{
		Summary: "Count available package updates without installing them",
		Args:    "[--quiet]", Examples: []string{"subcult update check"}}},
	{Words: []string{"update", "migrate"}, Metadata: dispatch.Metadata{
		Summary: "Run pending migrations, or list them with --pending",
		Args:    "[--pending | --mark-all]", Examples: []string{"subcult update migrate --pending"}}},
}

type app struct {
	stdin          io.Reader
	stdout, stderr io.Writer
	runner         update.Runner
	migrations     func() (update.Migrations, error)
}

func main() {
	ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt)
	defer stop()
	a := &app{
		stdin: os.Stdin, stdout: os.Stdout, stderr: os.Stderr,
		runner:     update.ExecRunner{Stdin: os.Stdin, Stdout: os.Stdout, Stderr: os.Stderr},
		migrations: update.DefaultMigrations,
	}
	os.Exit(a.main(ctx, os.Args[1:]))
}

func (a *app) main(ctx context.Context, args []string) int {
	if len(args) == 1 && args[0] == dispatch.MetadataFlag {
		if err := json.NewEncoder(a.stdout).Encode(routes); err != nil {
			return a.fail(err)
		}
		return 0
	}
	sub := ""
	if len(args) > 0 && !strings.HasPrefix(args[0], "-") {
		sub, args = args[0], args[1:]
	}
	flags := map[string]bool{}
	for _, f := range args {
		flags[f] = true
	}
	allowed := map[string][]string{
		"":        {"--yes", "-y", "--no-snapshot", "--dry-run", "-n", "--help", "-h"},
		"check":   {"--quiet", "-q"},
		"migrate": {"--pending", "--mark-all"},
	}
	known, ok := allowed[sub]
	if !ok {
		return a.usage(fmt.Errorf("unknown subcommand %q", sub))
	}
	for f := range flags {
		if !contains(known, f) {
			return a.usage(fmt.Errorf("unknown option %s", f))
		}
	}
	switch sub {
	case "check":
		return a.check(ctx, flags["--quiet"] || flags["-q"])
	case "migrate":
		return a.migrate(ctx, flags["--pending"], flags["--mark-all"])
	}
	if flags["--help"] || flags["-h"] {
		a.help(a.stdout)
		return 0
	}
	return a.update(ctx, flags["--yes"] || flags["-y"], flags["--no-snapshot"], flags["--dry-run"] || flags["-n"])
}

func contains(list []string, s string) bool {
	for _, x := range list {
		if x == s {
			return true
		}
	}
	return false
}

func (a *app) help(w io.Writer) {
	fmt.Fprintln(w, "Usage:")
	for _, r := range routes {
		fmt.Fprintf(w, "  subcult %s %s\n      %s\n", strings.Join(r.Words, " "), r.Args, r.Summary)
	}
}

func (a *app) usage(err error) int {
	fmt.Fprintf(a.stderr, "subcult update: %v\n\n", err)
	a.help(a.stderr)
	return 2
}

func (a *app) fail(err error) int {
	fmt.Fprintf(a.stderr, "subcult update: %v\n", err)
	return 1
}

func (a *app) update(ctx context.Context, yes, noSnapshot, dryRun bool) int {
	m, err := a.migrations()
	if err != nil {
		return a.fail(err)
	}
	r := a.runner
	if dryRun {
		r = update.DryRunner{Runner: r, Out: a.stdout}
	}
	u := &update.Updater{R: r, O: update.Options{
		Yes: yes, NoSnapshot: noSnapshot || dryRun, Version: dispatch.Version,
		ModulesDir: "/usr/lib/modules", Migrations: m, Stdin: a.stdin, Stdout: a.stdout,
	}}
	rep, err := u.Run(ctx)
	if err != nil {
		return a.fail(err)
	}
	fmt.Fprint(a.stdout, "\n"+rep.Summary())
	return 0
}

// check prints the number of available updates. Exit 0 when there are
// updates, 2 when there are none (checkupdates' convention), 1 on error.
func (a *app) check(ctx context.Context, quiet bool) int {
	if !a.runner.Has("checkupdates") {
		return a.fail(errors.New("checkupdates not found (pacman-contrib)"))
	}
	out, err := a.runner.Output(ctx, "checkupdates", "--nocolor")
	var exit *exec.ExitError
	if errors.As(err, &exit) && exit.ExitCode() == 2 {
		if !quiet {
			fmt.Fprintln(a.stdout, "0 updates")
		}
		return 2
	}
	if err != nil {
		return a.fail(fmt.Errorf("checkupdates: %w", err))
	}
	n := 0
	for _, line := range strings.Split(out, "\n") {
		if strings.TrimSpace(line) != "" {
			n++
		}
	}
	if quiet {
		fmt.Fprintln(a.stdout, n)
	} else {
		fmt.Fprintf(a.stdout, "%d updates (run subcult update)\n", n)
	}
	return 0
}

func (a *app) migrate(ctx context.Context, pendingOnly, markAll bool) int {
	m, err := a.migrations()
	if err != nil {
		return a.fail(err)
	}
	switch {
	case pendingOnly && markAll:
		return a.usage(errors.New("--pending and --mark-all are exclusive"))
	case markAll:
		if err := m.MarkAll(); err != nil {
			return a.fail(err)
		}
		return 0
	case pendingOnly:
		pending, err := m.Pending()
		if err != nil {
			return a.fail(err)
		}
		for _, p := range pending {
			fmt.Fprintln(a.stdout, p)
		}
		if len(pending) == 0 {
			return 1 // like omarchy-migrate --pending: nothing pending
		}
		return 0
	}
	ran, err := m.Run(ctx, a.runner)
	for _, r := range ran {
		fmt.Fprintf(a.stdout, "ran %s\n", r)
	}
	if err != nil {
		return a.fail(err)
	}
	return 0
}
