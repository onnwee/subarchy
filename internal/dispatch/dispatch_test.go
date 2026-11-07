package dispatch

import (
	"bytes"
	"encoding/json"
	"os"
	"path/filepath"
	"reflect"
	"strings"
	"testing"
)

func writeCmd(t *testing.T, dir, name, body string, mode os.FileMode) {
	t.Helper()
	if err := os.WriteFile(filepath.Join(dir, name), []byte(body), mode); err != nil {
		t.Fatal(err)
	}
}

// fixture builds two PATH directories with a shadowed command.
func fixture(t *testing.T) []string {
	t.Helper()
	a, b := t.TempDir(), t.TempDir()
	writeCmd(t, a, "subcult-theme-set", "#!/bin/bash\n# subcult:summary=Apply a theme\n# subcult:args=<theme-id>\n# subcult:examples=subcult theme set subcult-minimal | subcult theme list\necho\n", 0o755)
	writeCmd(t, a, "subcult-theme-list", "#!/bin/bash\n# subcult:summary=List themes\n", 0o755)
	writeCmd(t, a, "subcult-update", "#!/bin/bash\n# subcult:summary=Update the system\n# subcult:requires-sudo=true\n", 0o755)
	writeCmd(t, a, "subcult-debug-dump", "#!/bin/bash\n# subcult:summary=Internal dump\n# subcult:hidden=true\n", 0o755)
	writeCmd(t, a, "subcult-not-executable", "#!/bin/bash\n", 0o644)
	writeCmd(t, a, "other-tool", "#!/bin/bash\n", 0o755)
	writeCmd(t, b, "subcult-theme-set", "#!/bin/bash\n# subcult:summary=Shadowed\n", 0o755)
	writeCmd(t, b, "subcult-factory-reset", "#!/bin/bash\n# subcult:summary=Reset to the installed state\n# subcult:dangerous=true\n", 0o755)
	return []string{a, "", filepath.Join(a, "missing"), b}
}

func TestParseMetadata(t *testing.T) {
	tests := []struct {
		name string
		in   string
		want Metadata
	}{
		{"full header", "#!/bin/bash\n# subcult:summary=Apply a theme\n# subcult:args=<id>\n# subcult:examples=a | b |\n# subcult:hidden=true\n# subcult:requires-sudo=true\n# subcult:dangerous=true\n",
			Metadata{Summary: "Apply a theme", Args: "<id>", Examples: []string{"a", "b"}, Hidden: true, RequiresSudo: true, Dangerous: true}},
		{"blank lines and other comments", "#!/bin/bash\n\n# set -e explanation\n# subcult:summary=Ok\n", Metadata{Summary: "Ok"}},
		{"stops at first code line", "#!/bin/bash\nset -e\n# subcult:summary=Too late\n", Metadata{}},
		{"malformed key ignored", "# subcult:summary\n# subcult:args=x\n", Metadata{Args: "x"}},
		{"binary", "\x7fELF\x00\x00# subcult:summary=no", Metadata{}},
		{"empty", "", Metadata{}},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got, err := ParseMetadata(strings.NewReader(tt.in))
			if err != nil {
				t.Fatal(err)
			}
			if !reflect.DeepEqual(got, tt.want) {
				t.Fatalf("got %+v, want %+v", got, tt.want)
			}
		})
	}
}

func TestDiscoverAndResolve(t *testing.T) {
	reg, err := Discover(fixture(t))
	if err != nil {
		t.Fatal(err)
	}
	if got := len(reg.Commands(true)); got != 5 {
		t.Fatalf("all commands = %d, want 5", got)
	}
	if got := len(reg.Commands(false)); got != 4 {
		t.Fatalf("visible commands = %d, want 4", got)
	}
	tests := []struct {
		args     []string
		binary   string
		rest     []string
		resolved bool
	}{
		{[]string{"theme", "set", "subcult-minimal"}, "subcult-theme-set", []string{"subcult-minimal"}, true},
		{[]string{"theme", "set"}, "subcult-theme-set", []string{}, true},
		{[]string{"update", "--dry-run"}, "subcult-update", []string{"--dry-run"}, true},
		{[]string{"factory", "reset"}, "subcult-factory-reset", []string{}, true},
		{[]string{"theme"}, "", nil, false},
		{[]string{"nope", "x"}, "", nil, false},
	}
	for _, tt := range tests {
		t.Run(strings.Join(tt.args, " "), func(t *testing.T) {
			c, rest, ok := reg.Resolve(tt.args)
			if ok != tt.resolved {
				t.Fatalf("resolved = %v, want %v", ok, tt.resolved)
			}
			if !ok {
				return
			}
			if c.Binary != tt.binary || !reflect.DeepEqual(rest, tt.rest) {
				t.Fatalf("got %s %v, want %s %v", c.Binary, rest, tt.binary, tt.rest)
			}
		})
	}
	c, _, _ := reg.Resolve([]string{"theme", "set"})
	if c.Summary != "Apply a theme" {
		t.Fatalf("earlier PATH entry should win, got summary %q", c.Summary)
	}
}

