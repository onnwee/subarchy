// Package apps loads Subarchy's app catalogue (ADR 0044): which apps the
// installer offers, which ship preinstalled, and which app is the default
// for each role.
//
// Three files are read, each overriding the one before:
//
//   - the system catalogue, /usr/share/subcult/default/apps.toml;
//   - the user's catalogue, ~/.config/subcult/apps.toml, hand-edited: an
//     entry with an existing id replaces it, `remove = true` hides it;
//   - the user's default choices, ~/.config/subcult/defaults.toml, written by
//     `subcult app default`.
package apps

import (
	"errors"
	"fmt"
	"io"
	"io/fs"
	"os"
	"path/filepath"
	"regexp"
	"slices"
	"sort"
	"strings"

	"github.com/BurntSushi/toml"

	"git.subcult.tv/subculture-collective/subarchy/internal/atomicfile"
)

// Schema is the catalogue format version this package reads.
const Schema = 1

// Source says where an app's packages come from.
type Source string

// Known sources.
const (
	SourceRepo    Source = "repo"    // Arch repositories
	SourceAUR     Source = "aur"     // rebuilt into Subarchy's repository
	SourceMise    Source = "mise"    // installed per user with mise
	SourceFlatpak Source = "flatpak" // Flathub
	SourceWebapp  Source = "webapp"  // a Chromium app window
	SourceBuild   Source = "build"   // not packaged yet
)

var sources = []Source{SourceRepo, SourceAUR, SourceMise, SourceFlatpak, SourceWebapp, SourceBuild}

// App is one catalogue entry.
type App struct {
	ID           string   `toml:"id" json:"id"`
	Name         string   `toml:"name" json:"name"`
	Roles        []string `toml:"roles" json:"roles"`
	DefaultFor   []string `toml:"default_for" json:"default_for,omitempty"`
	Preinstalled bool     `toml:"preinstalled" json:"preinstalled"`
	Source       Source   `toml:"source" json:"source"`
	Packages     []string `toml:"packages" json:"packages,omitempty"`
	Desktop      string   `toml:"desktop" json:"desktop,omitempty"`
	URL          string   `toml:"url" json:"url,omitempty"`
	Notes        string   `toml:"notes" json:"notes,omitempty"`
	// Ask, for agents, is the command that answers one question on its
	// standard output; the question is appended (ADR 0047, 0057).
	Ask []string `toml:"ask" json:"ask,omitempty"`
	// Remove, in the user's catalogue, hides the system entry with this id.
	Remove bool `toml:"remove" json:"-"`
}

// HasRole reports whether the app can fill role.
func (a App) HasRole(role string) bool { return slices.Contains(a.Roles, role) }

type catalogFile struct {
	Schema int   `toml:"schema"`
	Apps   []App `toml:"app"`
}

type defaultsFile struct {
	Default map[string]string `toml:"default"`
}

// Paths names the three files Load reads. User and Defaults may be missing.
type Paths struct {
	System   string
	User     string
	Defaults string
	// Applications and Icons are the user's desktop entries and icon theme
	// (XDG_DATA_HOME), where web apps are installed.
	Applications string
	Icons        string
}

// DefaultPaths returns the standard locations, honouring XDG_CONFIG_HOME
// and, for development, SUBCULT_APPS_SYSTEM.
func DefaultPaths() (Paths, error) {
	system := os.Getenv("SUBCULT_APPS_SYSTEM")
	if system == "" {
		system = "/usr/share/subcult/default/apps.toml"
	}
	config, err := os.UserConfigDir()
	if err != nil {
		return Paths{}, fmt.Errorf("config directory: %w", err)
	}
	dir := filepath.Join(config, "subcult")
	data := os.Getenv("XDG_DATA_HOME")
	if data == "" {
		home, err := os.UserHomeDir()
		if err != nil {
			return Paths{}, fmt.Errorf("home directory: %w", err)
		}
		data = filepath.Join(home, ".local", "share")
	}
	return Paths{
		System:       system,
		User:         filepath.Join(dir, "apps.toml"),
		Defaults:     filepath.Join(dir, "defaults.toml"),
		Applications: filepath.Join(data, "applications"),
		Icons:        filepath.Join(data, "icons"),
	}, nil
}

