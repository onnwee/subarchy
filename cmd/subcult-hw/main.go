// Command subcult-hw serves `subcult hw ...` (ADR 0005, 0006, 0050):
// `hw packages` lists the microcode, firmware and GPU driver packages this
// machine needs, which the installer adds to the base set; `hw info` shows
// what was detected; `hw <question>` answers one of the matching questions
// the hardware fixes ask (exit 0 for yes), `hw match <text>` matches the
// product name or family, and `hw matches` lists every answer.
package main

import (
	"encoding/json"
	"flag"
	"fmt"
	"io"
	"os"
	"sort"
	"strings"

	"git.subcult.tv/subculture-collective/subarchy/internal/dispatch"
	"git.subcult.tv/subculture-collective/subarchy/internal/hw"
)

var routes = func() []dispatch.Described {
	r := []dispatch.Described{
		{Words: []string{"hw", "packages"}, Metadata: dispatch.Metadata{
			Summary:  "List the firmware, microcode and GPU driver packages this machine needs (--all: every package it could pick)",
			Args:     "[--all]",
			Examples: []string{"subcult hw packages", "subcult hw packages --all"}}},
		{Words: []string{"hw", "info"}, Metadata: dispatch.Metadata{
			Summary: "Show the detected CPU, GPUs, radios, notes and matches", Args: "[--json]",
			Examples: []string{"subcult hw info", "subcult hw info --json"}}},
		{Words: []string{"hw", "fixes"}, Metadata: dispatch.Metadata{
			Summary: "List the hardware fixes this machine gets (--all: the whole catalogue)", Args: "[--all] [--json]",
			Examples: []string{"subcult hw fixes", "subcult hw fixes --all --json"}}},
		{Words: []string{"hw", "apply"}, Metadata: dispatch.Metadata{
			Summary: "Write the hardware fixes' files (modprobe, initramfs, kernel command line); the installer runs it on the target",
			Args:    "[--target DIR]", RequiresSudo: true,
			Examples: []string{"sudo subcult hw apply", "subcult hw apply --target /mnt"}}},
		{Words: []string{"hw", "services"}, Metadata: dispatch.Metadata{
			Summary:  "List the system services the installer enables for this hardware",
			Examples: []string{"subcult hw services"}}},
		{Words: []string{"hw", "match"}, Metadata: dispatch.Metadata{
			Summary: "Exit 0 when the product name or family contains the text", Args: "<text>",
			Examples: []string{"subcult hw match XPS"}}},
		{Words: []string{"hw", "matches"}, Metadata: dispatch.Metadata{
			Summary: "Answer every hardware question (yes or no)", Args: "[--json]",
			Examples: []string{"subcult hw matches"}}},
	}
	for _, m := range hw.Matchers {
		r = append(r, dispatch.Described{Words: []string{"hw", m.Name}, Metadata: dispatch.Metadata{
			Summary: "Exit 0 on " + m.Name + " hardware (" + m.Source + ")", Hidden: true}})
	}
	return r
}()

