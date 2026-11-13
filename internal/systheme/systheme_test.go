package systheme

import (
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

const sample = `{"schema": 1, "name": "dracula", "appearance": "dark", "colors": {"base": "#282A36", "text": "#f8f8f2", "mauve": "#bd93f9", "surface0": "#3d454f",
 "ansi0": "#21222c", "ansi1": "#ff5555", "ansi2": "#50fa7b", "ansi3": "#f1fa8c", "ansi4": "#bd93f9", "ansi5": "#ff79c6", "ansi6": "#8be9fd", "ansi7": "#f8f8f2",
 "ansi8": "#6272a4", "ansi9": "#ff6e6e", "ansi10": "#69ff94", "ansi11": "#ffffa5", "ansi12": "#d6acff", "ansi13": "#ff92df", "ansi14": "#a4ffff", "ansi15": "#ffffff"}}`

func TestParsePaletteAndArgs(t *testing.T) {
	p, err := ParsePalette([]byte(sample))
	if err != nil {
		t.Fatal(err)
	}
	if p.Colors["base"] != "#282a36" || p.Appearance != "dark" {
		t.Errorf("parsed: %+v", p)
	}
	back, err := ParseArgs(p.Args(), p.Appearance)
	if err != nil {
		t.Fatal(err)
	}
	if back.Args() != p.Args() || back.Colors["mauve"] != "#bd93f9" {
		t.Errorf("args round trip: %s", back.Args())
	}
	for _, bad := range []string{`{"colors": {"base": "red"}}`, `{"colors": {"base": "#12345"}}`, `{"colors": {"Base;": "#123456"}}`, `{"colors": {}}`, `nope`} {
		if _, err := ParsePalette([]byte(bad)); err == nil {
			t.Errorf("accepted %s", bad)
		}
	}
	for _, bad := range []string{"", "base", "base=red", "base=#123456;rm", "ba se=#123456"} {
		if _, err := ParseArgs(bad, "dark"); err == nil {
			t.Errorf("accepted args %q", bad)
		}
	}
	light, _ := ParsePalette([]byte(`{"theme": {"appearance": "light"}, "colors": {"base": "#ffffff"}}`))
	if light.Appearance != "light" {
		t.Error("appearance under theme not read")
	}
}

func TestSDDMConfAndFallback(t *testing.T) {
	p, _ := ParsePalette([]byte(sample))
	conf := SDDMConf(p)
	if !strings.Contains(conf, "base=#282a36\n") || !strings.Contains(conf, "border=#bd93f9\n") {
		t.Errorf("sddm conf: %s", conf)
	}
	if !strings.Contains(conf, "error=#d52032\n") {
		t.Errorf("a role the theme lacks must come from subcult-minimal: %s", conf)
	}
}

func TestLimineConf(t *testing.T) {
	p, _ := ParsePalette([]byte(sample))
	existing := "timeout: 3\ndefault_entry: 2\nserial: yes\ninterface_branding: SUBCULT // Subarchy\ninterface_branding_colour: 8b5cf6\n\n/+Subarchy\n    //linux-zen\n        protocol: linux\n"
	got, changed := LimineConf([]byte(existing), p)
	s := string(got)
	if !changed {
		t.Fatal("no change reported")
	}
	for _, want := range []string{"interface_branding_colour: bd93f9\n", "term_background: 00282a36\n", "term_foreground: f8f8f2\n",
		"term_palette: 21222c;ff5555;50fa7b;f1fa8c;bd93f9;ff79c6;8be9fd;f8f8f2\n", "term_palette_bright: 6272a4;"} {
		if !strings.Contains(s, want) {
			t.Errorf("missing %q in\n%s", want, s)
		}
	}
	if !strings.HasSuffix(s, "/+Subarchy\n    //linux-zen\n        protocol: linux\n") || strings.Count(s, "interface_branding_colour") != 1 {
		t.Errorf("entries or the branding line were disturbed:\n%s", s)
	}
	if strings.Index(s, "term_palette") > strings.Index(s, "/+Subarchy") {
		t.Error("colour lines landed below the first entry")
	}
	again, changed := LimineConf(got, p)
	if changed || string(again) != s {
		t.Error("a second pass must change nothing")
	}
	// No ANSI roles: the palettes are left out; an empty file gets a preamble.
	small, _ := ParsePalette([]byte(`{"colors": {"base": "#101010"}}`))
	got, _ = LimineConf(nil, small)
	if strings.Contains(string(got), "term_palette") || !strings.Contains(string(got), "term_background: 00101010\n") {
		t.Errorf("small palette: %s", got)
	}
}

func fixtureRoot(t *testing.T) string {
	t.Helper()
	root := t.TempDir()
	files := map[string]string{
		filepath.Join(SDDMThemeDir, "Main.qml"):              "Rectangle {}\n",
		LimineConfPath:                                       "timeout: 3\ninterface_branding_colour: 8b5cf6\n/+Subarchy\n",
		filepath.Join(PlymouthThemeDir, "subarchy.script"):   "Window.SetBackgroundTopColor(0.063, 0.043, 0.098);\nWindow.SetBackgroundBottomColor(0.063, 0.043, 0.098);\nfun message_callback(text) {\n  local.image = Image.Text(text, 0.941, 0.925, 0.894);\n}\n",
		filepath.Join(PlymouthThemeDir, "subarchy.plymouth"): "[Plymouth Theme]\nName=Subarchy\nModuleName=script\n\n[script]\nImageDir=/usr/share/plymouth/themes/subarchy\nScriptFile=/usr/share/plymouth/themes/subarchy/subarchy.script\nConsoleLogBackgroundColor=0x100B19\n",
		filepath.Join(PlymouthThemeDir, "logo.png"):          "png",
		PlymouthDaemon:       "[Daemon]\nTheme=subarchy\nShowDelay=0\n",
		"etc/chromium/.keep": "",
	}
	for rel, c := range files {
		full := filepath.Join(root, rel)
		if err := os.MkdirAll(filepath.Dir(full), 0o755); err != nil {
			t.Fatal(err)
		}
		if err := os.WriteFile(full, []byte(c), 0o644); err != nil {
			t.Fatal(err)
		}
	}
	return root
}

func TestApply(t *testing.T) {
	root := fixtureRoot(t)
	p, _ := ParsePalette([]byte(sample))
	rep, err := Apply(root, p)
	if err != nil {
		t.Fatal(err)
	}
	if !rep.PlymouthChanged || len(rep.Skipped) != 0 {
		t.Errorf("first apply: %+v", rep)
	}
	read := func(rel string) string {
		b, err := os.ReadFile(filepath.Join(root, rel))
		if err != nil {
			t.Fatalf("%s: %v", rel, err)
		}
		return string(b)
	}
	if !strings.Contains(read(filepath.Join(SDDMThemeDir, "theme.conf")), "base=#282a36") {
		t.Error("sddm theme.conf")
	}
	if !strings.Contains(read(LimineConfPath), "term_palette: 21222c") || !strings.HasSuffix(read(LimineConfPath), "/+Subarchy\n") {
		t.Errorf("limine: %s", read(LimineConfPath))
	}
	script := read(filepath.Join(PlymouthUserDir, "subarchy-user.script"))
	if !strings.Contains(script, "SetBackgroundTopColor(0.157, 0.165, 0.212)") || !strings.Contains(script, "Image.Text(text, 0.973, 0.973, 0.949)") {
		t.Errorf("plymouth script: %s", script)
	}
	theme := read(filepath.Join(PlymouthUserDir, "subarchy-user.plymouth"))
	if !strings.Contains(theme, "ScriptFile=/usr/share/plymouth/themes/subarchy-user/subarchy-user.script") || !strings.Contains(theme, "ConsoleLogBackgroundColor=0x282A36") || !strings.Contains(theme, "ImageDir=/usr/share/plymouth/themes/subarchy-user\n") {
		t.Errorf("plymouth theme: %s", theme)
	}
	if link, err := os.Readlink(filepath.Join(root, PlymouthUserDir, "logo.png")); err != nil || link != "../subarchy/logo.png" {
		t.Errorf("image link: %q %v", link, err)
	}
	if read(PlymouthDaemon) != "[Daemon]\nTheme=subarchy-user\nShowDelay=0\n" {
		t.Errorf("plymouthd.conf: %q", read(PlymouthDaemon))
	}
	if read(filepath.Join(ChromiumPolicyDir, "color.json")) != `{"BrowserThemeColor": "#282a36", "BrowserColorScheme": "dark"}`+"\n" {
		t.Errorf("chromium: %s", read(filepath.Join(ChromiumPolicyDir, "color.json")))
	}
	// The same palette again: nothing written, no initramfs.
	rep, err = Apply(root, p)
	if err != nil {
		t.Fatal(err)
	}
	if len(rep.Written) != 0 || rep.PlymouthChanged {
		t.Errorf("second apply: %+v", rep)
	}
	// Another theme's base changes the splash; the images stay links.
	other, _ := ParsePalette([]byte(`{"colors": {"base": "#000000"}}`))
	rep, _ = Apply(root, other)
	if !rep.PlymouthChanged || !strings.Contains(read(filepath.Join(PlymouthUserDir, "subarchy-user.script")), "SetBackgroundTopColor(0.000, 0.000, 0.000)") {
		t.Errorf("third apply: %+v", rep)
	}
}

func TestApplySkipsAbsentTargets(t *testing.T) {
	root := t.TempDir()
	p, _ := ParsePalette([]byte(sample))
	rep, err := Apply(root, p)
	if err != nil {
		t.Fatal(err)
	}
	if len(rep.Written) != 0 || len(rep.Skipped) != 4 || rep.PlymouthChanged {
		t.Errorf("bare root: %+v", rep)
	}
}

func TestPlymouthDaemonConf(t *testing.T) {
	cases := map[string]string{
		"":                                  "[Daemon]\nTheme=subarchy-user\n",
		"[Daemon]\nTheme=subarchy\n":        "[Daemon]\nTheme=subarchy-user\n",
		"[Daemon]\nShowDelay=0\n":           "[Daemon]\nShowDelay=0\nTheme=subarchy-user\n",
		"[Other]\nx=1\n":                    "[Other]\nx=1\n[Daemon]\nTheme=subarchy-user\n",
		"[Daemon]\nTheme=a\nTheme=b\n[X]\n": "[Daemon]\nTheme=subarchy-user\n[X]\n",
	}
	for in, want := range cases {
		if got := plymouthDaemonConf(in, "subarchy-user"); got != want {
			t.Errorf("%q: got %q want %q", in, got, want)
		}
	}
}

func TestLimineConfKeepsEntryTrailingWhitespace(t *testing.T) {
	p, err := ParsePalette([]byte(`{"colors":{"base":"#112233","text":"#ffeedd","mauve":"#abcdef","surface0":"#334455"}}`))
	if err != nil {
		t.Fatal(err)
	}
	preamble := "interface_branding_colour: abcdef\nterm_background: 00112233\nterm_foreground: ffeedd\nterm_background_bright: 334455\nterm_foreground_bright: ffeedd\n"
	for _, ending := range []string{"", "\n", "\n\n", "\n\n\n"} {
		t.Run(fmt.Sprintf("trailing-newlines-%d", len(ending)), func(t *testing.T) {
			existing := preamble + "/+Subarchy\n    //linux-zen\n        protocol: linux" + ending
			got, changed := LimineConf([]byte(existing), p)
			if changed || string(got) != existing {
				t.Fatalf("an already themed config was rewritten: got %q, want %q", got, existing)
			}
		})
	}
}

// The packaged splash script: every text image goes through the one
// recolourable Image.Text(text, ...) call, so a user palette reaches the
// passphrase label and the wrong-passphrase line too; the prompt keeps its
// label, its failure line and its bullet cap.
func TestPackagedPlymouthScript(t *testing.T) {
	packaged, err := os.ReadFile(filepath.Join("..", "..", "default", "plymouth", "subarchy.script"))
	if err != nil {
		t.Fatal(err)
	}
	s := string(packaged)
	if all, recolourable := strings.Count(s, "Image.Text("), len(plymouthText.FindAllString(s, -1)); all != 1 || recolourable != 1 {
		t.Errorf("want one Image.Text call, of the form Image.Text(text, ...); found %d, %d recolourable", all, recolourable)
	}
	for _, want := range []string{
		`paper_text("Disk passphrase")`,
		`paper_text("That passphrase didn't work. Try again.")`,
		"local.image = paper_text(text);",
		"if (bullets > dialog.capacity)",
	} {
		if !strings.Contains(s, want) {
			t.Errorf("the script lost %q", want)
		}
	}
	p, _ := ParsePalette([]byte(sample))
	out, err := PlymouthScript(packaged, p)
	if err != nil {
		t.Fatal(err)
	}
	if !strings.Contains(string(out), "Image.Text(text, 0.973, 0.973, 0.949)") || strings.Contains(string(out), "0.941, 0.925, 0.894") {
		t.Errorf("the text colour was not replaced everywhere:\n%s", out)
	}
}
