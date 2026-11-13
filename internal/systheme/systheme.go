// Package systheme applies the user's palette to the root-owned screens
// (ADR 0037): SDDM's theme configuration, Limine's terminal and branding
// colours, a recoloured copy of the Plymouth theme, and Chromium's colour
// policy. Pult runs as the user and writes the palette file; `subcult theme
// apply-system` reads it, hands the colours to a privileged run of itself
// through polkit, and that run calls Apply. The privileged half never
// opens a user file: the colours arrive as arguments and every one must be
// #rrggbb.
package systheme

import (
	"encoding/json"
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"regexp"
	"sort"
	"strconv"
	"strings"
)

// Palette is a theme's colours by Pult role, lower-case #rrggbb each, and
// its appearance (dark or light).
type Palette struct {
	Appearance string
	Colors     map[string]string
}

var hexColour = regexp.MustCompile(`^#[0-9a-fA-F]{6}$`)
var roleName = regexp.MustCompile(`^[a-z][a-z0-9_]*$`)

// Fallback is subcult-minimal, the palette the screens ship with; a role a
// theme leaves out comes from here.
var Fallback = map[string]string{
	"base": "#100b19", "mantle": "#0b0812", "crust": "#06040a", "surface0": "#1f1830", "surface1": "#3b2470",
	"text": "#f0ece4", "subtext0": "#9a92a8", "overlay0": "#5e5570", "mauve": "#8f4bc8", "green": "#00ff88",
	"red": "#d52032", "yellow": "#f6d447",
}

// ParsePalette reads a palette file as Pult and the shell write it: a JSON
// object with "colors" (role -> #rrggbb) and the appearance either at the
// top or under "theme". Anything that is not a colour is refused.
func ParsePalette(data []byte) (Palette, error) {
	var doc struct {
		Appearance string                      `json:"appearance"`
		Theme      struct{ Appearance string } `json:"theme"`
		Colors     map[string]string           `json:"colors"`
	}
	if err := json.Unmarshal(data, &doc); err != nil {
		return Palette{}, fmt.Errorf("palette: %w", err)
	}
	if len(doc.Colors) == 0 {
		return Palette{}, errors.New("palette: no colors")
	}
	p := Palette{Appearance: doc.Appearance, Colors: map[string]string{}}
	if p.Appearance == "" {
		p.Appearance = doc.Theme.Appearance
	}
	for role, c := range doc.Colors {
		if !roleName.MatchString(role) || !hexColour.MatchString(c) {
			return Palette{}, fmt.Errorf("palette: %q is not a role with a #rrggbb colour (%q)", role, c)
		}
		p.Colors[role] = strings.ToLower(c)
	}
	if p.Appearance != "light" {
		p.Appearance = "dark"
	}
	return p, nil
}

// Args renders the palette for the privileged run: "role=#rrggbb,..." in
// role order, so the same palette gives the same string.
func (p Palette) Args() string {
	roles := make([]string, 0, len(p.Colors))
	for r := range p.Colors {
		roles = append(roles, r)
	}
	sort.Strings(roles)
	parts := make([]string, 0, len(roles))
	for _, r := range roles {
		parts = append(parts, r+"="+p.Colors[r])
	}
	return strings.Join(parts, ",")
}

// ParseArgs is the inverse of Args, as strict as ParsePalette.
func ParseArgs(colors, appearance string) (Palette, error) {
	p := Palette{Appearance: appearance, Colors: map[string]string{}}
	if colors == "" {
		return Palette{}, errors.New("no colours given")
	}
	for _, part := range strings.Split(colors, ",") {
		role, c, ok := strings.Cut(part, "=")
		if !ok || !roleName.MatchString(role) || !hexColour.MatchString(c) {
			return Palette{}, fmt.Errorf("%q is not role=#rrggbb", part)
		}
		p.Colors[role] = strings.ToLower(c)
	}
	if p.Appearance != "light" {
		p.Appearance = "dark"
	}
	return p, nil
}

// role is the palette's colour for a role, else subcult-minimal's.
func (p Palette) role(name string) string {
	if c, ok := p.Colors[name]; ok {
		return c
	}
	return Fallback[name]
}

func bare(c string) string { return strings.TrimPrefix(c, "#") }