func run(args []string, stdout, stderr io.Writer) int {
	if len(args) == 1 && args[0] == dispatch.MetadataFlag {
		if err := json.NewEncoder(stdout).Encode(routes); err != nil {
			return 1
		}
		return 0
	}
	if len(args) == 0 {
		fmt.Fprintln(stderr, "Usage: subcult hw packages | services | fixes [--all] | apply [--target DIR] | info [--json] | match <text> | matches [--json] | <question>")
		return 2
	}
	matcher, isMatcher := hw.FindMatcher(args[0])
	if !isMatcher && args[0] != "packages" && args[0] != "services" && args[0] != "info" && args[0] != "match" && args[0] != "matches" && args[0] != "fixes" && args[0] != "apply" {
		fmt.Fprintf(stderr, "subcult hw: unknown question %q; the questions are: %s\n", args[0], strings.Join(matcherNames(), ", "))
		return 2
	}
	fs := flag.NewFlagSet("subcult hw", flag.ContinueOnError)
	fs.SetOutput(stderr)
	root := fs.String("root", "/", "directory holding proc/ and sys/ (tests)")
	asJSON := fs.Bool("json", false, "machine-readable output")
	all := fs.Bool("all", false, "every package the selection can pick (packages), or the whole catalogue (fixes)")
	target := fs.String("target", "/", "where apply writes the files (the installer's target)")
	if err := fs.Parse(args[1:]); err != nil {
		return 2
	}
	if args[0] == "packages" && *all {
		for _, p := range hw.Catalog() {
			fmt.Fprintln(stdout, p)
		}
		return 0
	}
	if args[0] == "fixes" && *all {
		return printFixes(hw.AllFixes(), *asJSON, stdout)
	}
	m, err := hw.Detect(*root)
	if err != nil {
		fmt.Fprintf(stderr, "subcult hw: %v\n", err)
		return 1
	}
	if args[0] == "fixes" {
		return printFixes(hw.Fixes(m), *asJSON, stdout)
	}
	if args[0] == "apply" {
		if *target == "/" && os.Geteuid() != 0 {
			fmt.Fprintln(stderr, "subcult hw apply: writes under /etc; run it as root, or give --target")
			return 1
		}
		written, kept, err := hw.Apply(*target, hw.Fixes(m))
		if err != nil {
			fmt.Fprintf(stderr, "subcult hw apply: %v\n", err)
			return 1
		}
		for _, p := range written {
			fmt.Fprintln(stdout, "wrote", p)
		}
		for _, p := range kept {
			fmt.Fprintln(stdout, "kept", p, "(yours; not a Subarchy file)")
		}
		if hw.NeedsInitramfs(written) {
			fmt.Fprintln(stdout, "initramfs: the initramfs or kernel command line changed; rebuild the boot images with `sudo limine-mkinitcpio`")
		}
		return 0
	}
	if isMatcher {
		if matcher.Test(m) {
			if matcher.Name == "touchpad" || matcher.Name == "touchscreen" || matcher.Name == "display" {
				fmt.Fprintln(stdout, map[string]string{"touchpad": m.Facts.Touchpad, "touchscreen": m.Facts.Touchscreen, "display": m.Facts.Backlight}[matcher.Name])
			}
			return 0
		}
		return 1
	}
	if args[0] == "match" {
		if fs.NArg() != 1 {
			fmt.Fprintln(stderr, "Usage: subcult hw match <text>")
			return 2
		}
		if m.Match(fs.Arg(0)) {
			return 0
		}
		return 1
	}
	if args[0] == "matches" {
		matches := m.Matches()
		if *asJSON {
			enc := json.NewEncoder(stdout)
			enc.SetIndent("", "  ")
			if err := enc.Encode(matches); err != nil {
				return 1
			}
			return 0
		}
		for _, name := range matcherNames() {
			fmt.Fprintf(stdout, "%-26s%v\n", name, matches[name])
		}
		return 0
	}
	sel := hw.Select(m)
	if args[0] == "services" {
		for _, s := range sel.Services {
			fmt.Fprintln(stdout, s)
		}
		return 0
	}
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
			"cpu": m.CPUVendor, "vm": m.VM, "hybrid": m.Hybrid(), "packages": sel.Packages, "services": sel.Services, "notes": sel.Notes,
			"vendor": m.Facts.SysVendor, "product": m.Facts.ProductName, "family": m.Facts.ProductFamily,
			"matches": m.Matches(),
		}); err != nil {
			return 1
		}
		return 0
	}
	fmt.Fprintf(stdout, "CPU:       %s\n", m.CPUVendor)
	if m.Facts.SysVendor != "" {
		fmt.Fprintf(stdout, "Machine:   %s %s\n", m.Facts.SysVendor, m.Facts.ProductName)
	}
	for _, d := range m.Devices {
		if k := d.Kind(); k != "" {
			fmt.Fprintf(stdout, "%-11s%s %04x:%04x\n", k+":", d.Bus, d.Vendor, d.Device)
		}
	}
	if m.VM != "" {
		fmt.Fprintf(stdout, "VM:        %s\n", m.VM)
	}
	fmt.Fprintf(stdout, "Hybrid:    %v\n", m.Hybrid())
	var yes []string
	for name, ok := range m.Matches() {
		if ok {
			yes = append(yes, name)
		}
	}
	sort.Strings(yes)
	fmt.Fprintf(stdout, "Matches:   %s\n", strings.Join(yes, " "))
	for _, n := range sel.Notes {
		fmt.Fprintf(stdout, "Note:      %s\n", n)
	}
	return 0
}

func printFixes(fixes []hw.Fix, asJSON bool, stdout io.Writer) int {
	if asJSON {
		enc := json.NewEncoder(stdout)
		enc.SetIndent("", "  ")
		if err := enc.Encode(fixes); err != nil {
			return 1
		}
		return 0
	}
	for _, f := range fixes {
		state := "untested"
		if f.Tested {
			state = "tested"
		}
		fmt.Fprintf(stdout, "%-22s %-9s %s\n", f.Name, state, f.Summary)
		if f.Note != "" {
			fmt.Fprintf(stdout, "%-22s           note: %s\n", "", f.Note)
		}
	}
	return 0
}

func matcherNames() []string {
	var names []string
	for _, m := range hw.Matchers {
		names = append(names, m.Name)
	}
	return names
}

func main() { os.Exit(run(os.Args[1:], os.Stdout, os.Stderr)) }
