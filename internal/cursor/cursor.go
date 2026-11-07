// Package cursor builds Subarchy's own cursor theme, `subcult-cursor`, from
// flat SVG shapes coloured with a palette role (shell and look design,
// "Cursor"). It writes both formats: Xcursor for GTK and X11 apps and a
// hyprcursor theme that Hyprland scales without blurring.
package cursor

import (
	"bufio"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"math"
	"os"
	"path/filepath"
	"regexp"
	"strconv"
	"strings"
)

// ThemeName is the name both cursor formats install under.
const ThemeName = "subcult-cursor"

// Sizes are the pixel sizes rendered for Xcursor and accepted by Settings.
var Sizes = []int{24, 32, 48}

// Palette maps role names to #RRGGBB colours.
type Palette map[string]string

var hexColour = regexp.MustCompile(`^#[0-9A-Fa-f]{6}$`)

// LoadPalette reads the `colors` object of a palette.json (Theme Tender's
// schema 1) and rejects any value that is not #RRGGBB.
func LoadPalette(path string) (Palette, error) {
	data, err := os.ReadFile(path)
	if err != nil {
		return nil, err
	}
	var doc struct {
		Colors map[string]string `json:"colors"`
	}
	if err := json.Unmarshal(data, &doc); err != nil {
		return nil, fmt.Errorf("%s: %w", path, err)
	}
	if len(doc.Colors) == 0 {
		return nil, fmt.Errorf("%s: no colors", path)
	}
	for role, value := range doc.Colors {
		if !hexColour.MatchString(value) {
			return nil, fmt.Errorf("%s: %s is %q, not #RRGGBB", path, role, value)
		}
	}
	return Palette(doc.Colors), nil
}

// Outline picks the outline for a fill: crust on light fills, text on dark
// ones, judged by OKLab lightness against 0.5.
func Outline(fill, crust, text string) (string, error) {
	l, err := lightness(fill)
	if err != nil {
		return "", err
	}
	if l < 0.5 {
		return text, nil
	}
	return crust, nil
}

func lightness(hex string) (float64, error) {
	if !hexColour.MatchString(hex) {
		return 0, fmt.Errorf("%q is not #RRGGBB", hex)
	}
	v, err := strconv.ParseUint(hex[1:], 16, 32)
	if err != nil {
		return 0, err
	}
	lin := func(c uint64) float64 {
		x := float64(c) / 255
		if x <= 0.04045 {
			return x / 12.92
		}
		return math.Pow((x+0.055)/1.055, 2.4)
	}
	r, g, b := lin(v>>16&0xff), lin(v>>8&0xff), lin(v&0xff)
	l := math.Cbrt(0.4122214708*r + 0.5363325363*g + 0.0514459929*b)
	m := math.Cbrt(0.2119034982*r + 0.6806995451*g + 0.1073969566*b)
	s := math.Cbrt(0.0883024619*r + 0.2817188376*g + 0.6299787005*b)
	return 0.2104542553*l + 0.7936177850*m - 0.0040720468*s, nil
}

// Colourise fills the #FILL# and #LINE# placeholders of a shape's SVG.
func Colourise(svg, fill, line string) string {
	return strings.NewReplacer("#FILL#", fill, "#LINE#", line).Replace(svg)
}

// Shape is one drawn cursor: its file name in the source folder (without
// .svg), its hotspot in the 32-unit SVG grid, and the other cursor names
// that use it.
type Shape struct {
	Name       string
	HotX, HotY int
	Aliases    []string
}

// ParseShapes reads shapes.tsv: `shape<TAB>hot_x<TAB>hot_y<TAB>names...`,
// with `#` comments and blank lines. Every cursor name may appear once.
func ParseShapes(r io.Reader) ([]Shape, error) {
	var shapes []Shape
	seen := map[string]bool{}
	sc := bufio.NewScanner(r)
	for n := 1; sc.Scan(); n++ {
		line := strings.TrimSpace(sc.Text())
		if line == "" || strings.HasPrefix(line, "#") {
			continue
		}
		f := strings.Split(line, "\t")
		if len(f) < 3 {
			return nil, fmt.Errorf("shapes line %d: want shape, hot_x, hot_y and names", n)
		}
		s := Shape{Name: f[0]}
		var err error
		if s.HotX, err = hotspot(f[1]); err != nil {
			return nil, fmt.Errorf("shapes line %d: %w", n, err)
		}
		if s.HotY, err = hotspot(f[2]); err != nil {
			return nil, fmt.Errorf("shapes line %d: %w", n, err)
		}
		if len(f) > 3 {
			s.Aliases = strings.Fields(f[3])
		}
		for _, name := range append([]string{s.Name}, s.Aliases...) {
			if seen[name] {
				return nil, fmt.Errorf("shapes line %d: cursor name %s used twice", n, name)
			}
			seen[name] = true
		}
		shapes = append(shapes, s)
	}
	return shapes, sc.Err()
}

func hotspot(s string) (int, error) {
	v, err := strconv.Atoi(s)
	if err != nil || v < 0 || v > 31 {
		return 0, fmt.Errorf("hotspot %q is not 0-31", s)
	}
	return v, nil
}

// Settings is the user's choice, stored in ~/.config/subcult/cursor.json.
type Settings struct {
	Role string `json:"role"`
	Size int    `json:"size"`
}

// Default is lavender at 24 px (owner, 2026-11-07).
var Default = Settings{Role: "lavender", Size: 24}

// LoadSettings returns the saved settings, or Default when the file is
// missing or unreadable.
func LoadSettings(path string) Settings {
	data, err := os.ReadFile(path)
	if err != nil {
		return Default
	}
	s := Default
	if err := json.Unmarshal(data, &s); err != nil {
		return Default
	}
	return s
}

// SaveSettings writes the settings atomically.
func SaveSettings(path string, s Settings) error {
	data, err := json.MarshalIndent(s, "", "  ")
	if err != nil {
		return err
	}
	if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
		return err
	}
	tmp := path + ".tmp"
	if err := os.WriteFile(tmp, append(data, '\n'), 0o644); err != nil {
		return err
	}
	return os.Rename(tmp, path)
}

// ErrInvalid marks a setting the palette or the size list rejects.
var ErrInvalid = errors.New("invalid cursor setting")

// Validate checks the role exists in the palette and the size is offered.
func Validate(s Settings, p Palette) error {
	if _, ok := p[s.Role]; !ok {
		return fmt.Errorf("%w: the palette has no role %q", ErrInvalid, s.Role)
	}
	for _, size := range Sizes {
		if s.Size == size {
			return nil
		}
	}
	return fmt.Errorf("%w: size %d is not one of %v", ErrInvalid, s.Size, Sizes)
}
