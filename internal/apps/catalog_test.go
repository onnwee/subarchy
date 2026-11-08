package apps

import (
	"os"
	"path/filepath"
	"slices"
	"strings"
	"testing"
)

const systemTOML = `schema = 1

[[app]]
id = "kitty"
name = "kitty"
roles = ["terminal"]
default_for = ["terminal"]
preinstalled = true
source = "repo"
packages = ["kitty"]
desktop = "kitty.desktop"

[[app]]
id = "wezterm"
name = "WezTerm"
roles = ["terminal"]
source = "repo"
packages = ["wezterm"]
desktop = "org.wezfurlong.wezterm.desktop"

[[app]]
id = "zen"
name = "Zen"
roles = ["browser"]
default_for = ["browser"]
source = "aur"
packages = ["zen-browser-bin"]
desktop = "zen.desktop"

[[app]]
id = "chromium"
name = "Chromium"
roles = ["browser"]
source = "repo"
packages = ["chromium"]
desktop = "chromium.desktop"

[[app]]
id = "discord"
name = "Discord"
roles = ["chat"]
source = "webapp"
url = "https://discord.com/app"
`

func write(t *testing.T, dir, name, body string) string {
	t.Helper()
	p := filepath.Join(dir, name)
	if err := os.WriteFile(p, []byte(body), 0o644); err != nil {
		t.Fatal(err)
	}
	return p
}

func load(t *testing.T, system, user, defaults string) (*Catalog, error) {
	t.Helper()
	dir := t.TempDir()
	p := Paths{
		System:   write(t, dir, "system.toml", system),
		User:     filepath.Join(dir, "user.toml"),
		Defaults: filepath.Join(dir, "defaults.toml"),
	}
	if user != "" {
		write(t, dir, "user.toml", user)
	}
	if defaults != "" {
		write(t, dir, "defaults.toml", defaults)
	}
	return Load(p)
}

func defaultID(c *Catalog, role string) string {
	a, ok := c.Default(role)
	if !ok {
		return ""
	}
	return a.ID
}

func TestLoadSystemOnly(t *testing.T) {
	c, err := load(t, systemTOML, "", "")
	if err != nil {
		t.Fatal(err)
	}
	if got := len(c.Apps()); got != 5 {
		t.Errorf("apps = %d, want 5", got)
	}
	if got := defaultID(c, "terminal"); got != "kitty" {
		t.Errorf("terminal default = %q", got)
	}
	if got := c.Roles(); !slices.Equal(got, []string{"browser", "chat", "terminal"}) {
		t.Errorf("roles = %v", got)
	}
	if got := len(c.ForRole("browser")); got != 2 {
		t.Errorf("browsers = %d", got)
	}
	if _, ok := c.Default("chat"); ok {
		t.Error("chat should have no default")
	}
}

func TestLoadLayers(t *testing.T) {
	tests := []struct {
		name, user, defaults string
		check                func(t *testing.T, c *Catalog)
	}{
		{
			name: "user entry replaces system entry",
			user: "schema = 1\n[[app]]\nid = \"chromium\"\nname = \"Chromium (mine)\"\nroles = [\"browser\"]\nsource = \"repo\"\npackages = [\"chromium\"]\ndesktop = \"chromium.desktop\"\n",
			check: func(t *testing.T, c *Catalog) {
				a, _ := c.App("chromium")
				if a.Name != "Chromium (mine)" {
					t.Errorf("name = %q", a.Name)
				}
			},
		},
		{
			name: "user remove hides entry",
			user: "schema = 1\n[[app]]\nid = \"discord\"\nremove = true\n",
			check: func(t *testing.T, c *Catalog) {
				if _, ok := c.App("discord"); ok {
					t.Error("discord still present")
				}
			},
		},
		{
			name: "user default_for overrides system default",
			user: "schema = 1\n[[app]]\nid = \"foot\"\nname = \"foot\"\nroles = [\"terminal\"]\ndefault_for = [\"terminal\"]\nsource = \"repo\"\npackages = [\"foot\"]\ndesktop = \"foot.desktop\"\n",
			check: func(t *testing.T, c *Catalog) {
				if got := defaultID(c, "terminal"); got != "foot" {
					t.Errorf("terminal default = %q", got)
				}
			},
		},
		{
			name:     "defaults file wins",
			defaults: "[default]\nbrowser = \"chromium\"\n",
			check: func(t *testing.T, c *Catalog) {
				if got := defaultID(c, "browser"); got != "chromium" {
					t.Errorf("browser default = %q", got)
				}
			},
		},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			c, err := load(t, systemTOML, tt.user, tt.defaults)
			if err != nil {
				t.Fatal(err)
			}
			tt.check(t, c)
		})
	}
}

