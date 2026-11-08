package main

import (
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"text/tabwriter"

	"git.subcult.tv/subculture-collective/subarchy/internal/apps"
	"git.subcult.tv/subculture-collective/subarchy/internal/dispatch"
)

type cli struct {
	stdout, stderr io.Writer
	paths          func() (apps.Paths, error)
	run            func(apps.Step) error
}

// routes describes the subcommands to the dispatcher (dispatch.MetadataFlag).
var routes = []dispatch.Described{
	{Words: []string{"app", "list"}, Metadata: dispatch.Metadata{
		Summary: "List the app catalogue", Args: "[--role ROLE] [--json]",
		Examples: []string{"subcult app list", "subcult app list --role browser"}}},
	{Words: []string{"app", "show"}, Metadata: dispatch.Metadata{
		Summary: "Show one app", Args: "<id> [--json]", Examples: []string{"subcult app show vlc"}}},
	{Words: []string{"app", "install"}, Metadata: dispatch.Metadata{
		Summary: "Install apps from the catalogue", Args: "<id>... [--dry-run]", RequiresSudo: true,
		Examples: []string{"subcult app install steam lutris", "subcult app install freecad --dry-run"}}},
	{Words: []string{"app", "remove"}, Metadata: dispatch.Metadata{
		Summary: "Remove apps installed from the catalogue", Args: "<id>... [--dry-run]", RequiresSudo: true, Dangerous: true,
		Examples: []string{"subcult app remove steam"}}},
	{Words: []string{"app", "default"}, Metadata: dispatch.Metadata{
		Summary: "Show or set the default app per role", Args: "[<role> [<id>]] [--dry-run]",
		Examples: []string{"subcult app default", "subcult app default browser", "subcult app default browser chromium"}}},
	{Words: []string{"app", "webapp"}, Metadata: dispatch.Metadata{
		Summary:  "Open a site as an app (a Chromium app window with its own desktop entry)",
		Args:     "install <name> <url> [--icon FILE] | remove <name>",
		Examples: []string{"subcult app webapp install \"Google Maps\" maps.google.com", "subcult app webapp remove \"Google Maps\""}}},
	{Words: []string{"app", "validate"}, Metadata: dispatch.Metadata{
		Summary: "Check the system and user catalogue files", Args: "[file]"}},
}

type options struct {
	dryRun, json bool
	role         string
	args         []string
	icon         string // --icon FILE for webapp install
}

func parseOptions(args []string) (options, error) {
	var o options
	for i := 0; i < len(args); i++ {
		switch a := args[i]; {
		case a == "--dry-run" || a == "-n":
			o.dryRun = true
		case a == "--json":
			o.json = true
		case a == "--role":
			if i+1 >= len(args) {
				return o, errors.New("--role needs a value")
			}
			i++
			o.role = args[i]
		case strings.HasPrefix(a, "--role="):
			o.role = strings.TrimPrefix(a, "--role=")
		case a == "--icon":
			if i+1 >= len(args) {
				return o, errors.New("--icon needs a file")
			}
			i++
			o.icon = args[i]
		case strings.HasPrefix(a, "--icon="):
			o.icon = strings.TrimPrefix(a, "--icon=")
		case strings.HasPrefix(a, "-") && a != "-":
			return o, fmt.Errorf("unknown option %s", a)
		default:
			o.args = append(o.args, a)
		}
	}
	return o, nil
}

func (c *cli) main(args []string) int {
	if len(args) == 1 && args[0] == dispatch.MetadataFlag {
		if err := json.NewEncoder(c.stdout).Encode(routes); err != nil {
			return c.fail(err)
		}
		return 0
	}
	if len(args) == 0 || args[0] == "help" || args[0] == "--help" || args[0] == "-h" {
		c.usage(c.stdout)
		return 0
	}
	sub, rest := args[0], args[1:]
	o, err := parseOptions(rest)
	if err != nil {
		return c.usageError(err)
	}
	if sub == "validate" {
		return c.validate(o)
	}
	paths, err := c.paths()
	if err != nil {
		return c.fail(err)
	}
	cat, err := apps.Load(paths)
	if err != nil {
		return c.fail(err)
	}
	switch sub {
	case "list":
		return c.list(cat, o)
	case "show":
		return c.show(cat, o)
	case "install":
		return c.change(cat, o, func(a apps.App) ([]apps.Step, error) { return apps.InstallPlanAt(a, paths) })
	case "remove":
		return c.change(cat, o, func(a apps.App) ([]apps.Step, error) { return apps.RemovePlanAt(a, paths) })
	case "webapp":
		return c.webapp(paths, o)
	case "default":
		return c.setDefault(cat, paths, o)
	default:
		return c.usageError(fmt.Errorf("unknown subcommand %q", sub))
	}
}