// Catalog is the merged catalogue.
type Catalog struct {
	apps     []App
	defaults map[string]string // role -> app id
}

// Load reads and merges the catalogue files, then validates the result.
func Load(p Paths) (*Catalog, error) {
	system, err := readCatalog(p.System, false)
	if err != nil {
		return nil, err
	}
	user, err := readCatalog(p.User, true)
	if err != nil {
		return nil, err
	}
	choices, err := readDefaults(p.Defaults)
	if err != nil {
		return nil, err
	}
	return build(system, user, choices)
}

// Parse reads one catalogue from r. name is used in error messages.
func Parse(r io.Reader, name string) ([]App, error) {
	var f catalogFile
	md, err := toml.NewDecoder(r).Decode(&f)
	if err != nil {
		return nil, fmt.Errorf("%s: %w", name, err)
	}
	if undecoded := md.Undecoded(); len(undecoded) > 0 {
		keys := make([]string, len(undecoded))
		for i, k := range undecoded {
			keys[i] = k.String()
		}
		return nil, fmt.Errorf("%s: unknown keys: %s", name, strings.Join(keys, ", "))
	}
	if f.Schema != Schema {
		return nil, fmt.Errorf("%s: schema = %d, want %d", name, f.Schema, Schema)
	}
	return f.Apps, nil
}

func readCatalog(path string, optional bool) ([]App, error) {
	f, err := os.Open(path)
	if optional && errors.Is(err, fs.ErrNotExist) {
		return nil, nil
	}
	if err != nil {
		return nil, fmt.Errorf("app catalogue: %w", err)
	}
	defer f.Close()
	return Parse(f, path)
}

func readDefaults(path string) (map[string]string, error) {
	var f defaultsFile
	md, err := toml.DecodeFile(path, &f)
	if errors.Is(err, fs.ErrNotExist) {
		return nil, nil
	}
	if err != nil {
		return nil, fmt.Errorf("%s: %w", path, err)
	}
	if undecoded := md.Undecoded(); len(undecoded) > 0 {
		return nil, fmt.Errorf("%s: unknown key %s", path, undecoded[0])
	}
	return f.Default, nil
}

// build merges the layers. Defaults resolve in order: the user's choices,
// then default_for in the user's catalogue, then the system catalogue.
func build(system, user []App, choices map[string]string) (*Catalog, error) {
	var errs []error
	apps := slices.Clone(system)
	index := func(id string) int {
		return slices.IndexFunc(apps, func(a App) bool { return a.ID == id })
	}
	userDefaults := map[string]string{}
	for _, u := range user {
		if u.ID == "" {
			errs = append(errs, errors.New("user catalogue: entry without id"))
			continue
		}
		i := index(u.ID)
		switch {
		case u.Remove && i < 0:
			errs = append(errs, fmt.Errorf("user catalogue: remove %q: no such app", u.ID))
		case u.Remove:
			apps = slices.Delete(apps, i, i+1)
		case i >= 0:
			apps[i] = u
		default:
			apps = append(apps, u)
		}
		if u.Remove {
			continue
		}
		for _, role := range u.DefaultFor {
			if prev, ok := userDefaults[role]; ok {
				errs = append(errs, fmt.Errorf("user catalogue: role %q has two defaults: %s and %s", role, prev, u.ID))
			}
			userDefaults[role] = u.ID
		}
	}

	c := &Catalog{apps: apps, defaults: map[string]string{}}
	errs = append(errs, c.validate()...)
	userIDs := map[string]bool{}
	for _, u := range user {
		userIDs[u.ID] = true
	}
	for _, a := range apps {
		if userIDs[a.ID] {
			continue
		}
		for _, role := range a.DefaultFor {
			if prev, ok := c.defaults[role]; ok {
				errs = append(errs, fmt.Errorf("role %q has two defaults: %s and %s", role, prev, a.ID))
			}
			c.defaults[role] = a.ID
		}
	}
	for role, id := range userDefaults {
		c.defaults[role] = id
	}
	for role, id := range choices {
		a, ok := c.App(id)
		switch {
		case !ok:
			errs = append(errs, fmt.Errorf("defaults: %s = %q: no such app", role, id))
		case !a.HasRole(role):
			errs = append(errs, fmt.Errorf("defaults: %s = %q: app does not have that role", role, id))
		default:
			c.defaults[role] = id
		}
	}
	if len(errs) > 0 {
		return nil, errors.Join(errs...)
	}
	return c, nil
}

