package atomicfile

import (
	"os"
	"path/filepath"
	"sync"
	"testing"
)

func TestWriteCreatesTheFolderAndSetsTheMode(t *testing.T) {
	path := filepath.Join(t.TempDir(), "sub", "history.json")
	if err := Write(path, []byte("one\n"), 0o600); err != nil {
		t.Fatal(err)
	}
	if err := Write(path, []byte("two\n"), 0o600); err != nil {
		t.Fatal(err)
	}
	data, _ := os.ReadFile(path)
	info, err := os.Stat(path)
	if err != nil || string(data) != "two\n" || info.Mode().Perm() != 0o600 {
		t.Errorf("got %q, mode %v, err %v", data, info.Mode().Perm(), err)
	}
	if entries, _ := os.ReadDir(filepath.Dir(path)); len(entries) != 1 {
		t.Errorf("temporary files left behind: %v", entries)
	}
}

func TestWriteKeepsALinkAndReplacesWhatItPointsAt(t *testing.T) {
	dir := t.TempDir()
	target := filepath.Join(dir, "dotfiles", "fonts.conf")
	link := filepath.Join(dir, "config", "fonts.conf")
	for _, d := range []string{filepath.Dir(target), filepath.Dir(link)} {
		if err := os.MkdirAll(d, 0o755); err != nil {
			t.Fatal(err)
		}
	}
	if err := os.WriteFile(target, []byte("old"), 0o644); err != nil {
		t.Fatal(err)
	}
	if err := os.Symlink(target, link); err != nil {
		t.Fatal(err)
	}
	if err := Write(link, []byte("new"), 0o644); err != nil {
		t.Fatal(err)
	}
	if info, err := os.Lstat(link); err != nil || info.Mode()&os.ModeSymlink == 0 {
		t.Errorf("the link was replaced by a file (%v, %v)", info, err)
	}
	if data, _ := os.ReadFile(target); string(data) != "new" {
		t.Errorf("the linked file holds %q", data)
	}
}

func TestWritersAtTheSameTimeLeaveOneWholeFile(t *testing.T) {
	path := filepath.Join(t.TempDir(), "events.json")
	payloads := map[string]bool{}
	var wg sync.WaitGroup
	for i := range 40 {
		// Different lengths: two writers sharing one temporary file would
		// leave a mix of both.
		data := make([]byte, 1000+i*997)
		for j := range data {
			data[j] = byte('a' + i%26)
		}
		payloads[string(data)] = true
		wg.Add(1)
		go func() {
			defer wg.Done()
			if err := Write(path, data, 0o644); err != nil {
				t.Error(err)
			}
		}()
	}
	wg.Wait()
	data, err := os.ReadFile(path)
	if err != nil || !payloads[string(data)] {
		t.Errorf("the file is not one writer's whole content (%d bytes, %v)", len(data), err)
	}
	if entries, _ := os.ReadDir(filepath.Dir(path)); len(entries) != 1 {
		t.Errorf("temporary files left behind: %v", entries)
	}
}
