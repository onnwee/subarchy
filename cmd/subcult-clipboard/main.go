// Command subcult-clipboard serves `subcult clipboard ...`: the clipboard
// history behind the launcher's "$" prefix and Super+Ctrl+V (ADR 0056,
// 0057). `clipboard watch` (the session service) runs `wl-paste --watch`,
// which starts `clipboard store` on every copy: it reads the offered MIME
// types, skips copies marked secret (and clears them from the clipboard
// after 30 s), and keeps text and PNG images under
// ~/.local/state/subcult/clipboard, newest first and capped. `list`,
// `copy`, `show`, `remove` and `clear` work on that store. Nothing polls:
// wl-paste sleeps on the Wayland socket between copies.
package main

import (
	"bytes"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"syscall"
	"text/tabwriter"
	"time"

	"git.subcult.tv/subculture-collective/subarchy/internal/clipboard"
	"git.subcult.tv/subculture-collective/subarchy/internal/dispatch"
)

var routes = []dispatch.Described{
	{Words: []string{"clipboard", "list"}, Metadata: dispatch.Metadata{
		Summary: "List the clipboard history, newest first", Args: "[--json]",
		Examples: []string{"subcult clipboard list", "subcult clipboard list --json"}}},
	{Words: []string{"clipboard", "copy"}, Metadata: dispatch.Metadata{
		Summary: "Put a history entry back on the clipboard", Args: "<id>",
		Examples: []string{"subcult clipboard copy 3f2a9c1e5b7d0a4c"}}},
	{Words: []string{"clipboard", "show"}, Metadata: dispatch.Metadata{
		Summary: "Print a text entry, or the file holding an image entry", Args: "<id>"}},
	{Words: []string{"clipboard", "remove"}, Metadata: dispatch.Metadata{
		Summary: "Drop one entry from the history", Args: "<id>"}},
	{Words: []string{"clipboard", "clear"}, Metadata: dispatch.Metadata{
		Summary: "Drop the whole clipboard history", Examples: []string{"subcult clipboard clear"}}},
	{Words: []string{"clipboard", "store"}, Metadata: dispatch.Metadata{
		Summary: "Record the current copy (wl-paste --watch runs this)", Hidden: true}},
	{Words: []string{"clipboard", "watch"}, Metadata: dispatch.Metadata{
		Summary: "Record every copy (the session service runs this)", Hidden: true}},
}

type app struct {
	stdout, stderr io.Writer
	dir            string
	now            func() time.Time
	// output runs wl-paste or wl-copy with stdin and returns its stdout.
	output func(argv []string, stdin []byte) ([]byte, error)
	// detach starts a command without waiting (the secret clearer).
	detach func(argv []string) error
	// execve replaces this process (watch).
	execve func(argv []string) error
}

// listed is one entry as `list --json` prints it for the launcher.
type listed struct {
	ID      string `json:"id"`
	Kind    string `json:"kind"`
	Mime    string `json:"mime"`
	Size    int    `json:"size"`
	Time    string `json:"time"`
	Preview string `json:"preview"`
	File    string `json:"file,omitempty"`
}

func (a *app) run(args []string) int {
	if len(args) == 1 && args[0] == dispatch.MetadataFlag {
		if err := json.NewEncoder(a.stdout).Encode(routes); err != nil {
			return 1
		}
		return 0
	}
	if len(args) == 0 || args[0] == "help" || args[0] == "--help" {
		return a.usage()
	}
	switch args[0] {
	case "watch":
		return a.watch()
	case "store":
		return a.store()
	case "list":
		return a.list(len(args) > 1 && args[1] == "--json")
	case "copy", "show", "remove":
		if len(args) != 2 {
			return a.usage()
		}
		return a.one(args[0], args[1])
	case "clear":
		return a.clear()
	}
	return a.usage()
}

func (a *app) usage() int {
	fmt.Fprintln(a.stderr, "Usage: subcult clipboard list [--json] | copy <id> | show <id> | remove <id> | clear")
	return 2
}

func (a *app) fail(err error) int {
	fmt.Fprintln(a.stderr, "subcult clipboard:", err)
	return 1
}

// watch hands the process to wl-paste, which runs `store` on every copy.
func (a *app) watch() int {
	exe, err := os.Executable()
	if err != nil {
		return a.fail(err)
	}
	if err := a.execve([]string{"wl-paste", "--watch", exe, "store"}); err != nil {
		return a.fail(fmt.Errorf("wl-paste: %w", err))
	}
	return 0
}

// store records the current copy, unless it is a secret or nothing worth
// keeping.
func (a *app) store() int {
	raw, err := a.output([]string{"wl-paste", "--list-types"}, nil)
	if err != nil {
		return a.fail(fmt.Errorf("wl-paste --list-types: %w", err))
	}
	types := strings.Split(strings.TrimSpace(string(raw)), "\n")
	if clipboard.Secret(types) {
		// Gone from the clipboard after 30 s, if it is still the secret.
		script := fmt.Sprintf("sleep %d; wl-paste --list-types 2>/dev/null | grep -qx %s && wl-copy --clear",
			int(clipboard.SecretClearAfter.Seconds()), clipboard.SecretType)
		if err := a.detach([]string{"sh", "-c", script}); err != nil {
			return a.fail(err)
		}
		return 0
	}
	kind, mime := clipboard.Pick(types)
	if kind == "" {
		return 0
	}
	data, err := a.output([]string{"wl-paste", "--no-newline", "--type", mime}, nil)
	if err != nil {
		return a.fail(fmt.Errorf("wl-paste --type %s: %w", mime, err))
	}
	var e clipboard.Entry
	switch kind {
	case "text":
		if len(bytes.TrimSpace(data)) == 0 || len(data) > clipboard.MaxText {
			return 0
		}
		e = clipboard.TextEntry(string(data), mime, a.now())
	case "image":
		if len(data) == 0 || len(data) > clipboard.MaxImage {
			return 0
		}
		e = clipboard.ImageEntry(data, mime, a.now())
		if err := os.MkdirAll(a.dir, 0o700); err != nil {
			return a.fail(err)
		}
		if err := os.WriteFile(filepath.Join(a.dir, e.File), data, 0o600); err != nil {
			return a.fail(err)
		}
	}
	s, err := clipboard.Load(a.dir)
	if err != nil {
		return a.fail(err)
	}
	dropped := s.Add(e)
	if err := clipboard.Save(a.dir, s); err != nil {
		return a.fail(err)
	}
	a.unlink(dropped)
	return 0
}

