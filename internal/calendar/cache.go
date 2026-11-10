package calendar

import (
	"encoding/json"
	"errors"
	"fmt"
	"os"
	"time"

	"git.subcult.tv/subculture-collective/subarchy/internal/atomicfile"
)

// SourceResult says how one source's last sync went.
type SourceResult struct {
	Name   string `json:"name"`
	OK     bool   `json:"ok"`
	Error  string `json:"error,omitempty"`
	Events int    `json:"events"`
}

// Cache is ~/.local/state/subcult/calendar/events.json: what the widget
// watches. Version changes only when a field is removed or changes meaning.
type Cache struct {
	Version  int            `json:"version"`
	SyncedAt time.Time      `json:"syncedAt"`
	Window   Window         `json:"window"`
	Sources  []SourceResult `json:"sources"`
	Events   []Event        `json:"events"`
}

// CacheVersion is the current format.
const CacheVersion = 1

// ReadCache loads a cache; a missing file is an empty cache.
func ReadCache(path string) (Cache, error) {
	var c Cache
	raw, err := os.ReadFile(path)
	if errors.Is(err, os.ErrNotExist) {
		return c, nil
	}
	if err != nil {
		return c, err
	}
	if err := json.Unmarshal(raw, &c); err != nil {
		return Cache{}, fmt.Errorf("%s: %w", path, err)
	}
	if c.Version != CacheVersion {
		return Cache{}, nil
	}
	return c, nil
}

// WriteCache saves the cache atomically.
func WriteCache(path string, c Cache) error {
	c.Version = CacheVersion
	raw, err := json.MarshalIndent(c, "", "  ")
	if err != nil {
		return err
	}
	return atomicfile.Write(path, append(raw, '\n'), 0o644)
}
