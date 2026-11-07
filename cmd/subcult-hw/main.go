// Command subcult-hw serves `subcult hw ...` (ADR 0005, 0006, 0050):
// `hw packages` lists the microcode, firmware and GPU driver packages this
// machine needs, which the installer adds to the base set; `hw info`
// shows what was detected.
package main

import (
	"encoding/json"
	"flag"
	"fmt"
	"io"
	"os"

	"git.subcult.tv/subculture-collective/subarchy/internal/dispatch"
	"git.subcult.tv/subculture-collective/subarchy/internal/hw"
)

var routes = []dispatch.Described{
	{Words: []string{"hw", "packages"}, Metadata: dispatch.Metadata{
		Summary:  "List the firmware, microcode and GPU driver packages this machine needs",
		Examples: []string{"subcult hw packages"}}},
	{Words: []string{"hw", "info"}, Metadata: dispatch.Metadata{
		Summary: "Show the detected CPU, GPUs, radios and notes", Args: "[--json]",
		Examples: []string{"subcult hw info", "subcult hw info --json"}}},
}

func run(args []string, stdout, stderr io.Writer) int {
	if len(args) == 1 && args[0] == dispatch.MetadataFlag {
		if err := json.NewEncoder(stdout).Encode(routes); err != nil {
			return 1
		}
		return 0
	}
	if len(args) == 0 || (args[0] != "packages" && args[0] != "info") {
		fmt.Fprintln(stderr, "Usage: subcult hw packages | subcult hw info [--json]")
		return 2
	}
	fs := flag.NewFlagSet("subcult hw", flag.ContinueOnError)
	fs.SetOutput(stderr)
	root := fs.String("root", "/", "directory holding proc/ and sys/ (tests)")
	asJSON := fs.Bool("json", false, "machine-readable output")
	if err := fs.Parse(args[1:]); err != nil {
		return 2
	}
	m, err := hw.Detect(*root)
	if err != nil {
		fmt.Fprintf(stderr, "subcult hw: %v\n", err)
		return 1
	}
	sel := hw.Select(m)
	if args[0] == "packages" {
		for _, p := range sel.Packages {
			fmt.Fprintln(stdout, p)
		}
		for _, n := range sel.Notes {
			fmt.Fprintf(stderr, "note: %s\n", n)
		}
		return 0
	}
	if *asJSON {
		enc := json.NewEncoder(stdout)
		enc.SetIndent("", "  ")
		if err := enc.Encode(map[string]any{
			"cpu": m.CPUVendor, "vm": m.VM, "hybrid": m.Hybrid(), "packages": sel.Packages, "notes": sel.Notes,
		}); err != nil {
			return 1
		}
		return 0
	}
	fmt.Fprintf(stdout, "CPU:       %s\n", m.CPUVendor)
	for _, d := range m.Devices {
		if k := d.Kind(); k != "" {
			fmt.Fprintf(stdout, "%-11s%s %04x:%04x\n", k+":", d.Bus, d.Vendor, d.Device)
		}
	}
	if m.VM != "" {
		fmt.Fprintf(stdout, "VM:        %s\n", m.VM)
	}
	fmt.Fprintf(stdout, "Hybrid:    %v\n", m.Hybrid())
	for _, n := range sel.Notes {
		fmt.Fprintf(stdout, "Note:      %s\n", n)
	}
	return 0
}

func main() { os.Exit(run(os.Args[1:], os.Stdout, os.Stderr)) }
