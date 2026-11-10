// Package clipboard keeps the clipboard history the launcher's "$" prefix
// shows (ADR 0056, 0057): the text and images copied, newest first, in a
// capped store under the user's state directory. Copies marked secret
// (the x-kde-passwordManagerHint MIME type) are never stored.
package clipboard

import (
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"time"

	"git.subcult.tv/subculture-collective/subarchy/internal/atomicfile"
)

// SecretType marks a copy that password managers want kept out of history.
const SecretType = "x-kde-passwordManagerHint"

// SecretClearAfter is how long a secret copy stays on the clipboard.
const SecretClearAfter = 30 * time.Second

const (
	MaxEntries = 200       // entries kept
	MaxText    = 64 << 10  // bytes of one text copy; larger ones are skipped
	MaxImage   = 16 << 20  // bytes of one image copy
	MaxImages  = 128 << 20 // bytes of all image files together
)

// Entry is one copy.
type Entry struct {
	ID   string    `json:"id"`   // first 16 hex digits of the content's SHA-256
	Kind string    `json:"kind"` // "text" or "image"
	Mime string    `json:"mime"`
	Text string    `json:"text,omitempty"` // text entries
	File string    `json:"file,omitempty"` // image entries: file name in the store's directory
	Size int       `json:"size"`
	Time time.Time `json:"time"`
}

// Store is history.json in the store's directory, newest entry first.
type Store struct {
	Schema  int     `json:"schema"`
	Entries []Entry `json:"entries"`
}

// Secret reports whether the offered types mark the copy as a secret.
func Secret(types []string) bool {
	for _, t := range types {
		if strings.TrimSpace(t) == SecretType {
			return true
		}
	}
	return false
}

// Pick chooses what to keep from the offered MIME types: a PNG when an image
// is offered, otherwise the first text type; "" when nothing is worth
// keeping (a file drag, an application's private format).
func Pick(types []string) (kind, mime string) {
	var text string
	for _, t := range types {
		t = strings.TrimSpace(t)
		switch {
		case t == "image/png":
			return "image", t
		case text == "" && (t == "text/plain;charset=utf-8" || t == "text/plain" || t == "UTF8_STRING" || t == "text/uri-list"):
			text = t
		}
	}
	if text != "" {
		return "text", text
	}
	return "", ""
}

func id(data []byte) string {
	sum := sha256.Sum256(data)
	return hex.EncodeToString(sum[:8])
}

// TextEntry is the entry for a text copy.
func TextEntry(text, mime string, now time.Time) Entry {
	return Entry{ID: id([]byte(text)), Kind: "text", Mime: mime, Text: text, Size: len(text), Time: now}
}

// ImageEntry is the entry for an image copy; its bytes go to File.
func ImageEntry(data []byte, mime string, now time.Time) Entry {
	i := id(data)
	return Entry{ID: i, Kind: "image", Mime: mime, File: i + ".png", Size: len(data), Time: now}
}

// Preview is an entry's one-line label for a list: the text's first 80
// characters on one line, or the image's size.
func Preview(e Entry) string {
	if e.Kind == "image" {
		return fmt.Sprintf("Image, %s", humanSize(e.Size))
	}
	s := strings.Join(strings.Fields(e.Text), " ")
	if r := []rune(s); len(r) > 80 {
		s = string(r[:79]) + "…"
	}
	if s == "" {
		s = "(whitespace)"
	}
	return s
}

func humanSize(n int) string {
	switch {
	case n >= 1<<20:
		return fmt.Sprintf("%.1f MiB", float64(n)/(1<<20))
	case n >= 1<<10:
		return fmt.Sprintf("%.0f KiB", float64(n)/(1<<10))
	}
	return fmt.Sprintf("%d bytes", n)
}

// Load reads the store in dir; a missing file is empty.
func Load(dir string) (Store, error) {
	var s Store
	raw, err := os.ReadFile(filepath.Join(dir, "history.json"))
	if errors.Is(err, os.ErrNotExist) {
		return Store{Schema: 1}, nil
	}
	if err != nil {
		return s, err
	}
	if err := json.Unmarshal(raw, &s); err != nil {
		return s, fmt.Errorf("%s: %w", filepath.Join(dir, "history.json"), err)
	}
	if s.Schema != 1 {
		return s, fmt.Errorf("%s: schema must be 1", filepath.Join(dir, "history.json"))
	}
	return s, nil
}

// Save writes the store atomically, private to the user.
func Save(dir string, s Store) error {
	s.Schema = 1
	raw, err := json.Marshal(s)
	if err != nil {
		return err
	}
	if err := os.MkdirAll(dir, 0o700); err != nil {
		return err
	}
	return atomicfile.Write(filepath.Join(dir, "history.json"), append(raw, '\n'), 0o600)
}

// Add puts e first, dropping an older copy of the same content, and trims
// the store to MaxEntries entries and MaxImages bytes of images. It
// returns the entries dropped, so their files can go.
func (s *Store) Add(e Entry) []Entry {
	var dropped []Entry
	kept := make([]Entry, 0, len(s.Entries)+1)
	kept = append(kept, e)
	images := 0
	if e.Kind == "image" {
		images = e.Size
	}
	for _, old := range s.Entries {
		if old.ID == e.ID {
			continue
		}
		if len(kept) >= MaxEntries || (old.Kind == "image" && images+old.Size > MaxImages) {
			dropped = append(dropped, old)
			continue
		}
		if old.Kind == "image" {
			images += old.Size
		}
		kept = append(kept, old)
	}
	s.Entries = kept
	return dropped
}

// Get finds an entry by id.
func (s Store) Get(id string) (Entry, bool) {
	for _, e := range s.Entries {
		if e.ID == id {
			return e, true
		}
	}
	return Entry{}, false
}

// Remove drops the entry with id and returns it.
func (s *Store) Remove(id string) (Entry, bool) {
	for i, e := range s.Entries {
		if e.ID == id {
			s.Entries = append(s.Entries[:i], s.Entries[i+1:]...)
			return e, true
		}
	}
	return Entry{}, false
}

// Clear drops every entry and returns them.
func (s *Store) Clear() []Entry {
	all := s.Entries
	s.Entries = nil
	return all
}

// DefaultDir is ~/.local/state/subcult/clipboard (or under XDG_STATE_HOME).
func DefaultDir() (string, error) {
	if state := os.Getenv("XDG_STATE_HOME"); state != "" {
		return filepath.Join(state, "subcult", "clipboard"), nil
	}
	home, err := os.UserHomeDir()
	if err != nil {
		return "", err
	}
	return filepath.Join(home, ".local", "state", "subcult", "clipboard"), nil
}
