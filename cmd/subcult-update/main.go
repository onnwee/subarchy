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
	"path/filepath"
	"strconv"
	"strings"
	"syscall"

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
	{Words: []string{"update", "privileged"}, Metadata: dispatch.Metadata{
		Summary: "Run one root step of the update (used through sudo)",
		Args:    "snapshot | upgrade [--noconfirm] | prune", Hidden: true, RequiresSudo: true}},
}

// selfPath is the installed helper used for the privileged steps.
const selfPath = "/usr/bin/subcult-update"

type app struct {
	stdin          io.Reader
	stdout, stderr io.Writer
	runner         update.Runner
	migrations     func() (update.Migrations, error)
	euid           int
	procDir        string // /proc, for the services step
	stateDir       func() (string, error)
}

func main() {
	ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM, syscall.SIGHUP)
	defer stop()
	a := &app{
		stdin: os.Stdin, stdout: os.Stdout, stderr: os.Stderr,
		runner:     update.ExecRunner{Stdin: os.Stdin, Stdout: os.Stdout, Stderr: os.Stderr},
		migrations: update.DefaultMigrations,
		euid:       os.Geteuid(),
		procDir:    "/proc",
		stateDir:   stateDir,
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
	if sub == "privileged" {
		return a.privileged(ctx, strings.Join(args, " "))
	}
	flags := map[string]bool{}
	for _, f := range args {
		flags[f] = true
	}
	allowed := map[string][]string{
		"":        {"--yes", "-y", "--no-snapshot", "--dry-run", "-n", "--help", "-h"},
		"check":   {"--quiet", "-q", "--state"},
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
		return a.check(ctx, flags["--quiet"] || flags["-q"], flags["--state"])
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
	} else {
		stopAuthorization, err := update.Authorize(ctx, r)
		if err != nil {
			return a.fail(err)
		}
		defer stopAuthorization()
	}
	u := &update.Updater{R: r, O: update.Options{
		Yes: yes, NoSnapshot: noSnapshot || dryRun, Version: dispatch.Version,
		ModulesDir: "/usr/lib/modules", ProcDir: "/proc", Migrations: m, Stdin: a.stdin, Stdout: a.stdout,
		Privileged:      []string{"sudo", selfPath, "privileged"},
		ChannelRefresh:  []string{"sudo", "/usr/bin/subcult-channel", "refresh", "--quiet"},
		HyprlandSession: os.Getenv("HYPRLAND_INSTANCE_SIGNATURE") != "",
	}}
	rep, err := u.Run(ctx)
	if err != nil {
		return a.fail(err)
	}
	fmt.Fprint(a.stdout, "\n"+rep.Summary())
	// The bar reads a persisted count. Refresh it after the upgrade instead
	// of leaving yesterday's value visible until the randomized daily check.
	if !dryRun && a.runner.Has("checkupdates") {
		fmt.Fprintln(a.stdout, ">> refreshing the update indicator")
		if code := a.check(ctx, false, true); code == 1 {
			fmt.Fprintln(a.stdout, "warning: the update indicator could not be refreshed.")
		}
	}
	return 0
}

// check prints the number of available updates. Exit 0 when there are
// updates, 2 when there are none (checkupdates' convention), 1 on error.
// privileged runs one fixed root step after normal sudo authentication
// (ADR 0069).
func (a *app) privileged(ctx context.Context, step string) int {
	argv, ok := update.PrivilegedSteps(dispatch.Version)[step]
	if !ok && step != "services" {
		return a.usage(fmt.Errorf("unknown privileged step %q", step))
	}
	if a.euid != 0 {
		return a.fail(errors.New("privileged steps run as root, through sudo"))
	}
	if step == "services" {
		services, err := update.ServicesNeedingRestart(a.procDir)
		if err != nil {
			return a.fail(err)
		}
		for _, s := range services {
			fmt.Fprintln(a.stdout, s)
		}
		return 0
	}
	if step == "snapshot" {
		out, err := a.runner.Output(ctx, argv...)
		fmt.Fprint(a.stdout, out)
		if err != nil {
			return a.fail(err)
		}
		return 0
	}
	if err := a.runner.Run(ctx, argv...); err != nil {
		return a.fail(err)
	}
	return 0
}

func stateDir() (string, error) {
	state := os.Getenv("XDG_STATE_HOME")
	if state == "" {
		home, err := os.UserHomeDir()
		if err != nil {
			return "", err
		}
		state = filepath.Join(home, ".local", "state")
	}
	return filepath.Join(state, "subcult"), nil
}

// writeState records the update count for the bar (ADR 0026).
func (a *app) writeState(n int) error {
	dir, err := a.stateDir()
	if err != nil {
		return err
	}
	if err := os.MkdirAll(dir, 0o755); err != nil {
		return err
	}
	return os.WriteFile(filepath.Join(dir, "update-count"), []byte(strconv.Itoa(n)+"\n"), 0o644)
}

func (a *app) check(ctx context.Context, quiet, state bool) int {
	if !a.runner.Has("checkupdates") {
		return a.fail(errors.New("checkupdates not found (pacman-contrib)"))
	}
	out, err := a.runner.Output(ctx, "checkupdates", "--nocolor")
	var exit *exec.ExitError
	if errors.As(err, &exit) && exit.ExitCode() == 2 {
		if state {
			if err := a.writeState(0); err != nil {
				return a.fail(err)
			}
		}
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
	if state {
		if err := a.writeState(n); err != nil {
			return a.fail(err)
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