// SDDMConf is the greeter theme's theme.conf: the roles Main.qml reads.
func SDDMConf(p Palette) string {
	return "# Written by subcult theme apply-system from the user's palette (ADR 0037).\n[General]\n" +
		"base=" + p.role("base") + "\nsurface=" + p.role("surface0") + "\nborder=" + p.role("mauve") +
		"\nborderInactive=" + p.role("surface1") + "\ntext=" + p.role("text") + "\nmuted=" + p.role("overlay0") +
		"\nsubtext=" + p.role("subtext0") + "\nerror=" + p.role("red") + "\n"
}

// limineKeys are the preamble lines Apply owns, in the order they are added.
var limineKeys = []string{"interface_branding_colour", "term_background", "term_foreground", "term_background_bright", "term_foreground_bright", "term_palette", "term_palette_bright"}

// LimineConf rewrites the colour lines of /boot/limine.conf's preamble (the
// lines before the first entry, which the Limine tools own) and reports
// whether anything changed. Entries and other preamble lines stay as they are.
func LimineConf(existing []byte, p Palette) ([]byte, bool) {
	want := map[string]string{
		"interface_branding_colour": bare(p.role("mauve")),
		"term_background":           "00" + bare(p.role("base")),
		"term_foreground":           bare(p.role("text")),
		"term_background_bright":    bare(p.role("surface0")),
		"term_foreground_bright":    bare(p.role("text")),
	}
	if ansi, ok := ansiPalette(p, 0); ok {
		want["term_palette"] = ansi
	}
	if ansi, ok := ansiPalette(p, 8); ok {
		want["term_palette_bright"] = ansi
	}
	// The Limine tools may end the last entry with blank lines. Keep those
	// bytes so applying the same colours does not rewrite their output.
	content := strings.TrimRight(string(existing), "\n")
	ending := string(existing)[len(content):]
	lines := strings.Split(content, "\n")
	if len(existing) == 0 {
		lines = nil
		ending = "\n"
	}
	firstEntry := len(lines)
	for i, l := range lines {
		if strings.HasPrefix(l, "/") {
			firstEntry = i
			break
		}
	}
	seen := map[string]bool{}
	var out []string
	for i, l := range lines {
		if i < firstEntry {
			key, _, ok := strings.Cut(l, ":")
			key = strings.TrimSpace(key)
			if ok && want[key] != "" {
				seen[key] = true
				out = append(out, key+": "+want[key])
				continue
			}
		}
		if i == firstEntry {
			for _, k := range limineKeys {
				if want[k] != "" && !seen[k] {
					out = append(out, k+": "+want[k])
					seen[k] = true
				}
			}
		}
		out = append(out, l)
	}
	if firstEntry == len(lines) {
		for _, k := range limineKeys {
			if want[k] != "" && !seen[k] {
				out = append(out, k+": "+want[k])
			}
		}
	}
	result := strings.Join(out, "\n") + ending
	return []byte(result), result != string(existing)
}

// ansiPalette is Limine's ";"-separated RRGGBB list of eight ANSI colours
// from the given index, when the palette has them all.
func ansiPalette(p Palette, from int) (string, bool) {
	parts := make([]string, 0, 8)
	for i := from; i < from+8; i++ {
		c, ok := p.Colors["ansi"+strconv.Itoa(i)]
		if !ok {
			return "", false
		}
		parts = append(parts, bare(c))
	}
	return strings.Join(parts, ";"), true
}

var (
	plymouthBackground = regexp.MustCompile(`Window\.SetBackground(Top|Bottom)Color\([^)]*\)`)
	plymouthText       = regexp.MustCompile(`Image\.Text\(text, [^)]*\)`)
	plymouthConsole    = regexp.MustCompile(`(?m)^ConsoleLogBackgroundColor=.*$`)
	plymouthDir        = regexp.MustCompile(`(?m)^(ImageDir|ScriptFile)=.*$`)
	plymouthName       = regexp.MustCompile(`(?m)^Name=.*$`)
)

// rgbFloats is a #rrggbb colour as Plymouth's script takes it: three 0..1
// values with three decimals.
func rgbFloats(c string) (string, error) {
	c = bare(c)
	if len(c) != 6 {
		return "", fmt.Errorf("not a colour: %q", c)
	}
	parts := make([]string, 0, 3)
	for i := 0; i < 6; i += 2 {
		v, err := strconv.ParseUint(c[i:i+2], 16, 8)
		if err != nil {
			return "", err
		}
		parts = append(parts, strconv.FormatFloat(float64(v)/255, 'f', 3, 64))
	}
	return strings.Join(parts, ", "), nil
}