func run(t *testing.T, args ...string) (int, string, string, []string) {
	t.Helper()
	reg, err := Discover(fixture(t))
	if err != nil {
		t.Fatal(err)
	}
	var out, errb bytes.Buffer
	var execd []string
	app := &App{Registry: reg, Stdout: &out, Stderr: &errb, Exec: func(path string, argv []string) error {
		execd = append([]string{path}, argv...)
		return nil
	}}
	return app.Run(args), out.String(), errb.String(), execd
}

func TestRun(t *testing.T) {
	tests := []struct {
		name      string
		args      []string
		code      int
		stdout    string
		stderr    string
		execArgv0 string
	}{
		{"usage lists groups", nil, 0, "theme\t", "", ""},
		{"version", []string{"--version"}, 0, "subcult 0.0.0", "", ""},
		{"exec with args", []string{"theme", "set", "x"}, 0, "", "", "subcult-theme-set"},
		{"group help", []string{"theme"}, 0, "subcult theme list", "", ""},
		{"help keyword", []string{"help", "theme"}, 0, "subcult theme set", "", ""},
		{"command help", []string{"theme", "set", "--help"}, 0, "Examples:", "", ""},
		{"sudo note", []string{"help", "update"}, 0, "administrator", "", ""},
		{"unknown suggests", []string{"thme", "st"}, 127, "", "Did you mean", ""},
		{"bad flag", []string{"commands", "--nope"}, 2, "", "unknown flag", ""},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			code, out, errs, execd := run(t, tt.args...)
			if code != tt.code {
				t.Fatalf("code = %d, want %d (stderr %q)", code, tt.code, errs)
			}
			if tt.stdout != "" && !strings.Contains(strings.ReplaceAll(out, "  ", "\t"), tt.stdout) && !strings.Contains(out, tt.stdout) {
				t.Fatalf("stdout %q missing %q", out, tt.stdout)
			}
			if tt.stderr != "" && !strings.Contains(errs, tt.stderr) {
				t.Fatalf("stderr %q missing %q", errs, tt.stderr)
			}
			if tt.execArgv0 != "" && (len(execd) < 2 || execd[1] != tt.execArgv0) {
				t.Fatalf("exec = %v, want argv0 %s", execd, tt.execArgv0)
			}
		})
	}
}

func TestCommandsJSON(t *testing.T) {
	for _, all := range []bool{false, true} {
		args := []string{"commands", "--json"}
		want := 4
		if all {
			args = append(args, "--all")
			want = 5
		}
		code, out, _, _ := run(t, args...)
		if code != 0 {
			t.Fatalf("code %d", code)
		}
		var doc struct {
			OK       bool      `json:"ok"`
			Commands []Command `json:"commands"`
		}
		if err := json.Unmarshal([]byte(out), &doc); err != nil {
			t.Fatal(err)
		}
		if !doc.OK || len(doc.Commands) != want {
			t.Fatalf("all=%v: ok=%v n=%d, want %d", all, doc.OK, len(doc.Commands), want)
		}
		if doc.Commands[0].Route == "" || doc.Commands[0].Binary == "" {
			t.Fatalf("missing fields: %+v", doc.Commands[0])
		}
	}
}

func TestLevenshtein(t *testing.T) {
	for _, tt := range []struct {
		a, b string
		want int
	}{{"", "", 0}, {"theme", "theme", 0}, {"thme", "theme", 1}, {"kitten", "sitting", 3}} {
		if got := levenshtein(tt.a, tt.b); got != tt.want {
			t.Fatalf("levenshtein(%q,%q)=%d want %d", tt.a, tt.b, got, tt.want)
		}
	}
}

func FuzzParseMetadata(f *testing.F) {
	f.Add("#!/bin/bash\n# subcult:summary=x\n")
	f.Fuzz(func(t *testing.T, s string) {
		if _, err := ParseMetadata(strings.NewReader(s)); err != nil {
			t.Skip()
		}
	})
}