// webapp installs or removes a site as a Chromium app window (ADR 0042):
// `webapp install <name> <url> [--icon FILE]`, `webapp remove <name>`.
func (c *cli) webapp(paths apps.Paths, o options) int {
	if len(o.args) == 0 {
		return c.usageError(errors.New("webapp needs install <name> <url> or remove <name>"))
	}
	var steps []apps.Step
	var err error
	switch o.args[0] {
	case "install":
		if len(o.args) != 3 {
			return c.usageError(errors.New("webapp install needs a name and a URL"))
		}
		steps, err = apps.WebappPlan(paths.Applications, paths.Icons, o.args[1], o.args[2], o.icon)
	case "remove":
		if len(o.args) != 2 {
			return c.usageError(errors.New("webapp remove needs a name"))
		}
		steps, err = apps.WebappRemovePlan(paths.Applications, paths.Icons, o.args[1])
	default:
		return c.usageError(fmt.Errorf("webapp: unknown action %q", o.args[0]))
	}
	if err != nil {
		return c.fail(err)
	}
	for _, s := range steps {
		if o.dryRun {
			fmt.Fprintln(c.stdout, s)
			continue
		}
		if err := c.run(s); err != nil {
			return c.fail(err)
		}
	}
	return 0
}

func (c *cli) usage(w io.Writer) {
	fmt.Fprintln(w, "Usage: subcult app <command>")
	fmt.Fprintln(w)
	tw := tabwriter.NewWriter(w, 0, 0, 2, ' ', 0)
	for _, r := range routes {
		fmt.Fprintf(tw, "  %s %s\t%s\n", r.Words[1], r.Args, r.Summary)
	}
	tw.Flush()
}

func (c *cli) usageError(err error) int {
	fmt.Fprintf(c.stderr, "subcult app: %v\n\n", err)
	c.usage(c.stderr)
	return 2
}

func (c *cli) fail(err error) int {
	fmt.Fprintf(c.stderr, "subcult app: %v\n", err)
	return 1
}

func (c *cli) validate(o options) int {
	if len(o.args) > 1 {
		return c.usageError(errors.New("validate takes at most one file"))
	}
	if len(o.args) == 1 {
		// A single file is checked as a system catalogue on its own.
		if _, err := apps.Load(apps.Paths{System: o.args[0]}); err != nil {
			return c.fail(err)
		}
		fmt.Fprintf(c.stdout, "%s: ok\n", o.args[0])
		return 0
	}
	paths, err := c.paths()
	if err != nil {
		return c.fail(err)
	}
	cat, err := apps.Load(paths)
	if err != nil {
		return c.fail(err)
	}
	fmt.Fprintf(c.stdout, "catalogue ok: %d apps, %d roles\n", len(cat.Apps()), len(cat.Roles()))
	return 0
}

func (c *cli) list(cat *apps.Catalog, o options) int {
	if len(o.args) > 0 {
		return c.usageError(errors.New("list takes no arguments"))
	}
	list := cat.Apps()
	if o.role != "" {
		list = cat.ForRole(o.role)
		if len(list) == 0 {
			return c.fail(fmt.Errorf("no apps for role %q", o.role))
		}
	}
	if o.json {
		return c.encode(list)
	}
	tw := tabwriter.NewWriter(c.stdout, 0, 0, 2, ' ', 0)
	fmt.Fprintln(tw, "ID\tNAME\tROLES\tSOURCE\tSHIPS")
	for _, a := range list {
		roles := make([]string, len(a.Roles))
		for i, r := range a.Roles {
			roles[i] = r
			if d, ok := cat.Default(r); ok && d.ID == a.ID {
				roles[i] += "*"
			}
		}
		ships := "offered"
		if a.Preinstalled {
			ships = "preinstalled"
		}
		fmt.Fprintf(tw, "%s\t%s\t%s\t%s\t%s\n", a.ID, a.Name, strings.Join(roles, ","), a.Source, ships)
	}
	tw.Flush()
	fmt.Fprintln(c.stdout, "\n* default for that role")
	return 0
}

