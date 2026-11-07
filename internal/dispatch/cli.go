package dispatch

import (
	"encoding/json"
	"fmt"
	"io"
	"sort"
	"strings"
	"text/tabwriter"
)

// Version is set at build time with -ldflags.
var Version = "0.0.0"

// Execer replaces the current process with the command; injected for tests.
type Execer func(path string, argv []string) error

// App is the subcult front end.
type App struct {
	Registry *Registry
	Stdout   io.Writer
	Stderr   io.Writer
	Exec     Execer
}

// Run dispatches args (without the program name) and returns an exit code.
func (a *App) Run(args []string) int {
	if len(args) == 0 {
		a.usage(a.Stdout)
		return 0
	}
	switch args[0] {
	case "-h", "--help", "help":
		if len(args) > 1 {
			return a.groupHelp(args[1:])
		}
		a.usage(a.Stdout)
		return 0
	case "-V", "--version", "version":
		fmt.Fprintf(a.Stdout, "subcult %s\n", Version)
		return 0
	case "commands":
		return a.commands(args[1:])
	}

	if cmd, rest, ok := a.Registry.Resolve(args); ok {
		if len(rest) > 0 && (rest[0] == "--help" || rest[0] == "-h") && cmd.Summary != "" {
			a.commandHelp(cmd)
			return 0
		}
		argv := append([]string{cmd.Binary}, cmd.ArgPrefix...)
		if err := a.Exec(cmd.Path, append(argv, rest...)); err != nil {
			fmt.Fprintf(a.Stderr, "subcult: run %s: %v\n", cmd.Binary, err)
			return 126
		}
		return 0
	}

	words := leadingWords(args)
	if len(a.Registry.Group(words, false)) > 0 {
		return a.groupHelp(words)
	}
	fmt.Fprintf(a.Stderr, "subcult: unknown command %q\n", strings.Join(words, " "))
	if sug := a.Registry.Suggest(words, 3); len(sug) > 0 {
		fmt.Fprintln(a.Stderr, "Did you mean:")
		for _, s := range sug {
			fmt.Fprintf(a.Stderr, "  %s\n", s)
		}
	}
	return 127
}

func leadingWords(args []string) []string {
	var words []string
	for _, a := range args {
		if strings.HasPrefix(a, "-") {
			break
		}
		words = append(words, a)
	}
	if len(words) == 0 {
		words = args[:1]
	}
	return words
}

func (a *App) commands(args []string) int {
	asJSON, all := false, false
	for _, f := range args {
		switch f {
		case "--json":
			asJSON = true
		case "--all":
			all = true
		default:
			fmt.Fprintf(a.Stderr, "subcult commands: unknown flag %q\n", f)
			return 2
		}
	}
	cmds := a.Registry.Commands(all)
	if asJSON {
		enc := json.NewEncoder(a.Stdout)
		enc.SetIndent("", "  ")
		if err := enc.Encode(map[string]any{"ok": true, "commands": cmds}); err != nil {
			fmt.Fprintf(a.Stderr, "subcult commands: %v\n", err)
			return 1
		}
		return 0
	}
	a.table(cmds)
	return 0
}

func (a *App) table(cmds []Command) {
	tw := tabwriter.NewWriter(a.Stdout, 0, 4, 2, ' ', 0)
	for _, c := range cmds {
		fmt.Fprintf(tw, "  %s\t%s\t%s\n", c.Route, c.Args, c.Summary)
	}
	_ = tw.Flush() // writing to a terminal or buffer; nothing to recover
}

func (a *App) groupHelp(words []string) int {
	cmds := a.Registry.Group(words, false)
	if cmd, _, ok := a.Registry.Resolve(words); ok && len(cmds) == 0 {
		a.commandHelp(cmd)
		return 0
	}
	if len(cmds) == 0 {
		fmt.Fprintf(a.Stderr, "subcult: no commands under %q\n", strings.Join(words, " "))
		return 127
	}
	fmt.Fprintf(a.Stdout, "Commands under subcult %s:\n", strings.Join(words, " "))
	a.table(cmds)
	return 0
}

func (a *App) commandHelp(c Command) {
	fmt.Fprintf(a.Stdout, "%s %s\n", c.Route, c.Args)
	if c.Summary != "" {
		fmt.Fprintf(a.Stdout, "\n%s\n", c.Summary)
	}
	if len(c.Examples) > 0 {
		fmt.Fprintln(a.Stdout, "\nExamples:")
		for _, ex := range c.Examples {
			fmt.Fprintf(a.Stdout, "  %s\n", ex)
		}
	}
	if c.RequiresSudo {
		fmt.Fprintln(a.Stdout, "\nNeeds administrator rights.")
	}
	if c.Dangerous {
		fmt.Fprintln(a.Stdout, "Asks for confirmation from the launcher: changes are hard to undo.")
	}
}

func (a *App) usage(w io.Writer) {
	fmt.Fprintf(w, "subcult %s: Subarchy's command line\n\n", Version)
	fmt.Fprintln(w, "Usage: subcult <group> <action> [args]   (also: sub)")
	fmt.Fprintln(w, "       subcult commands [--json] [--all]")
	fmt.Fprintln(w, "       subcult help <group>")
	groups := map[string]int{}
	for _, c := range a.Registry.Commands(false) {
		groups[c.Group]++
	}
	if len(groups) == 0 {
		return
	}
	names := make([]string, 0, len(groups))
	for g := range groups {
		names = append(names, g)
	}
	sort.Strings(names)
	fmt.Fprintln(w, "\nGroups:")
	tw := tabwriter.NewWriter(w, 0, 4, 2, ' ', 0)
	for _, g := range names {
		fmt.Fprintf(tw, "  %s\t%d commands\n", g, groups[g])
	}
	_ = tw.Flush()
}
