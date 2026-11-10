// Package cursortest stands in for the programs a cursor build runs.
package cursortest

import (
	"context"
	"errors"
	"os"
	"path/filepath"
)

// Tools is an update.Runner that does what rsvg-convert, xcursorgen and
// hyprcursor-util do to the filesystem, without rendering anything. Fail
// names a program that exits with an error instead.
type Tools struct {
	Fail    string
	Configs map[string]string // xcursorgen config text by cursor name
}

func (t *Tools) Run(_ context.Context, argv ...string) error {
	if argv[0] == t.Fail {
		return errors.New(argv[0] + ": failed")
	}
	switch argv[0] {
	case "rsvg-convert": // -w N -h N -o PNG SVG
		return os.WriteFile(argv[6], []byte("png"), 0o644)
	case "xcursorgen": // CONFIG OUT
		cfg, err := os.ReadFile(argv[1])
		if err != nil {
			return err
		}
		if t.Configs == nil {
			t.Configs = map[string]string{}
		}
		t.Configs[filepath.Base(argv[2])] = string(cfg)
		return os.WriteFile(argv[2], []byte("xcursor"), 0o644)
	case "hyprcursor-util": // --create DIR, writing DIR/../theme_<name>
		manifest, err := os.ReadFile(filepath.Join(argv[2], "manifest.hl"))
		if err != nil {
			return err
		}
		out := filepath.Join(filepath.Dir(argv[2]), "theme_subcult-cursor")
		if err := os.MkdirAll(filepath.Join(out, "hyprcursors"), 0o755); err != nil {
			return err
		}
		return os.WriteFile(filepath.Join(out, "manifest.hl"), manifest, 0o644)
	}
	return nil
}

func (t *Tools) Output(context.Context, ...string) (string, error) { return "", nil }
func (t *Tools) Has(string) bool                                   { return false }
