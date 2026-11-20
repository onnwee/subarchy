// Command subcult-dns serves `subcult dns ...` (ADR 0020): `dns` shows the
// DNS trust of the active connections, `dns set` switches them between the
// untrusted and trusted modes.
//
//	subcult dns                                show the policy
//	subcult dns set <untrusted|trusted> [--connection NAME] [--dns ADDR[#NAME],...] [--no-check]
package main

import (
	"context"
	"encoding/json"
	"errors"
	"flag"
	"fmt"
	"io"
	"os"
	"strings"

	"git.subcult.tv/subculture-collective/subarchy/internal/dispatch"
	"git.subcult.tv/subculture-collective/subarchy/internal/dns"
	"git.subcult.tv/subculture-collective/subarchy/internal/update"
)

var routes = []dispatch.Described{
	{Words: []string{"dns"}, Metadata: dispatch.Metadata{
		Summary: "Show each active connection's DNS trust and the DNS servers in use", Examples: []string{"subcult dns"}}},
	{Words: []string{"dns", "set"}, Metadata: dispatch.Metadata{
		Summary:  "Switch connections between untrusted (Quad9 over TLS) and trusted (the network's DNS or your own)",
		Args:     "<untrusted|trusted> [--connection <name>] [--dns <addr[#tls-name],...>] [--no-check]",
		Examples: []string{"subcult dns set untrusted", "subcult dns set trusted --connection Home --dns 10.0.0.200,10.0.0.57"}}},
}

type env struct {
	runner         update.Runner
	stdout, stderr io.Writer
}

func main() {
	e := env{stdout: os.Stdout, stderr: os.Stderr,
		runner: update.ExecRunner{Stdout: io.Discard, Stderr: os.Stderr}}
	os.Exit(run(context.Background(), os.Args[1:], e))
}

func run(ctx context.Context, args []string, e env) int {
	if len(args) == 1 && args[0] == dispatch.MetadataFlag {
		if err := json.NewEncoder(e.stdout).Encode(routes); err != nil {
			return 1
		}
		return 0
	}
	if len(args) == 0 {
		out, err := dns.Status(ctx, e.runner)
		if err != nil {
			return report(e, err)
		}
		fmt.Fprint(e.stdout, out)
		return 0
	}
	if args[0] != "set" {
		fmt.Fprintf(e.stderr, "subcult dns: unknown command %q\n", args[0])
		return 2
	}
	if len(args) < 2 {
		fmt.Fprintln(e.stderr, "Usage: subcult dns set <untrusted|trusted> [--connection <name>] [--dns <addr[#tls-name],...>] [--no-check]")
		return 2
	}
	mode, err := dns.ParseMode(args[1])
	if err != nil {
		return report(e, err)
	}
	fs := flag.NewFlagSet("subcult dns set", flag.ContinueOnError)
	fs.SetOutput(e.stderr)
	conn := fs.String("connection", "", "connection to change (default: every active Wi-Fi and Ethernet connection)")
	servers := fs.String("dns", "", "DNS servers for a trusted connection, as addr or addr#tls-name, comma separated")
	noCheck := fs.Bool("no-check", false, "do not look up a name after the switch")
	if err := fs.Parse(args[2:]); err != nil {
		return 2
	}
	if fs.NArg() > 0 {
		fmt.Fprintf(e.stderr, "subcult dns: unexpected argument %q\n", fs.Arg(0))
		return 2
	}
	var names, list []string
	if *servers != "" {
		list = strings.Split(*servers, ",")
	}
	if _, err := dns.Target(mode, list); err != nil {
		return report(e, err)
	}
	if *conn != "" {
		names = []string{*conn}
	} else if names, err = dns.Active(ctx, e.runner); err != nil {
		return report(e, err)
	}
	if err := dns.Switch(ctx, e.runner, names, mode, list, !*noCheck); err != nil {
		return report(e, err)
	}
	fmt.Fprintf(e.stdout, "DNS: %s for %s\n", mode, strings.Join(names, ", "))
	return 0
}

func report(e env, err error) int {
	fmt.Fprintf(e.stderr, "subcult dns: %v\n", err)
	if errors.Is(err, dns.ErrInvalid) {
		return 2
	}
	return 1
}
