package update

import (
	"context"
	"fmt"
	"os"
	"path/filepath"
	"regexp"
	"sort"
)

// Migrations run once per user, in timestamp order (ADR 0026, 0048, 0066).
// Each is /usr/share/subcult/migrations/<unix-time>.sh; a marker file of
// the same name in the user's state directory records that it ran.
var migrationName = regexp.MustCompile(`^[0-9]{10,}\.sh$`)

// Migrations locates migration scripts and their run markers.
type Migrations struct {
	Dir      string // scripts
	StateDir string // markers
}

// DefaultMigrations returns the standard locations, honouring
// SUBCULT_MIGRATIONS_DIR for development.
func DefaultMigrations() (Migrations, error) {
	dir := os.Getenv("SUBCULT_MIGRATIONS_DIR")
	if dir == "" {
		dir = "/usr/share/subcult/migrations"
	}
	state := os.Getenv("XDG_STATE_HOME")
	if state == "" {
		home, err := os.UserHomeDir()
		if err != nil {
			return Migrations{}, fmt.Errorf("home directory: %w", err)
		}
		state = filepath.Join(home, ".local", "state")
	}
	return Migrations{Dir: dir, StateDir: filepath.Join(state, "subcult", "migrations")}, nil
}

// Pending lists migrations not yet run, oldest first.
func (m Migrations) Pending() ([]string, error) {
	entries, err := os.ReadDir(m.Dir)
	if os.IsNotExist(err) {
		return nil, nil
	}
	if err != nil {
		return nil, fmt.Errorf("migrations: %w", err)
	}
	var pending []string
	for _, e := range entries {
		if e.IsDir() || !migrationName.MatchString(e.Name()) {
			continue
		}
		_, err := os.Stat(filepath.Join(m.StateDir, e.Name()))
		switch {
		case err == nil:
		case os.IsNotExist(err):
			pending = append(pending, e.Name())
		default:
			return nil, fmt.Errorf("migration marker: %w", err)
		}
	}
	// Names are equal-length timestamps in practice; sort numerically anyway.
	sort.Slice(pending, func(i, j int) bool {
		if len(pending[i]) != len(pending[j]) {
			return len(pending[i]) < len(pending[j])
		}
		return pending[i] < pending[j]
	})
	return pending, nil
}

// Run runs each pending migration with bash -euo pipefail and marks it done.
// It stops at the first failure, leaving that migration pending.
func (m Migrations) Run(ctx context.Context, r Runner) (ran []string, err error) {
	pending, err := m.Pending()
	if err != nil {
		return nil, err
	}
	if len(pending) == 0 {
		return nil, nil
	}
	if err := os.MkdirAll(m.StateDir, 0o755); err != nil {
		return nil, fmt.Errorf("migrations: %w", err)
	}
	for _, name := range pending {
		if err := r.Run(ctx, "bash", "-euo", "pipefail", filepath.Join(m.Dir, name)); err != nil {
			return ran, fmt.Errorf("migration %s: %w", name, err)
		}
		if _, dry := r.(DryRunner); !dry {
			if err := os.WriteFile(filepath.Join(m.StateDir, name), nil, 0o644); err != nil {
				return ran, fmt.Errorf("migration marker: %w", err)
			}
		}
		ran = append(ran, name)
	}
	return ran, nil
}

// MarkAll records every migration as done without running it. A fresh
// install calls this so a new user starts with no pending migrations.
func (m Migrations) MarkAll() error {
	pending, err := m.Pending()
	if err != nil {
		return err
	}
	if err := os.MkdirAll(m.StateDir, 0o755); err != nil {
		return fmt.Errorf("migrations: %w", err)
	}
	for _, name := range pending {
		if err := os.WriteFile(filepath.Join(m.StateDir, name), nil, 0o644); err != nil {
			return fmt.Errorf("migration marker: %w", err)
		}
	}
	return nil
}
