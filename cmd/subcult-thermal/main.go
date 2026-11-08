// Command subcult-thermal serves `subcult thermal ...` (rice port: thermal
// alerts, issue #98; ADR 0054). `thermal zones` lists the kernel's thermal
// zones with their trip points; `thermal watch` sleeps on the kernel's
// thermal netlink events and prints one JSON line per trip point crossed,
// which the shell turns into an alert. Nothing polls.
package main

import (
	"encoding/json"
	"errors"
	"flag"
	"fmt"
	"io"
	"os"
	"time"

	"git.subcult.tv/subculture-collective/subarchy/internal/dispatch"
	"git.subcult.tv/subculture-collective/subarchy/internal/thermal"
)

var routes = []dispatch.Described{
	{Words: []string{"thermal", "zones"}, Metadata: dispatch.Metadata{
		Summary: "List the thermal zones and their trip points", Args: "[--json]",
		Examples: []string{"subcult thermal zones"}}},
	{Words: []string{"thermal", "watch"}, Metadata: dispatch.Metadata{
		Summary:  "Print a JSON line for every trip point crossed, from the kernel's events",
		Args:     "[--timeout <duration>]",
		Examples: []string{"subcult thermal watch", "subcult thermal watch --timeout 30s"}}},
}

// Exit codes of `watch`.
const (
	exitNoFamily = 3 // the kernel has no thermal netlink events
)

func run(args []string, stdout, stderr io.Writer) int {
	if len(args) == 1 && args[0] == dispatch.MetadataFlag {
		if err := json.NewEncoder(stdout).Encode(routes); err != nil {
			return 1
		}
		return 0
	}
	if len(args) == 0 || (args[0] != "zones" && args[0] != "watch") {
		fmt.Fprintln(stderr, "Usage: subcult thermal zones [--json] | watch [--timeout <duration>]")
		return 2
	}
	fs := flag.NewFlagSet("subcult thermal "+args[0], flag.ContinueOnError)
	fs.SetOutput(stderr)
	root := fs.String("root", "/sys", "the sysfs root (tests)")
	asJSON := fs.Bool("json", false, "machine-readable output")
	timeout := fs.Duration("timeout", 0, "stop after this long without an event (watch; 0 waits forever)")
	if err := fs.Parse(args[1:]); err != nil {
		return 2
	}
	if args[0] == "zones" {
		return zones(*root, *asJSON, stdout, stderr)
	}
	return watch(*root, *timeout, stdout, stderr)
}

func zones(root string, asJSON bool, stdout, stderr io.Writer) int {
	zs, err := thermal.Zones(root)
	if err != nil {
		fmt.Fprintf(stderr, "subcult thermal: %v\n", err)
		return 1
	}
	if asJSON {
		enc := json.NewEncoder(stdout)
		enc.SetIndent("", "  ")
		if zs == nil {
			zs = []thermal.Zone{}
		}
		if err := enc.Encode(zs); err != nil {
			return 1
		}
		return 0
	}
	for _, z := range zs {
		fmt.Fprintf(stdout, "zone %d  %-20s %5.1f °C\n", z.ID, z.Type, float64(z.Temp)/1000)
		for _, tr := range z.Trips {
			if tr.Temp < -200000 { // an unset trip reads as absolute zero
				continue
			}
			fmt.Fprintf(stdout, "  trip %d  %-10s %5.1f °C\n", tr.ID, tr.Kind, float64(tr.Temp)/1000)
		}
	}
	return 0
}

func watch(root string, timeout time.Duration, stdout, stderr io.Writer) int {
	conn, err := thermal.Dial()
	if err != nil {
		fmt.Fprintf(stderr, "subcult thermal: %v\n", err)
		return 1
	}
	defer conn.Close()
	if err := conn.SetTimeout(timeout); err != nil {
		fmt.Fprintf(stderr, "subcult thermal: %v\n", err)
		return 1
	}
	family, err := conn.Subscribe()
	if errors.Is(err, thermal.ErrNoFamily) {
		fmt.Fprintln(stderr, "subcult thermal: this kernel has no thermal netlink events")
		return exitNoFamily
	}
	if err != nil {
		fmt.Fprintf(stderr, "subcult thermal: %v\n", err)
		return 1
	}
	enc := json.NewEncoder(stdout)
	err = conn.Events(family.ID, root, func(e thermal.Event) error { return enc.Encode(e) })
	if errors.Is(err, os.ErrDeadlineExceeded) {
		return 0
	}
	fmt.Fprintf(stderr, "subcult thermal: %v\n", err)
	return 1
}

func main() {
	os.Exit(run(os.Args[1:], os.Stdout, os.Stderr))
}
