package main

import (
	"bytes"
	"context"
	"encoding/json"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"

	"git.subcult.tv/subculture-collective/subarchy/internal/dispatch"
	"git.subcult.tv/subculture-collective/subarchy/internal/update"
)

// fakeRunner answers queries; err is returned from Output when set.
type fakeRunner struct {
	tools map[string]bool
	out   string
	err   error
	ran   []string
}

func (f *fakeRunner) Run(_ context.Context, argv ...string) error {
	f.ran = append(f.ran, strings.Join(argv, " "))
	return nil
}
func (f *fakeRunner) Output(context.Context, ...string) (string, error) { return f.out, f.err }
func (f *fakeRunner) Has(name string) bool                              { return f.tools[name] }

func newApp(t *testing.T, r update.Runner, scripts ...string) (*app, *bytes.Buffer, *bytes.Buffer) {
	t.Helper()
	m := update.Migrations{Dir: t.TempDir(), StateDir: filepath.Join(t.TempDir(), "state")}
	for _, s := range scripts {
		if err := os.WriteFile(filepath.Join(m.Dir, s), []byte("true\n"), 0o644); err != nil {
			t.Fatal(err)
		}
	}
	out, errOut := &bytes.Buffer{}, &bytes.Buffer{}
	state := filepath.Join(t.TempDir(), "state")
	return &app{
		stdin: strings.NewReader(""), stdout: out, stderr: errOut, runner: r,
		migrations: func() (update.Migrations, error) { return m, nil },
		euid:       1000,
		stateDir:   func() (string, error) { return state, nil },
	}, out, errOut
}

func TestMetadata(t *testing.T) {
	a, out, _ := newApp(t, &fakeRunner{})
	if code := a.main(context.Background(), []string{dispatch.MetadataFlag}); code != 0 {
		t.Fatalf("exit %d", code)
	}
	var got []dispatch.Described
	if err := json.Unmarshal(out.Bytes(), &got); err != nil || len(got) != 4 {
		t.Fatalf("metadata %q: %v", out, err)
	}
}

func TestDryRunTouchesNothing(t *testing.T) {
	r := &fakeRunner{tools: map[string]bool{"snapper": true}}
	a, out, errOut := newApp(t, r, "1790000001.sh")
	if code := a.main(context.Background(), []string{"--dry-run"}); code != 0 {
		t.Fatalf("exit %d: %s", code, errOut)
	}
	if len(r.ran) != 0 {
		t.Errorf("dry run ran %q", r.ran)
	}
	for _, want := range []string{"would run: sudo /usr/bin/subcult-update privileged upgrade", "would run: bash -euo pipefail"} {
		if !strings.Contains(out.String(), want) {
			t.Errorf("output lacks %q:\n%s", want, out)
		}
	}
	if strings.Contains(out.String(), "taking a snapshot") {
		t.Error("dry run should not snapshot")
	}
}

func TestUpdateYes(t *testing.T) {
	r := &fakeRunner{}
	a, out, errOut := newApp(t, r)
	if code := a.main(context.Background(), []string{"--yes", "--no-snapshot"}); code != 0 {
		t.Fatalf("exit %d: %s", code, errOut)
	}
	if len(r.ran) == 0 || r.ran[0] != "sudo /usr/bin/subcult-update privileged upgrade --noconfirm" {
		t.Errorf("ran %q", r.ran)
	}
	if !strings.Contains(out.String(), "reboot") {
		t.Errorf("no report:\n%s", out)
	}
}

func TestCheck(t *testing.T) {
	noUpdates := exec.Command("sh", "-c", "exit 2").Run()
	tests := []struct {
		name string
		r    *fakeRunner
		args []string
		code int
		out  string
	}{
		{"two updates", &fakeRunner{tools: map[string]bool{"checkupdates": true}, out: "a 1 -> 2\nb 3 -> 4\n"}, nil, 0, "2 updates"},
		{"quiet", &fakeRunner{tools: map[string]bool{"checkupdates": true}, out: "a 1 -> 2\n"}, []string{"-q"}, 0, "1\n"},
		{"none", &fakeRunner{tools: map[string]bool{"checkupdates": true}, err: noUpdates}, nil, 2, "0 updates"},
		{"missing tool", &fakeRunner{}, nil, 1, ""},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			a, out, _ := newApp(t, tt.r)
			if code := a.main(context.Background(), append([]string{"check"}, tt.args...)); code != tt.code {
				t.Fatalf("exit %d, want %d", code, tt.code)
			}
			if !strings.Contains(out.String(), tt.out) {
				t.Errorf("out = %q, want %q", out, tt.out)
			}
		})
	}
}