func (c *cli) show(cat *apps.Catalog, o options) int {
	if len(o.args) != 1 {
		return c.usageError(errors.New("show takes one app id"))
	}
	a, ok := cat.App(o.args[0])
	if !ok {
		return c.fail(fmt.Errorf("no app %q", o.args[0]))
	}
	if o.json {
		return c.encode(a)
	}
	tw := tabwriter.NewWriter(c.stdout, 0, 0, 2, ' ', 0)
	field := func(k, v string) {
		if v != "" {
			fmt.Fprintf(tw, "%s:\t%s\n", k, v)
		}
	}
	field("id", a.ID)
	field("name", a.Name)
	field("roles", strings.Join(a.Roles, ", "))
	var defaults []string
	for _, r := range a.Roles {
		if d, ok := cat.Default(r); ok && d.ID == a.ID {
			defaults = append(defaults, r)
		}
	}
	field("default for", strings.Join(defaults, ", "))
	field("preinstalled", fmt.Sprint(a.Preinstalled))
	field("source", string(a.Source))
	field("packages", strings.Join(a.Packages, " "))
	field("desktop", a.Desktop)
	field("url", a.URL)
	field("notes", a.Notes)
	tw.Flush()
	return 0
}

func (c *cli) change(cat *apps.Catalog, o options, plan func(apps.App) ([]apps.Step, error)) int {
	if len(o.args) == 0 {
		return c.usageError(errors.New("name at least one app id"))
	}
	var steps []apps.Step
	for _, id := range o.args {
		a, ok := cat.App(id)
		if !ok {
			return c.fail(fmt.Errorf("no app %q (see subcult app list)", id))
		}
		s, err := plan(a)
		if err != nil {
			return c.fail(err)
		}
		steps = append(steps, s...)
	}
	return c.apply(steps, o.dryRun)
}

func (c *cli) setDefault(cat *apps.Catalog, paths apps.Paths, o options) int {
	switch len(o.args) {
	case 0:
		tw := tabwriter.NewWriter(c.stdout, 0, 0, 2, ' ', 0)
		fmt.Fprintln(tw, "ROLE\tDEFAULT\tCHOICES")
		for _, role := range cat.Roles() {
			def := "-"
			if a, ok := cat.Default(role); ok {
				def = a.ID
			}
			var ids []string
			for _, a := range cat.ForRole(role) {
				ids = append(ids, a.ID)
			}
			fmt.Fprintf(tw, "%s\t%s\t%s\n", role, def, strings.Join(ids, " "))
		}
		tw.Flush()
		return 0
	case 1:
		role := o.args[0]
		choices := cat.ForRole(role)
		if len(choices) == 0 {
			return c.fail(fmt.Errorf("no apps for role %q", role))
		}
		def, _ := cat.Default(role)
		for _, a := range choices {
			mark := " "
			if a.ID == def.ID {
				mark = "*"
			}
			fmt.Fprintf(c.stdout, "%s %s\t%s\n", mark, a.ID, a.Name)
		}
		return 0
	case 2:
		role, id := o.args[0], o.args[1]
		a, ok := cat.App(id)
		if !ok {
			return c.fail(fmt.Errorf("no app %q", id))
		}
		steps, err := apps.DefaultPlan(role, a, filepath.Dir(filepath.Dir(paths.Defaults)))
		if err != nil {
			return c.fail(err)
		}
		if o.dryRun {
			fmt.Fprintf(c.stdout, "record %s = %s in %s\n", role, id, paths.Defaults)
			return c.apply(steps, true)
		}
		if err := apps.SaveDefault(paths.Defaults, role, id); err != nil {
			return c.fail(err)
		}
		if code := c.apply(steps, false); code != 0 {
			return code
		}
		fmt.Fprintf(c.stdout, "%s is now the default %s\n", a.Name, role)
		return 0
	default:
		return c.usageError(errors.New("default takes a role and an app id"))
	}
}

func (c *cli) apply(steps []apps.Step, dryRun bool) int {
	for _, s := range steps {
		if dryRun {
			fmt.Fprintln(c.stdout, s)
			continue
		}
		if err := c.run(s); err != nil {
			return c.fail(fmt.Errorf("%s: %w", s, err))
		}
	}
	return 0
}

func (c *cli) encode(v any) int {
	enc := json.NewEncoder(c.stdout)
	enc.SetIndent("", "  ")
	if err := enc.Encode(v); err != nil {
		return c.fail(err)
	}
	return 0
}

// runStep performs a step for real.
func runStep(s apps.Step) error {
	if s.Path != "" {
		if err := os.MkdirAll(filepath.Dir(s.Path), 0o755); err != nil {
			return err
		}
		return os.WriteFile(s.Path, []byte(s.Content), 0o644)
	}
	cmd := exec.Command(s.Argv[0], s.Argv[1:]...)
	cmd.Stdin, cmd.Stdout, cmd.Stderr = os.Stdin, os.Stdout, os.Stderr
	return cmd.Run()
}