func (a *app) unlink(entries []clipboard.Entry) {
	for _, e := range entries {
		if e.File != "" {
			_ = os.Remove(filepath.Join(a.dir, e.File))
		}
	}
}

func (a *app) list(asJSON bool) int {
	s, err := clipboard.Load(a.dir)
	if err != nil {
		return a.fail(err)
	}
	if asJSON {
		out := make([]listed, 0, len(s.Entries))
		for _, e := range s.Entries {
			l := listed{ID: e.ID, Kind: e.Kind, Mime: e.Mime, Size: e.Size, Time: e.Time.Format(time.RFC3339), Preview: clipboard.Preview(e)}
			if e.File != "" {
				l.File = filepath.Join(a.dir, e.File)
			}
			out = append(out, l)
		}
		enc := json.NewEncoder(a.stdout)
		enc.SetIndent("", "  ")
		if err := enc.Encode(out); err != nil {
			return a.fail(err)
		}
		return 0
	}
	if len(s.Entries) == 0 {
		fmt.Fprintln(a.stdout, "clipboard history is empty")
		return 0
	}
	tw := tabwriter.NewWriter(a.stdout, 0, 4, 2, ' ', 0)
	for _, e := range s.Entries {
		fmt.Fprintf(tw, "%s\t%s\t%s\n", e.ID, e.Time.Local().Format("Jan 2 15:04"), clipboard.Preview(e))
	}
	tw.Flush()
	return 0
}

// one is copy, show or remove for a single entry.
func (a *app) one(verb, id string) int {
	s, err := clipboard.Load(a.dir)
	if err != nil {
		return a.fail(err)
	}
	e, ok := s.Get(id)
	if !ok {
		return a.fail(fmt.Errorf("no entry %s", id))
	}
	switch verb {
	case "show":
		if e.Kind == "image" {
			fmt.Fprintln(a.stdout, filepath.Join(a.dir, e.File))
		} else {
			fmt.Fprint(a.stdout, e.Text)
		}
	case "copy":
		data := []byte(e.Text)
		if e.Kind == "image" {
			if data, err = os.ReadFile(filepath.Join(a.dir, e.File)); err != nil {
				return a.fail(err)
			}
		}
		if _, err := a.output([]string{"wl-copy", "--type", e.Mime}, data); err != nil {
			return a.fail(fmt.Errorf("wl-copy: %w", err))
		}
		// The copy lands first again, with a fresh time.
		e.Time = a.now()
		s.Add(e)
		if err := clipboard.Save(a.dir, s); err != nil {
			return a.fail(err)
		}
	case "remove":
		s.Remove(id)
		if err := clipboard.Save(a.dir, s); err != nil {
			return a.fail(err)
		}
		a.unlink([]clipboard.Entry{e})
	}
	return 0
}

func (a *app) clear() int {
	s, err := clipboard.Load(a.dir)
	if err != nil {
		return a.fail(err)
	}
	all := s.Clear()
	if err := clipboard.Save(a.dir, s); err != nil {
		return a.fail(err)
	}
	a.unlink(all)
	fmt.Fprintf(a.stdout, "dropped %d entries\n", len(all))
	return 0
}

func realOutput(argv []string, stdin []byte) ([]byte, error) {
	cmd := exec.Command(argv[0], argv[1:]...)
	if stdin != nil {
		cmd.Stdin = bytes.NewReader(stdin)
	}
	var stderr bytes.Buffer
	cmd.Stderr = &stderr
	out, err := cmd.Output()
	if err != nil && stderr.Len() > 0 {
		return out, errors.New(strings.TrimSpace(stderr.String()))
	}
	return out, err
}

func realDetach(argv []string) error {
	cmd := exec.Command(argv[0], argv[1:]...)
	cmd.SysProcAttr = &syscall.SysProcAttr{Setsid: true}
	if err := cmd.Start(); err != nil {
		return err
	}
	return cmd.Process.Release()
}

func realExecve(argv []string) error {
	path, err := exec.LookPath(argv[0])
	if err != nil {
		return err
	}
	return syscall.Exec(path, argv, os.Environ())
}

func main() {
	dir, err := clipboard.DefaultDir()
	if err != nil {
		fmt.Fprintln(os.Stderr, "subcult clipboard:", err)
		os.Exit(1)
	}
	a := &app{stdout: os.Stdout, stderr: os.Stderr, dir: dir, now: time.Now, output: realOutput, detach: realDetach, execve: realExecve}
	os.Exit(a.run(os.Args[1:]))
}
