// Command subcult-agent serves `subcult agent ...` (ADR 0047). `agent usage`
// reads what the coding agents on this machine used today and this week,
// their pace and the rate limits they last wrote to disk, from their own
// local files (Claude Code and Codex); nothing on the network. The agents
// bar widget shows its JSON.
package main

import (
	"encoding/json"
	"flag"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"time"

	"git.subcult.tv/subculture-collective/subarchy/internal/agentusage"
	"git.subcult.tv/subculture-collective/subarchy/internal/dispatch"
)

var routes = []dispatch.Described{
	{Words: []string{"agent", "usage"}, Metadata: dispatch.Metadata{
		Summary:  "Show the coding agents' token use today and this week, their pace and rate limits",
		Args:     "[--json]",
		Examples: []string{"subcult agent usage", "subcult agent usage --json"}}},
}

func run(args []string, stdout, stderr io.Writer, now time.Time) int {
	if len(args) == 1 && args[0] == dispatch.MetadataFlag {
		if err := json.NewEncoder(stdout).Encode(routes); err != nil {
			return 1
		}
		return 0
	}
	if len(args) == 0 || args[0] != "usage" {
		fmt.Fprintln(stderr, "Usage: subcult agent usage [--json]")
		return 2
	}
	fs := flag.NewFlagSet("subcult agent usage", flag.ContinueOnError)
	fs.SetOutput(stderr)
	asJSON := fs.Bool("json", false, "machine-readable output")
	home := fs.String("home", "", "the home directory to read (default $HOME)")
	cachePath := fs.String("cache", "", "the cache file (default $XDG_CACHE_HOME/subcult/agent-usage.json)")
	if err := fs.Parse(args[1:]); err != nil {
		return 2
	}
	if *home == "" {
		*home = os.Getenv("HOME")
	}
	if *home == "" {
		fmt.Fprintln(stderr, "subcult agent: no home directory")
		return 1
	}
	if *cachePath == "" {
		dir := os.Getenv("XDG_CACHE_HOME")
		if dir == "" {
			dir = filepath.Join(*home, ".cache")
		}
		*cachePath = filepath.Join(dir, "subcult", "agent-usage.json")
	}
	cache := agentusage.LoadCache(*cachePath)
	report := agentusage.Scan(*home, &cache, now)
	if err := cache.Save(*cachePath); err != nil {
		fmt.Fprintf(stderr, "subcult agent: cache not saved: %v\n", err)
	}
	if *asJSON {
		enc := json.NewEncoder(stdout)
		enc.SetIndent("", "  ")
		if err := enc.Encode(report); err != nil {
			return 1
		}
		return 0
	}
	for _, a := range report.Agents {
		if !a.Found {
			fmt.Fprintf(stdout, "%-12s not set up\n", a.Name)
			continue
		}
		fmt.Fprintf(stdout, "%-12s today %s (%s out)  week %s  pace %s/h", a.Name,
			tokens(a.Today.Total), tokens(a.Today.Output), tokens(a.Week.Total), tokens(a.PaceHour))
		for _, l := range a.Limits {
			fmt.Fprintf(stdout, "  %s %.0f%%", l.Name, l.UsedPercent)
			if !l.ResetsAt.IsZero() {
				fmt.Fprintf(stdout, " (resets %s)", l.ResetsAt.Local().Format("Mon 15:04"))
			}
		}
		fmt.Fprintln(stdout)
	}
	return 0
}

// 1234 -> "1.2k", 2345678 -> "2.3M", 3456789012 -> "3.5G".
func tokens(n int) string {
	switch {
	case n >= 1000000000:
		return fmt.Sprintf("%.1fG", float64(n)/1e9)
	case n >= 1000000:
		return fmt.Sprintf("%.1fM", float64(n)/1e6)
	case n >= 1000:
		return fmt.Sprintf("%.1fk", float64(n)/1e3)
	}
	return fmt.Sprint(n)
}

func main() {
	os.Exit(run(os.Args[1:], os.Stdout, os.Stderr, time.Now()))
}
