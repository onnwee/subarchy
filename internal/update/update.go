package update

import (
	"bufio"
	"context"
	"errors"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"sort"
	"strings"
)

// Options controls one update run.
type Options struct {
	Yes        bool   // answer yes to every question
	NoSnapshot bool   // skip the pre-update snapshot
	Version    string // Subarchy version, for the snapshot description
	ModulesDir string // /usr/lib/modules
	Migrations Migrations
	Stdin      io.Reader
	Stdout     io.Writer
	// Privileged runs a fixed root step, e.g. ["sudo",
	// "/usr/bin/subcult-update", "privileged"]; sudoers lets wheel run those
	// exact command lines without a password (ADR 0062).
	Privileged []string
}

// PrivilegedSteps are the root steps `subcult-update privileged` accepts,
// mapped to the commands they run. Nothing in them comes from the caller.
func PrivilegedSteps(version string) map[string][]string {
	return map[string][]string{
		"snapshot": {"snapper", "-c", "root", "create", "--cleanup-algorithm", "number",
			"--print-number", "--description", "subcult update " + version},
		"upgrade":             {"pacman", "-Syu"},
		"upgrade --noconfirm": {"pacman", "-Syu", "--noconfirm"},
		"prune":               {"paccache", "-rk2"},
	}
}

func (u *Updater) priv(step ...string) []string {
	return append(append([]string{}, u.O.Privileged...), step...)
}

// Updater runs the update steps in the order ADR 0026 sets.
type Updater struct {
	R Runner
	O Options
}

// Report is what the update found worth telling the user.
type Report struct {
	Snapshot      string   // snapper snapshot number, if taken
	DKMSProblems  []string // "module/version for kernel": not installed
	Migrations    []string // migrations that ran
	RebootNeeded  bool
	RunningKernel string
}

// Run performs the update. A failure in the snapshot or package step stops
// the run; later steps report problems without stopping.
func (u *Updater) Run(ctx context.Context) (Report, error) {
	var rep Report
	say := func(format string, args ...any) { fmt.Fprintf(u.O.Stdout, ">> "+format+"\n", args...) }

	if !u.O.NoSnapshot && u.R.Has("snapper") {
		say("taking a snapshot")
		num, err := u.R.Output(ctx, u.priv("snapshot")...)
		if err != nil {
			return rep, fmt.Errorf("snapshot: %w (use --no-snapshot to update without one)", err)
		}
		rep.Snapshot = strings.TrimSpace(num)
	}

	say("upgrading packages")
	args := u.priv("upgrade")
	if u.O.Yes {
		args = append(args, "--noconfirm")
	}
	if err := u.R.Run(ctx, args...); err != nil {
		return rep, fmt.Errorf("packages: %w", err)
	}

	if u.R.Has("dkms") {
		say("checking DKMS modules")
		status, err := u.R.Output(ctx, "dkms", "status")
		if err != nil {
			return rep, fmt.Errorf("dkms status: %w", err)
		}
		kernels, err := InstalledKernels(u.O.ModulesDir)
		if err != nil {
			return rep, err
		}
		rep.DKMSProblems = CheckDKMS(status, kernels)
	}

	say("running migrations")
	ran, err := u.O.Migrations.Run(ctx, u.R)
	rep.Migrations = ran
	if err != nil {
		return rep, err
	}

	optional := []struct {
		tool, what string
		argv       []string
	}{
		{"fwupdmgr", "firmware", []string{"fwupdmgr", "update"}},
		{"yay", "AUR packages", []string{"yay", "-Sua"}},
		{"mise", "mise tools", []string{"mise", "upgrade"}},
	}
	for _, o := range optional {
		if !u.R.Has(o.tool) {
			continue
		}
		say("updating %s", o.what)
		argv := o.argv
		if u.O.Yes && o.tool == "yay" {
			argv = append(argv, "--noconfirm")
		}
		if err := u.R.Run(ctx, argv...); err != nil {
			fmt.Fprintf(u.O.Stdout, "   %s: %v (continuing)\n", o.what, err)
		}
	}

	if err := u.cleanup(ctx); err != nil {
		fmt.Fprintf(u.O.Stdout, "   cleanup: %v (continuing)\n", err)
	}

	running, err := u.R.Output(ctx, "uname", "-r")
	if err == nil {
		rep.RunningKernel = strings.TrimSpace(running)
		rep.RebootNeeded = RebootNeeded(u.O.ModulesDir, rep.RunningKernel)
	}
	return rep, nil
}