func TestMigrate(t *testing.T) {
	r := &fakeRunner{}
	a, out, _ := newApp(t, r, "1790000001.sh")
	if code := a.main(context.Background(), []string{"migrate", "--pending"}); code != 0 || out.String() != "1790000001.sh\n" {
		t.Fatalf("pending: exit %d, %q", code, out)
	}
	out.Reset()
	if code := a.main(context.Background(), []string{"migrate"}); code != 0 || !strings.Contains(out.String(), "ran 1790000001.sh") {
		t.Fatalf("run: exit %d, %q", code, out)
	}
	if code := a.main(context.Background(), []string{"migrate", "--pending"}); code != 1 {
		t.Errorf("nothing pending should exit 1, got %d", code)
	}
	a2, _, _ := newApp(t, r, "1790000002.sh")
	if code := a2.main(context.Background(), []string{"migrate", "--mark-all"}); code != 0 {
		t.Errorf("mark-all exit %d", code)
	}
	if code := a2.main(context.Background(), []string{"migrate", "--pending", "--mark-all"}); code != 2 {
		t.Errorf("exclusive flags exit %d", code)
	}
}

func TestUsageErrors(t *testing.T) {
	for _, args := range [][]string{{"frob"}, {"--bogus"}, {"check", "--yes"}} {
		a, _, errOut := newApp(t, &fakeRunner{})
		if code := a.main(context.Background(), args); code != 2 || !strings.Contains(errOut.String(), "unknown") {
			t.Errorf("%q: exit %d, %q", args, code, errOut)
		}
	}
	a, out, _ := newApp(t, &fakeRunner{})
	if code := a.main(context.Background(), []string{"--help"}); code != 0 || !strings.Contains(out.String(), "subcult update check") {
		t.Errorf("help: %d %q", code, out)
	}
}

func TestPrivileged(t *testing.T) {
	r := &fakeRunner{out: "12\n"}
	a, out, errOut := newApp(t, r)
	if code := a.main(context.Background(), []string{"privileged", "upgrade"}); code != 1 || !strings.Contains(errOut.String(), "as root") {
		t.Fatalf("non-root: exit %d, %q", code, errOut)
	}
	a.euid = 0
	for _, tt := range []struct {
		args []string
		ran  string
	}{
		{[]string{"privileged", "upgrade", "--noconfirm"}, "pacman -Syu --noconfirm"},
		{[]string{"privileged", "prune"}, "paccache -rk2"},
	} {
		r.ran = nil
		if code := a.main(context.Background(), tt.args); code != 0 || len(r.ran) != 1 || r.ran[0] != tt.ran {
			t.Errorf("%q: exit %d, ran %q", tt.args, code, r.ran)
		}
	}
	if code := a.main(context.Background(), []string{"privileged", "snapshot"}); code != 0 || out.String() != "12\n" {
		t.Errorf("snapshot: exit %d, out %q", code, out)
	}
	// The services step scans /proc itself (as root) and runs no command.
	a.procDir = t.TempDir()
	r.ran = nil
	out.Reset()
	if code := a.main(context.Background(), []string{"privileged", "services"}); code != 0 || len(r.ran) != 0 || out.String() != "" {
		t.Errorf("services: exit %d, ran %q, out %q", code, r.ran, out)
	}
	for _, bad := range [][]string{{"privileged", "upgrade", "--overwrite=*"}, {"privileged"}, {"privileged", "rm"}} {
		if code := a.main(context.Background(), bad); code != 2 {
			t.Errorf("%q accepted: exit %d", bad, code)
		}
	}
}

func TestCheckState(t *testing.T) {
	r := &fakeRunner{tools: map[string]bool{"checkupdates": true}, out: "a 1 -> 2\nb 1 -> 2\nc 1 -> 2\n"}
	a, _, _ := newApp(t, r)
	if code := a.main(context.Background(), []string{"check", "--state", "-q"}); code != 0 {
		t.Fatalf("exit %d", code)
	}
	dir, _ := a.stateDir()
	got, err := os.ReadFile(filepath.Join(dir, "update-count"))
	if err != nil || string(got) != "3\n" {
		t.Errorf("state = %q, %v", got, err)
	}
	none := &fakeRunner{tools: map[string]bool{"checkupdates": true}, err: exec.Command("sh", "-c", "exit 2").Run()}
	a.runner = none
	if code := a.main(context.Background(), []string{"check", "--state"}); code != 2 {
		t.Fatalf("none: exit %d", code)
	}
	if got, _ := os.ReadFile(filepath.Join(dir, "update-count")); string(got) != "0\n" {
		t.Errorf("state after none = %q", got)
	}
}
