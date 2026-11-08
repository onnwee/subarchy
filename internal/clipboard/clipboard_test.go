package clipboard

import (
	"strings"
	"testing"
	"time"
)

var now = time.Date(2026, 11, 7, 23, 0, 0, 0, time.UTC)

func TestSecret(t *testing.T) {
	if !Secret([]string{"text/plain", SecretType}) {
		t.Error("the hint type marks a secret")
	}
	if Secret([]string{"text/plain;charset=utf-8", "image/png"}) {
		t.Error("no hint, no secret")
	}
	if !Secret([]string{" " + SecretType + "\n"}) {
		t.Error("types are trimmed")
	}
}

func TestPick(t *testing.T) {
	cases := []struct {
		types      []string
		kind, mime string
	}{
		{[]string{"text/plain;charset=utf-8", "text/plain", "TEXT", "STRING", "UTF8_STRING"}, "text", "text/plain;charset=utf-8"},
		{[]string{"image/png", "image/jpeg", "text/html"}, "image", "image/png"},
		{[]string{"text/html", "text/plain", "image/png"}, "image", "image/png"},
		{[]string{"text/uri-list", "x-special/gnome-copied-files"}, "text", "text/uri-list"},
		{[]string{"application/x-kde-cutselection"}, "", ""},
		{nil, "", ""},
	}
	for _, c := range cases {
		kind, mime := Pick(c.types)
		if kind != c.kind || mime != c.mime {
			t.Errorf("Pick(%v) = %q %q, want %q %q", c.types, kind, mime, c.kind, c.mime)
		}
	}
}

func TestEntriesAndPreview(t *testing.T) {
	e := TextEntry("hello\n  world", "text/plain", now)
	if e.Kind != "text" || e.Size != 13 || len(e.ID) != 16 || e.Text != "hello\n  world" {
		t.Errorf("entry %+v", e)
	}
	if Preview(e) != "hello world" {
		t.Errorf("preview %q", Preview(e))
	}
	long := strings.Repeat("ab", 100)
	if p := Preview(TextEntry(long, "text/plain", now)); len([]rune(p)) != 80 || !strings.HasSuffix(p, "…") {
		t.Errorf("long preview %q", p)
	}
	if Preview(TextEntry("  \n", "text/plain", now)) != "(whitespace)" {
		t.Error("whitespace preview")
	}
	img := ImageEntry([]byte("PNG..."), "image/png", now)
	if img.Kind != "image" || img.File != img.ID+".png" || Preview(img) != "Image, 6 bytes" {
		t.Errorf("image %+v %q", img, Preview(img))
	}
	if TextEntry("a", "text/plain", now).ID == TextEntry("b", "text/plain", now).ID {
		t.Error("ids differ by content")
	}
}

func TestStoreAdd(t *testing.T) {
	var s Store
	a := TextEntry("a", "text/plain", now)
	b := TextEntry("b", "text/plain", now.Add(time.Second))
	s.Add(a)
	s.Add(b)
	if len(s.Entries) != 2 || s.Entries[0].ID != b.ID {
		t.Fatalf("newest first: %+v", s.Entries)
	}
	a2 := TextEntry("a", "text/plain", now.Add(2*time.Second))
	if dropped := s.Add(a2); len(dropped) != 0 || len(s.Entries) != 2 || s.Entries[0].ID != a.ID || !s.Entries[0].Time.Equal(a2.Time) {
		t.Errorf("a copy of the same text moves to the front with the new time: %+v %v", s.Entries, dropped)
	}
	// The cap on entries.
	s = Store{}
	for i := 0; i < MaxEntries+5; i++ {
		s.Add(TextEntry(strings.Repeat("x", i+1), "text/plain", now))
	}
	if len(s.Entries) != MaxEntries {
		t.Errorf("%d entries, want %d", len(s.Entries), MaxEntries)
	}
	// The cap on image bytes drops the oldest images and keeps text.
	s = Store{}
	big := Entry{ID: "old", Kind: "image", File: "old.png", Size: MaxImages - 10, Time: now}
	s.Add(big)
	s.Add(TextEntry("keep", "text/plain", now))
	dropped := s.Add(Entry{ID: "new", Kind: "image", File: "new.png", Size: 20, Time: now})
	if len(dropped) != 1 || dropped[0].ID != "old" {
		t.Errorf("dropped %+v", dropped)
	}
	if got := ids(s); got != "new,"+TextEntry("keep", "text/plain", now).ID {
		t.Errorf("kept %s", got)
	}
}

func ids(s Store) string {
	var out []string
	for _, e := range s.Entries {
		out = append(out, e.ID)
	}
	return strings.Join(out, ",")
}

func TestStoreGetRemoveClear(t *testing.T) {
	var s Store
	a := TextEntry("a", "text/plain", now)
	s.Add(a)
	s.Add(TextEntry("b", "text/plain", now))
	if e, ok := s.Get(a.ID); !ok || e.Text != "a" {
		t.Error("get")
	}
	if _, ok := s.Get("nope"); ok {
		t.Error("get missing")
	}
	if e, ok := s.Remove(a.ID); !ok || e.Text != "a" || len(s.Entries) != 1 {
		t.Error("remove")
	}
	if all := s.Clear(); len(all) != 1 || len(s.Entries) != 0 {
		t.Error("clear")
	}
}

func TestLoadSave(t *testing.T) {
	dir := t.TempDir() + "/clipboard"
	s, err := Load(dir)
	if err != nil || len(s.Entries) != 0 {
		t.Fatalf("empty load: %v %+v", err, s)
	}
	s.Add(TextEntry("hello", "text/plain", now))
	if err := Save(dir, s); err != nil {
		t.Fatal(err)
	}
	again, err := Load(dir)
	if err != nil || len(again.Entries) != 1 || again.Entries[0].Text != "hello" || again.Schema != 1 {
		t.Fatalf("reload: %v %+v", err, again)
	}
	t.Setenv("XDG_STATE_HOME", "/tmp/state")
	if d, _ := DefaultDir(); d != "/tmp/state/subcult/clipboard" {
		t.Errorf("default dir %s", d)
	}
}