// cleanup offers to remove orphaned packages and prunes the package cache.
func (u *Updater) cleanup(ctx context.Context) error {
	out, err := u.R.Output(ctx, "pacman", "-Qdtq")
	orphans := strings.Fields(out)
	// pacman -Qdtq exits 1 when there are no orphans.
	if err != nil && len(orphans) > 0 {
		return fmt.Errorf("list orphans: %w", err)
	}
	if len(orphans) > 0 {
		fmt.Fprintf(u.O.Stdout, ">> %d orphaned packages: %s\n", len(orphans), strings.Join(orphans, " "))
		if u.ask("Remove them?") {
			if err := u.R.Run(ctx, append([]string{"sudo", "pacman", "-Rns", "--noconfirm"}, orphans...)...); err != nil {
				return err
			}
		}
	}
	if u.R.Has("paccache") {
		fmt.Fprintln(u.O.Stdout, ">> pruning the package cache (keeping 2 versions)")
		return u.R.Run(ctx, u.priv("prune")...)
	}
	return nil
}

func (u *Updater) ask(question string) bool {
	if u.O.Yes {
		return true
	}
	fmt.Fprintf(u.O.Stdout, "%s [y/N] ", question)
	line, err := bufio.NewReader(u.O.Stdin).ReadString('\n')
	if err != nil && !errors.Is(err, io.EOF) {
		return false
	}
	answer := strings.ToLower(strings.TrimSpace(line))
	return answer == "y" || answer == "yes"
}

// InstalledKernels returns the module directory names of packaged kernels:
// those with a pkgbase file, as Arch kernel packages install.
func InstalledKernels(modulesDir string) ([]string, error) {
	entries, err := os.ReadDir(modulesDir)
	if err != nil {
		return nil, fmt.Errorf("kernels: %w", err)
	}
	var kernels []string
	for _, e := range entries {
		if _, err := os.Stat(filepath.Join(modulesDir, e.Name(), "pkgbase")); err == nil {
			kernels = append(kernels, e.Name())
		}
	}
	sort.Strings(kernels)
	return kernels, nil
}

// CheckDKMS parses `dkms status` and returns, for every module, each
// installed kernel it is not installed for. Lines look like
// "nvidia/580.95.05, 7.2.14-zen1-1-zen, x86_64: installed".
func CheckDKMS(status string, kernels []string) []string {
	installed := map[string]map[string]bool{} // module -> kernel -> ok
	for _, line := range strings.Split(status, "\n") {
		head, state, ok := strings.Cut(line, ": ")
		if !ok {
			continue
		}
		fields := strings.Split(head, ", ")
		module := fields[0]
		if installed[module] == nil {
			installed[module] = map[string]bool{}
		}
		if len(fields) >= 2 && strings.HasPrefix(strings.TrimSpace(state), "installed") {
			installed[module][fields[1]] = true
		}
	}
	modules := make([]string, 0, len(installed))
	for m := range installed {
		modules = append(modules, m)
	}
	sort.Strings(modules)
	var problems []string
	for _, m := range modules {
		for _, k := range kernels {
			if !installed[m][k] {
				problems = append(problems, m+" for "+k)
			}
		}
	}
	return problems
}

// RebootNeeded reports whether the running kernel's modules are gone,
// which happens when its package was upgraded.
func RebootNeeded(modulesDir, running string) bool {
	if running == "" {
		return false
	}
	_, err := os.Stat(filepath.Join(modulesDir, running))
	return os.IsNotExist(err)
}

// Summary renders the report for the user.
func (r Report) Summary() string {
	var b strings.Builder
	if r.Snapshot != "" {
		fmt.Fprintf(&b, "Snapshot %s taken before the update; its boot entry undoes it.\n", r.Snapshot)
	}
	if len(r.Migrations) > 0 {
		fmt.Fprintf(&b, "Migrations run: %s\n", strings.Join(r.Migrations, ", "))
	}
	for _, p := range r.DKMSProblems {
		fmt.Fprintf(&b, "DKMS module not built: %s. Boot the other kernel or the snapshot if it fails.\n", p)
	}
	if r.RebootNeeded {
		fmt.Fprintf(&b, "Reboot needed: the running kernel %s was upgraded.\n", r.RunningKernel)
	} else {
		b.WriteString("No reboot needed.\n")
	}
	return b.String()
}
