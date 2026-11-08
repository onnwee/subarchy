package main

import (
	"bytes"
	"encoding/json"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"git.subcult.tv/subculture-collective/subarchy/internal/clipboard"
)

// fake stands in for wl-paste and wl-copy: types and content to offer, and
// the commands seen.
type fake struct {
	types, content string
	calls          []string
	stdin          [][]byte
	detached       []string
}

func (f *fake) output(argv []string, stdin []byte) ([]byte, error) {
	f.calls = append(f.calls, strings.Join(argv, " "))
	f.stdin = append(f.stdin, stdin)
	switch {
	case strings.HasPrefix(strings.Join(argv, " "), "wl-paste --list-types"):
		return []byte(f.types), nil
	case argv[0] == "wl-paste":
		return []byte(f.content), nil
	}
	return nil, nil
}

func (f *fake) detach(argv []string) error {
	f.detached = append(f.detached, strings.Join(argv, " "))
	return nil
}

func newApp(t *testing.T, f *fake) (*app, *bytes.Buffer) {
	t.Helper()
	out := &bytes.Buffer{}
	return &app{stdout: out, stderr: &bytes.Buffer{}, dir: filepath.Join(t.TempDir(), "clipboard"),
		now: func() time.Time { return time.Date(2026, 11, 7, 23, 0, 0, 0, time.UTC) },
		output: f.output, detach: f.detach}, out
}

func entries(t *testing.T, a *app) []clipboard.Entry {
	t.Helper()
	s, err := clipboard.Load(a.dir)
	if err != nil {
		t.Fatal(err)
	}
	return s.Entries
}

func TestStoreText(t *testing.T) {
	f := &fake{types: "text/plain;charset=utf-8\ntext/plain\nTEXT\n", content: "hello world"}
	a, _ := newApp(t, f)
	if code := a.run([]string{"store"}); code != 0 {
		t.Fatalf("exit %d", code)
	}
	es := entries(t, a)
	if len(es) != 1 || es[0].Text != "hello world" || es[0].Mime != "text/plain;charset=utf-8" {
		t.Fatalf("entries %+v", es)
	}
	if want := "wl-paste --no-newline --type text/plain;charset=utf-8"; f.calls[1] != want {
		t.Errorf("fetched with %q", f.calls[1])
	}
	// The same text again moves to the front, no duplicate.
	a.run([]string{"store"})
	f.content = "second"
	a.run([]string{"store"})
	es = entries(t, a)
	if len(es) != 2 || es[0].Text != "second" || es[1].Text != "hello world" {
		t.Errorf("entries %+v", es)
	}
	if len(f.detached) != 0 {
		t.Error("nothing to clear for ordinary text")
	}
}

func TestStoreSecret(t *testing.T) {
	f := &fake{types: "text/plain\n" + clipboard.SecretType + "\n", content: "hunter2"}
	a, _ := newApp(t, f)
	if code := a.run([]string{"store"}); code != 0 {
		t.Fatalf("exit %d", code)
	}
	if len(entries(t, a)) != 0 {
		t.Error("a secret was stored")
	}
	if len(f.calls) != 1 {
		t.Errorf("a secret's content was fetched: %q", f.calls)
	}
	if len(f.detached) != 1 || !strings.Contains(f.detached[0], "sleep 30") || !strings.Contains(f.detached[0], "wl-copy --clear") || !strings.Contains(f.detached[0], clipboard.SecretType) {
		t.Errorf("clearer %q", f.detached)
	}
}

func TestStoreImageAndSkips(t *testing.T) {
	f := &fake{types: "image/png\nimage/jpeg\n", content: "\x89PNG..."}
	a, _ := newApp(t, f)
	a.run([]string{"store"})
	es := entries(t, a)
	if len(es) != 1 || es[0].Kind != "image" {
		t.Fatalf("entries %+v", es)
	}
	if data, err := os.ReadFile(filepath.Join(a.dir, es[0].File)); err != nil || string(data) != "\x89PNG..." {
		t.Errorf("image file: %v %q", err, data)
	}
	f.types = "application/x-private\n"
	a.run([]string{"store"})
	f.types = "text/plain\n"
	f.content = "   \n"
	a.run([]string{"store"})
	if len(entries(t, a)) != 1 {
		t.Error("a private type or blank text was stored")
	}
}

func TestListCopyShowRemoveClear(t *testing.T) {
	f := &fake{types: "text/plain\n", content: "first"}
	a, out := newApp(t, f)
	a.run([]string{"store"})
	f.content = "second"
	a.run([]string{"store"})
	f.types = "image/png\n"
	f.content = "PNG"
	a.run([]string{"store"})
	if code := a.run([]string{"list", "--json"}); code != 0 {
		t.Fatal("list")
	}
	var got []listed
	if err := json.Unmarshal(out.Bytes(), &got); err != nil {
		t.Fatal(err)
	}
	if len(got) != 3 || got[0].Kind != "image" || got[0].Preview != "Image, 3 bytes" || !strings.HasSuffix(got[0].File, ".png") || got[2].Preview != "first" {
		t.Errorf("listed %+v", got)
	}
	first := got[2].ID
	out.Reset()
	a.run([]string{"show", first})
	if out.String() != "first" {
		t.Errorf("show %q", out.String())
	}
	f.calls = nil
	if code := a.run([]string{"copy", first}); code != 0 {
		t.Fatal("copy")
	}
	if f.calls[0] != "wl-copy --type text/plain" || string(f.stdin[len(f.stdin)-1]) != "first" {
		t.Errorf("copy ran %q with %q", f.calls, f.stdin)
	}
	if es := entries(t, a); es[0].ID != first {
		t.Error("a copied entry moves to the front")
	}
	if code := a.run([]string{"copy", "nope"}); code != 1 {
		t.Error("copying a missing entry fails")
	}
	a.run([]string{"remove", got[0].ID})
	if _, err := os.Stat(got[0].File); !os.IsNotExist(err) {
		t.Error("removing an image entry deletes its file")
	}
	out.Reset()
	a.run([]string{"clear"})
	if len(entries(t, a)) != 0 || !strings.Contains(out.String(), "dropped 2") {
		t.Errorf("clear: %s", out)
	}
}

func TestWatch(t *testing.T) {
	a, _ := newApp(t, &fake{})
	var ran []string
	a.execve = func(argv []string) error { ran = argv; return nil }
	if code := a.run([]string{"watch"}); code != 0 {
		t.Fatal("watch")
	}
	if len(ran) != 4 || ran[0] != "wl-paste" || ran[1] != "--watch" || ran[3] != "store" {
		t.Errorf("execve %q", ran)
	}
}
