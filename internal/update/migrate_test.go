package update

import (
	"bytes"
	"context"
	"os"
	"path/filepath"
	"slices"
	"testing"
)

func migrations(t *testing.T, names ...string) Migrations {
	t.Helper()
	m := Migrations{Dir: t.TempDir(), StateDir: filepath.Join(t.TempDir(), "state")}
	for _, n := range names {
		if err := os.WriteFile(filepath.Join(m.Dir, n), []byte("true\n"), 0o644); err != nil {
			t.Fatal(err)
		}
	}
	return m
}

func TestPendingOrderAndFilter(t *testing.T) {
	m := migrations(t, "1790000002.sh", "1790000001.sh", "notes.txt", "12.sh", "17900000010.sh")
	got, err := m.Pending()
	if err != nil {
		t.Fatal(err)
	}
	want := []string{"1790000001.sh", "1790000002.sh", "17900000010.sh"}
	if !slices.Equal(got, want) {
		t.Errorf("pending = %q, want %q", got, want)
	}
	if got, err := (Migrations{Dir: filepath.Join(t.TempDir(), "none")}).Pending(); err != nil || got != nil {
		t.Errorf("missing dir: %q, %v", got, err)
	}
}

func TestRunMarksAndStopsOnFailure(t *testing.T) {
	m := migrations(t, "1790000001.sh", "1790000002.sh", "1790000003.sh")
	f := &fake{fail: map[string]bool{"bash -euo pipefail " + filepath.Join(m.Dir, "1790000002.sh"): true}}
	ran, err := m.Run(context.Background(), f)
	if err == nil {
		t.Fatal("want error from the failing migration")
	}
	if !slices.Equal(ran, []string{"1790000001.sh"}) {
		t.Errorf("ran = %q", ran)
	}
	pending, _ := m.Pending()
	if !slices.Equal(pending, []string{"1790000002.sh", "1790000003.sh"}) {
		t.Errorf("pending after failure = %q", pending)
	}
	delete(f.fail, "bash -euo pipefail "+filepath.Join(m.Dir, "1790000002.sh"))
	if ran, err := m.Run(context.Background(), f); err != nil || len(ran) != 2 {
		t.Errorf("rerun: %q, %v", ran, err)
	}
	if pending, _ := m.Pending(); len(pending) != 0 {
		t.Errorf("still pending: %q", pending)
	}
}

func TestDryRunDoesNotMark(t *testing.T) {
	m := migrations(t, "1790000001.sh")
	d := DryRunner{Runner: &fake{}, Out: &bytes.Buffer{}}
	if _, err := m.Run(context.Background(), d); err != nil {
		t.Fatal(err)
	}
	if pending, _ := m.Pending(); len(pending) != 1 {
		t.Errorf("dry run marked migrations: pending = %q", pending)
	}
}

func TestMarkAll(t *testing.T) {
	m := migrations(t, "1790000001.sh", "1790000002.sh")
	if err := m.MarkAll(); err != nil {
		t.Fatal(err)
	}
	if pending, _ := m.Pending(); len(pending) != 0 {
		t.Errorf("pending = %q", pending)
	}
}

// TestRealMigration runs a script through ExecRunner end to end.
func TestRealMigration(t *testing.T) {
	m := migrations(t)
	out := filepath.Join(t.TempDir(), "touched")
	script := "touch " + out + "\n"
	if err := os.WriteFile(filepath.Join(m.Dir, "1790000001.sh"), []byte(script), 0o644); err != nil {
		t.Fatal(err)
	}
	r := ExecRunner{Stdout: &bytes.Buffer{}, Stderr: &bytes.Buffer{}}
	if _, err := m.Run(context.Background(), r); err != nil {
		t.Fatal(err)
	}
	if _, err := os.Stat(out); err != nil {
		t.Errorf("migration did not run: %v", err)
	}
}
