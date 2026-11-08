package main

import (
	"bytes"
	"encoding/json"
	"errors"
	"os"
	"path/filepath"
	"strings"
	"testing"

	"git.subcult.tv/subculture-collective/subarchy/internal/channel"
	"git.subcult.tv/subculture-collective/subarchy/internal/dispatch"
)

func root(t *testing.T) string {
	t.Helper()
	r := t.TempDir()
	for p, c := range map[string]string{
		channel.SnapshotPath: "2026/11/08\n",
		channel.PacmanConf:   "[core]\nInclude = /etc/pacman.d/mirrorlist\n",
	} {
		full := filepath.Join(r, p)
		if err := os.MkdirAll(filepath.Dir(full), 0o755); err != nil {
			t.Fatal(err)
		}
		if err := os.WriteFile(full, []byte(c), 0o644); err != nil {
			t.Fatal(err)
		}
	}
	return r
}

func newApp() (*app, *bytes.Buffer, *bytes.Buffer) {
	var out, errOut bytes.Buffer
	a := &app{stdout: &out, stderr: &errOut, euid: 1000, sudo: func(args ...string) error { return errors.New("sudo should not run") }}
	return a, &out, &errOut
}

func TestShowSetRefresh(t *testing.T) {
	r := root(t)
	a, out, errOut := newApp()
	if code := a.run([]string{"--root", r}); code != 0 || !strings.HasPrefix(out.String(), "unset") {
		t.Fatalf("show unset: %d %q", code, out.String())
	}
	out.Reset()
	if code := a.run([]string{"--root", r, "set", "stable"}); code != 0 || strings.TrimSpace(out.String()) != "stable (snapshot 2026/11/08)" {
		t.Fatalf("set stable: %d %q %s", code, out.String(), errOut.String())
	}
	out.Reset()
	if code := a.run([]string{"--root", r, "--quiet", "set", "edge"}); code != 0 || out.Len() != 0 {
		t.Fatalf("set edge quiet: %d %q", code, out.String())
	}
	errOut.Reset()
	if code := a.run([]string{"--root", r, "set", "stable"}); code != 0 || !strings.Contains(errOut.String(), "newer than the snapshot") {
		t.Fatalf("edge to stable: %d %q", code, errOut.String())
	}
	if code := a.run([]string{"--root", r, "set", "beta"}); code != 2 {
		t.Errorf("unknown channel: %d", code)
	}
	if err := os.WriteFile(filepath.Join(r, channel.SnapshotPath), []byte("2026/12/01\n"), 0o644); err != nil {
		t.Fatal(err)
	}
	out.Reset()
	if code := a.run([]string{"--root", r, "refresh"}); code != 0 || !strings.Contains(out.String(), "moved to stable (snapshot 2026/12/01)") {
		t.Errorf("refresh: %d %q", code, out.String())
	}
}

func TestSudoReexec(t *testing.T) {
	a, _, _ := newApp()
	var got []string
	a.sudo = func(args ...string) error { got = args; return nil }
	if code := a.run([]string{"set", "edge"}); code != 0 || strings.Join(got, " ") != "set edge" {
		t.Errorf("set without root: %d %v", code, got)
	}
	got = nil
	if code := a.run([]string{"refresh", "--quiet"}); code != 0 || strings.Join(got, " ") != "refresh --quiet" {
		t.Errorf("refresh without root: %d %v", code, got)
	}
}

func TestMetadata(t *testing.T) {
	a, out, _ := newApp()
	if code := a.run([]string{dispatch.MetadataFlag}); code != 0 {
		t.Fatal(code)
	}
	var described []dispatch.Described
	if err := json.Unmarshal(out.Bytes(), &described); err != nil || len(described) != 3 || !described[1].Metadata.RequiresSudo {
		t.Errorf("metadata: %s %v", out.String(), err)
	}
}
