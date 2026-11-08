package calendar

import (
	"errors"
	"fmt"
	"os"
	"strings"

	"github.com/BurntSushi/toml"
)

// Source is one calendar: a CalDAV collection or an iCal feed. Nothing
// secret lives here: a CalDAV password is read from the keyring under the
// source's name (`secret-tool lookup service subcult-calendar source
// <name>`).
type Source struct {
	Name string `toml:"name"`
	Kind string `toml:"kind"` // "caldav" or "ical"
	URL  string `toml:"url"`
	User string `toml:"user"` // CalDAV user name; the password is in the keyring
}

// Config is ~/.config/subcult/calendar.toml.
type Config struct {
	Schema  int      `toml:"schema"`
	Sources []Source `toml:"source"`
}

// LoadConfig reads the config; a missing file is an empty config.
func LoadConfig(path string) (Config, error) {
	var c Config
	raw, err := os.ReadFile(path)
	if errors.Is(err, os.ErrNotExist) {
		return c, nil
	}
	if err != nil {
		return c, err
	}
	md, err := toml.Decode(string(raw), &c)
	if err != nil {
		return c, fmt.Errorf("%s: %w", path, err)
	}
	if un := md.Undecoded(); len(un) > 0 {
		return c, fmt.Errorf("%s: unknown field %s (a password belongs in the keyring, not here)", path, un[0])
	}
	if c.Schema != 1 {
		return c, fmt.Errorf("%s: schema must be 1", path)
	}
	seen := map[string]bool{}
	for i, s := range c.Sources {
		switch {
		case strings.TrimSpace(s.Name) == "":
			return c, fmt.Errorf("%s: source %d has no name", path, i+1)
		case seen[s.Name]:
			return c, fmt.Errorf("%s: source %q listed twice", path, s.Name)
		case s.Kind != "caldav" && s.Kind != "ical":
			return c, fmt.Errorf("%s: source %q: kind must be caldav or ical", path, s.Name)
		case !strings.HasPrefix(s.URL, "https://") && !strings.HasPrefix(s.URL, "http://"):
			return c, fmt.Errorf("%s: source %q: url must be http or https", path, s.Name)
		case s.Kind == "caldav" && s.User == "":
			return c, fmt.Errorf("%s: source %q: a caldav source needs a user", path, s.Name)
		}
		seen[s.Name] = true
	}
	return c, nil
}
