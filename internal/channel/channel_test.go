package channel

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func root(t *testing.T, snapshot string) string {
	t.Helper()
	r := t.TempDir()
	for p, c := range map[string]string{
		SnapshotPath: snapshot + "\n",
		PacmanConf: "[options]\nHoldPkg = pacman glibc\n\n[core]\nInclude = /etc/pacman.d/mirrorlist\n\n[extra]\nInclude = /etc/pacman.d/mirrorlist\n\n" +
			"#[multilib]\n#Include = /etc/pacman.d/mirrorlist\n",
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

func read(t *testing.T, path string) string {
	t.Helper()
	b, err := os.ReadFile(path)
	if err != nil {
		t.Fatal(err)
	}
	return string(b)
}

func TestSetStableThenEdgeAndBack(t *testing.T) {
	r := root(t, "2026/11/08")
	if st, err := Current(r); err != nil || st.Channel != "" || !strings.HasPrefix(st.String(), "unset") {
		t.Fatalf("fresh root: %+v %v", st, err)
	}
	if w, err := Set(r, Stable); err != nil || w != "" {
		t.Fatalf("set stable: %q %v", w, err)
	}
	ml := read(t, filepath.Join(r, MirrorlistPath))
	if !strings.Contains(ml, "Server = https://archive.archlinux.org/repos/2026/11/08/$repo/os/$arch\n") {
		t.Errorf("stable mirrorlist:\n%s", ml)
	}
	if !strings.Contains(read(t, filepath.Join(r, RepoPath)), "arch/stable/$arch") {
		t.Error("stable repo server")
	}
	conf := read(t, filepath.Join(r, PacmanConf))
	if strings.Count(conf, "Include = /etc/pacman.d/subcult-mirrorlist") != 2 || !strings.Contains(conf, "#Include = /etc/pacman.d/mirrorlist") {
		t.Errorf("pacman.conf includes:\n%s", conf)
	}
	st, err := Current(r)
	if err != nil || st.Channel != Stable || st.Snapshot != "2026/11/08" || st.String() != "stable (snapshot 2026/11/08)" {
		t.Errorf("current: %+v %v", st, err)
	}

	if w, err := Set(r, Edge); err != nil || w != "" {
		t.Fatalf("set edge: %q %v", w, err)
	}
	if !strings.Contains(read(t, filepath.Join(r, MirrorlistPath)), "Include = /etc/pacman.d/mirrorlist\n") {
		t.Error("edge mirrorlist does not include Arch's")
	}
	if st, _ := Current(r); st.Channel != Edge || !strings.HasPrefix(st.String(), "edge") {
		t.Errorf("current after edge: %+v", st)
	}
	w, err := Set(r, Stable)
	if err != nil || !strings.Contains(w, "newer than the snapshot") {
		t.Errorf("edge to stable warning: %q %v", w, err)
	}
	if _, err := Set(r, "beta"); err == nil {
		t.Error("an unknown channel was accepted")
	}
}

func TestRefresh(t *testing.T) {
	r := root(t, "2026/11/08")
	if changed, err := Refresh(r); err != nil || changed {
		t.Errorf("refresh unset: %v %v", changed, err)
	}
	if _, err := Set(r, Stable); err != nil {
		t.Fatal(err)
	}
	if changed, err := Refresh(r); err != nil || changed {
		t.Errorf("refresh same date: %v %v", changed, err)
	}
	if err := os.WriteFile(filepath.Join(r, SnapshotPath), []byte("2026/11/20\n"), 0o644); err != nil {
		t.Fatal(err)
	}
	if changed, err := Refresh(r); err != nil || !changed {
		t.Errorf("refresh new date: %v %v", changed, err)
	}
	if st, _ := Current(r); st.Snapshot != "2026/11/20" {
		t.Errorf("date after refresh: %+v", st)
	}
	if _, err := Set(r, Edge); err != nil {
		t.Fatal(err)
	}
	if changed, err := Refresh(r); err != nil || changed {
		t.Errorf("refresh on edge: %v %v", changed, err)
	}
}

func TestSnapshotValidation(t *testing.T) {
	r := root(t, "08-11-2026")
	if _, err := Snapshot(r); err == nil {
		t.Error("a date that is not YYYY/MM/DD passed")
	}
	if _, err := Set(r, Stable); err == nil {
		t.Error("stable set with a bad snapshot date")
	}
	if _, err := Snapshot(t.TempDir()); err == nil {
		t.Error("a missing snapshot file passed")
	}
}

func TestCurrentWithoutHeader(t *testing.T) {
	r := root(t, "2026/11/08")
	p := filepath.Join(r, MirrorlistPath)
	if err := os.MkdirAll(filepath.Dir(p), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(p, []byte("Server = https://example.test/$repo\n"), 0o644); err != nil {
		t.Fatal(err)
	}
	if _, err := Current(r); err == nil {
		t.Error("a mirrorlist without the header passed as a channel")
	}
	if _, err := Set(r, Stable); err != nil {
		t.Errorf("a hand-edited mirrorlist cannot be repaired: %v", err)
	}
	if st, err := Current(r); err != nil || st.Channel != Stable {
		t.Errorf("after the repair: %+v %v", st, err)
	}
}