// PlymouthScript recolours the packaged splash script: the background from
// base, the message text from text. Everything else (images, layout) is
// kept, so the user theme follows the packaged one each time apply-system
// runs; nothing rewrites it when the package updates.
func PlymouthScript(packaged []byte, p Palette) ([]byte, error) {
	bg, err := rgbFloats(p.role("base"))
	if err != nil {
		return nil, err
	}
	fg, err := rgbFloats(p.role("text"))
	if err != nil {
		return nil, err
	}
	s := string(packaged)
	if !plymouthBackground.MatchString(s) || !plymouthText.MatchString(s) {
		return nil, errors.New("the packaged Plymouth script has no colour lines to replace")
	}
	s = plymouthBackground.ReplaceAllString(s, "Window.SetBackground${1}Color("+bg+")")
	s = plymouthText.ReplaceAllString(s, "Image.Text(text, "+fg+")")
	return []byte("# Recoloured copy of the Subarchy theme, written by subcult theme apply-system (ADR 0037).\n" + s), nil
}

// PlymouthTheme is the user theme's .plymouth file: the packaged one with
// its name, paths and console colour changed.
func PlymouthTheme(packaged []byte, p Palette, dir string) []byte {
	s := string(packaged)
	s = plymouthName.ReplaceAllString(s, "Name=Subarchy (user palette)")
	s = plymouthDir.ReplaceAllStringFunc(s, func(line string) string {
		if strings.HasPrefix(line, "ImageDir=") {
			return "ImageDir=" + dir
		}
		return "ScriptFile=" + dir + "/subarchy-user.script"
	})
	s = plymouthConsole.ReplaceAllString(s, "ConsoleLogBackgroundColor=0x"+strings.ToUpper(bare(p.role("base"))))
	return []byte(s)
}

// ChromiumPolicy is the managed policy Chromium reads for its frame colour.
func ChromiumPolicy(p Palette) string {
	return `{"BrowserThemeColor": "` + p.role("base") + `", "BrowserColorScheme": "` + p.Appearance + `"}` + "\n"
}

// Paths under the root Apply writes to.
const (
	SDDMThemeDir      = "usr/share/sddm/themes/subarchy"
	LimineConfPath    = "boot/limine.conf"
	PlymouthThemeDir  = "usr/share/plymouth/themes/subarchy"
	PlymouthUserDir   = "usr/share/plymouth/themes/subarchy-user"
	PlymouthDaemon    = "etc/plymouth/plymouthd.conf"
	ChromiumPolicyDir = "etc/chromium/policies/managed"
)

// Report is what Apply did.
type Report struct {
	Written   []string // files written or replaced
	Unchanged []string // files already as wanted
	Skipped   []string // targets not on this system, with the reason
	// PlymouthChanged: the splash theme or its selection changed, so the
	// initramfs must be rebuilt for the change to show at boot.
	PlymouthChanged bool
}

