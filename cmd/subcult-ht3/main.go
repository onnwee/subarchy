// Command subcult-ht3 serves `subcult ht3 ...` (issue #65): the battery and
// noise mode of TOZO HT3 headphones, read over their Bluetooth control
// channel. `ht3 status` reads once and prints; `ht3 watch` is the HT3
// panel's helper: it prints one JSON line per change and holds the channel
// until the panel closes and stops it. Neither changes a setting.
package main

import (
	"encoding/json"
	"flag"
	"fmt"
	"io"
	"os"
	"time"

	"git.subcult.tv/subculture-collective/subarchy/internal/dispatch"
	"git.subcult.tv/subculture-collective/subarchy/internal/ht3"
)

var routes = []dispatch.Described{
	{Words: []string{"ht3", "status"}, Metadata: dispatch.Metadata{
		Summary: "Show a connected TOZO HT3's battery and noise mode", Args: "<address> [--json]",
		Examples: []string{"subcult ht3 status AA:BB:CC:DD:EE:FF"}}},
	{Words: []string{"ht3", "watch"}, Metadata: dispatch.Metadata{
		Summary: "Print a TOZO HT3's battery and noise mode as JSON lines while it stays connected (the HT3 panel's helper)",
		Args:    "<address>", Hidden: true,
		Examples: []string{"subcult ht3 watch AA:BB:CC:DD:EE:FF"}}},
}

const (
	dialTimeout = 10 * time.Second
	replyWait   = 2 * time.Second
	tries       = 3
	// refreshEvery is how often watch asks again while the panel is open,
	// as the owner's plugin refreshes its popup.
	refreshEvery = 30 * time.Second
)

// dial opens the control channel; tests replace it.
var dial = func(address string) (ht3.Conn, io.Closer, error) {
	f, err := ht3.Dial(address, dialTimeout)
	if err != nil {
		return nil, nil, err
	}
	return f, f, nil
}

// line is one line of `watch` output.
type line struct {
	Event   string `json:"event"`
	Battery *int   `json:"battery,omitempty"`
	Mode    string `json:"mode,omitempty"`
	Message string `json:"message,omitempty"`
}

func stateLine(s ht3.State) line {
	l := line{Event: "state"}
	if s.Battery >= 0 {
		b := s.Battery
		l.Battery = &b
	}
	if s.Mode >= 0 {
		l.Mode = ht3.ModeName(s.Mode)
	}
	return l
}

func run(args []string, stdout, stderr io.Writer) int {
	if len(args) == 1 && args[0] == dispatch.MetadataFlag {
		if err := json.NewEncoder(stdout).Encode(routes); err != nil {
			return 1
		}
		return 0
	}
	if len(args) == 0 || (args[0] != "status" && args[0] != "watch") {
		fmt.Fprintln(stderr, "Usage: subcult ht3 status <address> [--json] | watch <address>")
		return 2
	}
	fs := flag.NewFlagSet("subcult ht3 "+args[0], flag.ContinueOnError)
	fs.SetOutput(stderr)
	asJSON := fs.Bool("json", false, "machine-readable output (status)")
	// Accept the address before or after the flags.
	rest := args[1:]
	var address string
	if len(rest) > 0 && rest[0] != "" && rest[0][0] != '-' {
		address, rest = rest[0], rest[1:]
	}
	if err := fs.Parse(rest); err != nil {
		return 2
	}
	if address == "" && fs.NArg() == 1 {
		address = fs.Arg(0)
	} else if fs.NArg() != 0 || address == "" {
		fmt.Fprintf(stderr, "Usage: subcult ht3 %s <address>\n", args[0])
		return 2
	}
	if _, err := ht3.ParseAddress(address); err != nil {
		fmt.Fprintf(stderr, "subcult ht3: %v\n", err)
		return 2
	}
	if args[0] == "watch" {
		return watch(address, stdout)
	}
	return status(address, *asJSON, stdout, stderr)
}

func status(address string, asJSON bool, stdout, stderr io.Writer) int {
	conn, closer, err := dial(address)
	if err != nil {
		fmt.Fprintf(stderr, "subcult ht3: %s\n", ht3.Explain(err))
		return 1
	}
	defer closer.Close()
	s := ht3.NewSession(conn)
	if err := s.Query(replyWait, tries, func(ht3.State) error { return nil }); err != nil {
		fmt.Fprintf(stderr, "subcult ht3: %s\n", ht3.Explain(err))
		return 1
	}
	if asJSON {
		if err := json.NewEncoder(stdout).Encode(stateLine(s.State)); err != nil {
			return 1
		}
		return 0
	}
	fmt.Fprintf(stdout, "Battery  %d %%\nMode     %s\n", s.State.Battery, ht3.ModeName(s.State.Mode))
	return 0
}

// watch runs until the channel fails or the panel stops it (SIGTERM). A
// failure is the last line, an error event, and exit 1.
func watch(address string, stdout io.Writer) int {
	enc := json.NewEncoder(stdout)
	fail := func(err error) int {
		_ = enc.Encode(line{Event: "error", Message: ht3.Explain(err)})
		return 1
	}
	conn, closer, err := dial(address)
	if err != nil {
		return fail(err)
	}
	defer closer.Close()
	if err := enc.Encode(line{Event: "connected"}); err != nil {
		return 1
	}
	s := ht3.NewSession(conn)
	changed := func(st ht3.State) error { return enc.Encode(stateLine(st)) }
	if err := s.Query(replyWait, tries, changed); err != nil {
		return fail(err)
	}
	return fail(s.Follow(refreshEvery, changed))
}

func main() {
	os.Exit(run(os.Args[1:], os.Stdout, os.Stderr))
}
