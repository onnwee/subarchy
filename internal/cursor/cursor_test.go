package cursor

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func TestOutlineContrastsWithFill(t *testing.T) {
	tests := []struct {
		name, fill, want string
	}{
		{"light fill gets crust", "#A78BFA", "#06040A"},
		{"paper fill gets crust", "#F0ECE4", "#06040A"},
		{"dark fill gets text", "#3B2470", "#F0ECE4"},
		{"ink fill gets text", "#100B19", "#F0ECE4"},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got, err := Outline(tt.fill, "#06040A", "#F0ECE4")
			if err != nil {
				t.Fatal(err)
			}
			if got != tt.want {
				t.Errorf("Outline(%s) = %s, want %s", tt.fill, got, tt.want)
			}
		})
	}
}

func TestOutlineRejectsBadHex(t *testing.T) {
	if _, err := Outline("lavender", "#06040A", "#F0ECE4"); err == nil {
		t.Error("want an error for a fill that is not #RRGGBB")
	}
}

func TestParseShapes(t *testing.T) {
	in := "# shape\thot_x\thot_y\tnames\n" +
		"default\t4\t2\tleft_ptr arrow\n" +
		"\n" +
		"text\t16\t16\txterm ibeam\n"
	shapes, err := ParseShapes(strings.NewReader(in))
	if err != nil {
		t.Fatal(err)
	}
	if len(shapes) != 2 {
		t.Fatalf("got %d shapes, want 2", len(shapes))
	}
	if s := shapes[0]; s.Name != "default" || s.HotX != 4 || s.HotY != 2 || strings.Join(s.Aliases, ",") != "left_ptr,arrow" {
		t.Errorf("first shape = %+v", s)
	}
}

func TestParseShapesErrors(t *testing.T) {
	tests := map[string]string{
		"hotspot out of range": "default\t40\t2\tleft_ptr\n",
		"hotspot not a number": "default\tx\t2\tleft_ptr\n",
		"too few fields":       "default\t4\n",
		"duplicate name":       "default\t4\t2\tarrow\npointer\t8\t2\tarrow\n",
	}
	for name, in := range tests {
		t.Run(name, func(t *testing.T) {
			if _, err := ParseShapes(strings.NewReader(in)); err == nil {
				t.Error("want an error")
			}
		})
	}
}

func TestColourise(t *testing.T) {
	got := Colourise(`<path fill="#FILL#" stroke="#LINE#"/>`, "#A78BFA", "#06040A")
	if got != `<path fill="#A78BFA" stroke="#06040A"/>` {
		t.Errorf("Colourise = %s", got)
	}
}

func TestLoadPalette(t *testing.T) {
	dir := t.TempDir()
	good := filepath.Join(dir, "good.json")
	writeFile(t, good, `{"schema": 1, "colors": {"lavender": "#A78BFA", "crust": "#06040A"}}`)
	p, err := LoadPalette(good)
	if err != nil {
		t.Fatal(err)
	}
	if p["lavender"] != "#A78BFA" {
		t.Errorf("lavender = %q", p["lavender"])
	}
	bad := filepath.Join(dir, "bad.json")
	writeFile(t, bad, `{"schema": 1, "colors": {"lavender": "purple"}}`)
	if _, err := LoadPalette(bad); err == nil {
		t.Error("want an error for a colour that is not #RRGGBB")
	}
	if _, err := LoadPalette(filepath.Join(dir, "missing.json")); err == nil {
		t.Error("want an error for a missing file")
	}
}

func TestSettingsDefaultWhenMissingOrBroken(t *testing.T) {
	dir := t.TempDir()
	if s := LoadSettings(filepath.Join(dir, "none.json")); s != Default {
		t.Errorf("missing file gave %+v, want %+v", s, Default)
	}
	broken := filepath.Join(dir, "broken.json")
	writeFile(t, broken, `{"role": `)
	if s := LoadSettings(broken); s != Default {
		t.Errorf("broken file gave %+v, want %+v", s, Default)
	}
	if Default.Role != "lavender" || Default.Size != 24 {
		t.Errorf("Default = %+v, spec says lavender at 24", Default)
	}
}

func TestSettingsRoundTrip(t *testing.T) {
	path := filepath.Join(t.TempDir(), "sub", "cursor.json")
	want := Settings{Role: "mauve", Size: 32}
	if err := SaveSettings(path, want); err != nil {
		t.Fatal(err)
	}
	if got := LoadSettings(path); got != want {
		t.Errorf("round trip gave %+v, want %+v", got, want)
	}
}

func TestValidate(t *testing.T) {
	palette := Palette{"lavender": "#A78BFA", "crust": "#06040A", "text": "#F0ECE4"}
	if err := Validate(Settings{Role: "lavender", Size: 24}, palette); err != nil {
		t.Errorf("valid settings: %v", err)
	}
	if err := Validate(Settings{Role: "nonsense", Size: 24}, palette); err == nil {
		t.Error("want an error for a role the palette lacks")
	}
	if err := Validate(Settings{Role: "lavender", Size: 30}, palette); err == nil {
		t.Error("want an error for a size other than 24, 32 or 48")
	}
}

func writeFile(t *testing.T, path, content string) {
	t.Helper()
	if err := os.WriteFile(path, []byte(content), 0o644); err != nil {
		t.Fatal(err)
	}
}

func TestLoadLayered(t *testing.T) {
	dir := t.TempDir()
	system := filepath.Join(dir, "system.json")
	writeFile(t, system, `{"schema": 1, "colors": {"lavender": "#A78BFA", "crust": "#06040A", "text": "#F0ECE4"}}`)
	user := filepath.Join(dir, "user.json")

	tests := []struct {
		name, content string
		lavender      string
		warnings      int
	}{
		{"missing user file", "", "#A78BFA", 0},
		{"bad JSON", `{"colors": `, "#A78BFA", 1},
		{"one bad role", `{"colors": {"lavender": "#112233", "foo": "oops"}}`, "#112233", 1},
		{"role missing in user file", `{"colors": {"green": "#00FF88"}}`, "#A78BFA", 0},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			os.Remove(user)
			if tt.content != "" {
				writeFile(t, user, tt.content)
			}
			p, warnings, err := LoadLayered(system, user)
			if err != nil {
				t.Fatal(err)
			}
			if p["lavender"] != tt.lavender {
				t.Errorf("lavender = %s, want %s", p["lavender"], tt.lavender)
			}
			if len(warnings) != tt.warnings {
				t.Errorf("warnings = %v, want %d", warnings, tt.warnings)
			}
		})
	}
	if _, _, err := LoadLayered(filepath.Join(dir, "none.json"), user); err == nil {
		t.Error("want an error when the system palette is missing")
	}
}