// Apply writes every target under root. A target whose program is not
// installed (no Limine config, no Chromium) is skipped and said so.
func Apply(root string, p Palette) (Report, error) {
	var rep Report
	write := func(rel string, content []byte, mode os.FileMode) (bool, error) {
		full := filepath.Join(root, rel)
		if old, err := os.ReadFile(full); err == nil && string(old) == string(content) {
			rep.Unchanged = append(rep.Unchanged, rel)
			return false, nil
		}
		if err := os.MkdirAll(filepath.Dir(full), 0o755); err != nil {
			return false, err
		}
		tmp := full + ".subcult-tmp"
		if err := os.WriteFile(tmp, content, mode); err != nil {
			return false, err
		}
		if err := os.Rename(tmp, full); err != nil {
			return false, err
		}
		rep.Written = append(rep.Written, rel)
		return true, nil
	}

	// SDDM: the greeter theme's configuration, read at the next greeter start.
	if _, err := os.Stat(filepath.Join(root, SDDMThemeDir, "Main.qml")); err == nil {
		if _, err := write(filepath.Join(SDDMThemeDir, "theme.conf"), []byte(SDDMConf(p)), 0o644); err != nil {
			return rep, err
		}
	} else {
		rep.Skipped = append(rep.Skipped, "SDDM: the Subarchy greeter theme is not installed")
	}

	// Limine: the preamble's colours; the entries are the Limine tools'.
	if existing, err := os.ReadFile(filepath.Join(root, LimineConfPath)); err == nil {
		if content, changed := LimineConf(existing, p); changed {
			if _, err := write(LimineConfPath, content, 0o644); err != nil {
				return rep, err
			}
		} else {
			rep.Unchanged = append(rep.Unchanged, LimineConfPath)
		}
	} else {
		rep.Skipped = append(rep.Skipped, "Limine: no /boot/limine.conf")
	}

	// Plymouth: a recoloured copy of the packaged theme, selected in
	// plymouthd.conf; the images are the packaged ones, linked.
	script, err := os.ReadFile(filepath.Join(root, PlymouthThemeDir, "subarchy.script"))
	theme, err2 := os.ReadFile(filepath.Join(root, PlymouthThemeDir, "subarchy.plymouth"))
	if err == nil && err2 == nil {
		recoloured, err := PlymouthScript(script, p)
		if err != nil {
			return rep, err
		}
		changed, err := write(filepath.Join(PlymouthUserDir, "subarchy-user.script"), recoloured, 0o644)
		if err != nil {
			return rep, err
		}
		rep.PlymouthChanged = rep.PlymouthChanged || changed
		changed, err = write(filepath.Join(PlymouthUserDir, "subarchy-user.plymouth"), PlymouthTheme(theme, p, "/"+PlymouthUserDir), 0o644)
		if err != nil {
			return rep, err
		}
		rep.PlymouthChanged = rep.PlymouthChanged || changed
		images, _ := filepath.Glob(filepath.Join(root, PlymouthThemeDir, "*.png"))
		for _, img := range images {
			link := filepath.Join(root, PlymouthUserDir, filepath.Base(img))
			target := "../subarchy/" + filepath.Base(img)
			if cur, err := os.Readlink(link); err == nil && cur == target {
				continue
			}
			os.Remove(link)
			if err := os.Symlink(target, link); err != nil {
				return rep, err
			}
			rep.Written = append(rep.Written, filepath.Join(PlymouthUserDir, filepath.Base(img)))
			rep.PlymouthChanged = true
		}
		daemon, _ := os.ReadFile(filepath.Join(root, PlymouthDaemon))
		conf := plymouthDaemonConf(string(daemon), "subarchy-user")
		changed, err = write(PlymouthDaemon, []byte(conf), 0o644)
		if err != nil {
			return rep, err
		}
		rep.PlymouthChanged = rep.PlymouthChanged || changed
	} else {
		rep.Skipped = append(rep.Skipped, "Plymouth: the Subarchy splash theme is not installed")
	}

	// Chromium: only where Chromium's configuration directory exists.
	if fi, err := os.Stat(filepath.Join(root, "etc/chromium")); err == nil && fi.IsDir() {
		if _, err := write(filepath.Join(ChromiumPolicyDir, "color.json"), []byte(ChromiumPolicy(p)), 0o644); err != nil {
			return rep, err
		}
	} else {
		rep.Skipped = append(rep.Skipped, "Chromium: not installed (no /etc/chromium)")
	}
	return rep, nil
}

// plymouthDaemonConf sets Theme= in plymouthd.conf, keeping its other lines.
func plymouthDaemonConf(existing, theme string) string {
	lines := strings.Split(strings.TrimRight(existing, "\n"), "\n")
	if strings.TrimSpace(existing) == "" {
		return "[Daemon]\nTheme=" + theme + "\n"
	}
	set := false
	inDaemon := false
	var out []string
	for _, l := range lines {
		t := strings.TrimSpace(l)
		if strings.HasPrefix(t, "[") {
			if inDaemon && !set {
				out = append(out, "Theme="+theme)
				set = true
			}
			inDaemon = t == "[Daemon]"
		}
		if inDaemon && strings.HasPrefix(t, "Theme=") {
			if set {
				continue
			}
			out = append(out, "Theme="+theme)
			set = true
			continue
		}
		out = append(out, l)
	}
	if !set {
		if !inDaemon {
			out = append(out, "[Daemon]")
		}
		out = append(out, "Theme="+theme)
	}
	return strings.Join(out, "\n") + "\n"
}