func TestLoadErrors(t *testing.T) {
	tests := []struct {
		name, system, user, defaults, want string
	}{
		{"wrong schema", "schema = 2\n", "", "", "schema = 2"},
		{"unknown key", systemTOML + "colour = \"red\"\n", "", "", "unknown keys"},
		{"two system defaults", systemTOML + "[[app]]\nid = \"foot\"\nname = \"foot\"\nroles = [\"terminal\"]\ndefault_for = [\"terminal\"]\nsource = \"repo\"\npackages = [\"foot\"]\ndesktop = \"foot.desktop\"\n", "", "", "two defaults"},
		{"duplicate id", systemTOML + "[[app]]\nid = \"zen\"\nname = \"Zen\"\nroles = [\"browser\"]\nsource = \"aur\"\npackages = [\"z\"]\n", "", "", "duplicate id"},
		{"default outside roles", strings.Replace(systemTOML, `default_for = ["browser"]`, `default_for = ["terminal"]`, 1), "", "", "not one of its roles"},
		{"bad source", strings.Replace(systemTOML, `source = "aur"`, `source = "snap"`, 1), "", "", `unknown source "snap"`},
		{"webapp without url", strings.Replace(systemTOML, `url = "https://discord.com/app"`, ``, 1), "", "", "https url"},
		{"no packages", strings.Replace(systemTOML, `packages = ["wezterm"]`, ``, 1), "", "", "no packages"},
		{"mime default without desktop", strings.Replace(systemTOML, `desktop = "zen.desktop"`, ``, 1), "", "", "needs a desktop file"},
		{"bad id", strings.Replace(systemTOML, `id = "kitty"`, `id = "Kitty"`, 1), "", "", "lowercase"},
		{"remove unknown", systemTOML, "schema = 1\n[[app]]\nid = \"nope\"\nremove = true\n", "", "no such app"},
		{"choice unknown app", systemTOML, "", "[default]\nbrowser = \"lynx\"\n", "no such app"},
		{"choice wrong role", systemTOML, "", "[default]\nbrowser = \"kitty\"\n", "does not have that role"},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			_, err := load(t, tt.system, tt.user, tt.defaults)
			if err == nil || !strings.Contains(err.Error(), tt.want) {
				t.Fatalf("err = %v, want it to contain %q", err, tt.want)
			}
		})
	}
}

func TestLoadMissingSystem(t *testing.T) {
	if _, err := Load(Paths{System: filepath.Join(t.TempDir(), "none.toml")}); err == nil {
		t.Fatal("want error for missing system catalogue")
	}
}

func TestSaveDefault(t *testing.T) {
	path := filepath.Join(t.TempDir(), "sub", "defaults.toml")
	if err := SaveDefault(path, "browser", "chromium"); err != nil {
		t.Fatal(err)
	}
	if err := SaveDefault(path, "terminal", "wezterm"); err != nil {
		t.Fatal(err)
	}
	got, err := readDefaults(path)
	if err != nil {
		t.Fatal(err)
	}
	if got["browser"] != "chromium" || got["terminal"] != "wezterm" {
		t.Errorf("defaults = %v", got)
	}
}

// TestShippedCatalogue validates the catalogue the package installs.
func TestShippedCatalogue(t *testing.T) {
	c, err := Load(Paths{System: "../../default/apps.toml"})
	if err != nil {
		t.Fatal(err)
	}
	for _, role := range []string{"terminal", "browser", "editor", "file-manager", "agent"} {
		if _, ok := c.Default(role); !ok {
			t.Errorf("no default %s", role)
		}
	}
	// Every agent answers the launcher's Ask row (ADR 0057).
	for _, a := range c.ForRole("agent") {
		if len(a.Ask) == 0 {
			t.Errorf("%s: no ask command", a.ID)
		}
	}
}

func FuzzParse(f *testing.F) {
	f.Add(systemTOML)
	f.Add("schema = 1\n[[app]]\nid = 3\n")
	f.Fuzz(func(t *testing.T, s string) {
		_, _ = Parse(strings.NewReader(s), "fuzz") // must not panic
	})
}
