package main

import (
	"bytes"
	"context"
	"os"
	"path/filepath"
	"strings"
	"testing"

	"git.subcult.tv/subculture-collective/subarchy/internal/cursor/cursortest"
)

type noRunner struct{ calls int }

func (r *noRunner) Run(context.Context, ...string) error {
	r.calls++
	return nil
}
func (r *noRunner) Output(context.Context, ...string) (string, error) { return "", nil }
func (r *noRunner) Has(string) bool                                   { return false }

func testEnv(t *testing.T, userPalette string) (env, *bytes.Buffer) {
	t.Helper()
	root, err := filepath.Abs("../..")
	if err != nil {
		t.Fatal(err)
	}
	home := t.TempDir()
	if userPalette != "" {
		p := filepath.Join(home, ".config", "subcult", "theme", "palette.json")
		os.MkdirAll(filepath.Dir(p), 0o755)
		os.WriteFile(p, []byte(userPalette), 0o644)
	}
	var errb bytes.Buffer
	return env{home: home, system: root, runner: &noRunner{},
		stdout: &bytes.Buffer{}, stderr: &errb}, &errb
}

// systemTree lays out $SUBCULT_PATH/default/theme/palette.json from the repo.
func systemTree(t *testing.T, e *env) {
	t.Helper()
	data, err := os.ReadFile("../../default/theme/palette.json")
	if err != nil {
		t.Fatal(err)
	}
	e.system = t.TempDir()
	p := filepath.Join(e.system, "default", "theme", "palette.json")
	os.MkdirAll(filepath.Dir(p), 0o755)
	os.WriteFile(p, data, 0o644)
}

func TestBrokenUserPaletteFallsBackToSystem(t *testing.T) {
	for name, content := range map[string]string{
		"bad JSON":     `{"colors": `,
		"bad role":     `{"colors": {"foo": "oops"}}`,
		"missing role": `{"colors": {"green": "#00FF88"}}`,
	} {
		t.Run(name, func(t *testing.T) {
			e, errb := testEnv(t, content)
			systemTree(t, &e)
			// A role the palette lacks is refused (exit 2) only after the
			// palette loaded; a palette that failed to load would exit 1.
			if code := run(context.Background(), []string{"set", "--role", "nonsense"}, e); code != 2 {
				t.Fatalf("exit %d, want 2; stderr: %s", code, errb)
			}
			if name != "missing role" && !strings.Contains(errb.String(), "palette") && !strings.Contains(errb.String(), "#RRGGBB") {
				t.Errorf("want a warning about the user palette, got %q", errb)
			}
		})
	}
}

func TestSetRejectsBadSize(t *testing.T) {
	e, _ := testEnv(t, "")
	systemTree(t, &e)
	if code := run(context.Background(), []string{"set", "--size", "30"}, e); code != 2 {
		t.Fatalf("exit %d, want 2", code)
	}
	if _, err := os.Stat(filepath.Join(e.home, ".config", "subcult", "cursor.json")); !os.IsNotExist(err) {
		t.Error("cursor.json written after a refused set")
	}
}

func TestApplyUsesTheDefaultSizeForASavedSizeThatIsNotOffered(t *testing.T) {
	e, errb := testEnv(t, "")
	e.runner = &cursortest.Tools{}
	out := e.stdout.(*bytes.Buffer)
	settings := filepath.Join(e.home, ".config", "subcult", "cursor.json")
	os.MkdirAll(filepath.Dir(settings), 0o755)
	os.WriteFile(settings, []byte(`{"role": "lavender", "size": 30}`), 0o644)
	if code := run(context.Background(), []string{"apply"}, e); code != 0 {
		t.Fatalf("exit %d, want 0; stderr: %s", code, errb)
	}
	if !strings.Contains(out.String(), "at 24 px") {
		t.Errorf("want the default size, got %q", out)
	}
	if !strings.Contains(errb.String(), "size 30") {
		t.Errorf("want a warning naming the bad size, got %q", errb)
	}
}