var idPattern = regexp.MustCompile(`^[a-z0-9][a-z0-9-]*$`)

// validate checks each entry on its own and that ids are unique.
func (c *Catalog) validate() []error {
	var errs []error
	seen := map[string]bool{}
	for _, a := range c.apps {
		bad := func(format string, args ...any) {
			errs = append(errs, fmt.Errorf("app %q: "+format, append([]any{a.ID}, args...)...))
		}
		if !idPattern.MatchString(a.ID) {
			bad("id must be lowercase letters, digits and dashes")
		}
		if seen[a.ID] {
			bad("duplicate id")
		}
		seen[a.ID] = true
		if a.Name == "" {
			bad("missing name")
		}
		if len(a.Roles) == 0 {
			bad("no roles")
		}
		for _, role := range a.Roles {
			if !idPattern.MatchString(role) {
				bad("role %q must be lowercase letters, digits and dashes", role)
			}
		}
		for _, role := range a.DefaultFor {
			if !a.HasRole(role) {
				bad("default_for %q is not one of its roles", role)
			}
			if _, mime := mimeTypes[role]; (mime || role == "terminal") && a.Desktop == "" {
				bad("default for %q needs a desktop file", role)
			}
		}
		if len(a.Ask) > 0 && a.Ask[0] == "" {
			bad("ask needs a program")
		}
		if !slices.Contains(sources, a.Source) {
			bad("unknown source %q", a.Source)
		}
		if a.Source == SourceWebapp {
			if !strings.HasPrefix(a.URL, "https://") {
				bad("web app needs an https url")
			}
		} else if len(a.Packages) == 0 {
			bad("no packages")
		}
		if a.Desktop != "" && !strings.HasSuffix(a.Desktop, ".desktop") {
			bad("desktop %q must end in .desktop", a.Desktop)
		}
	}
	return errs
}

// Apps returns every app in catalogue order.
func (c *Catalog) Apps() []App { return slices.Clone(c.apps) }

// App returns the app with the given id.
func (c *Catalog) App(id string) (App, bool) {
	i := slices.IndexFunc(c.apps, func(a App) bool { return a.ID == id })
	if i < 0 {
		return App{}, false
	}
	return c.apps[i], true
}

// Roles returns every role any app fills, sorted.
func (c *Catalog) Roles() []string {
	set := map[string]bool{}
	for _, a := range c.apps {
		for _, r := range a.Roles {
			set[r] = true
		}
	}
	roles := make([]string, 0, len(set))
	for r := range set {
		roles = append(roles, r)
	}
	sort.Strings(roles)
	return roles
}

// ForRole returns the apps that can fill role, in catalogue order.
func (c *Catalog) ForRole(role string) []App {
	var out []App
	for _, a := range c.apps {
		if a.HasRole(role) {
			out = append(out, a)
		}
	}
	return out
}

// Default returns the default app for role.
func (c *Catalog) Default(role string) (App, bool) {
	id, ok := c.defaults[role]
	if !ok {
		return App{}, false
	}
	return c.App(id)
}

// SaveDefault records id as the user's default for role in the defaults
// file, keeping the other choices. It does not apply the choice.
func SaveDefault(path, role, id string) error {
	choices, err := readDefaults(path)
	if err != nil {
		return err
	}
	if choices == nil {
		choices = map[string]string{}
	}
	choices[role] = id
	var b strings.Builder
	b.WriteString("# Written by `subcult app default`.\n")
	if err := toml.NewEncoder(&b).Encode(defaultsFile{Default: choices}); err != nil {
		return fmt.Errorf("encode defaults: %w", err)
	}
	if err := atomicfile.Write(path, []byte(b.String()), 0o644); err != nil {
		return fmt.Errorf("defaults: %w", err)
	}
	return nil
}
