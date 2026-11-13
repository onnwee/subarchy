package font

import (
	"os"
	"path/filepath"
	"regexp"
	"strings"
	"testing"
)

func TestCatalogMatchesSpec(t *testing.T) {
	var pre, monoChoices, otherChoices int
	seen := map[string]bool{}
	for _, e := range Catalog() {
		if seen[e.Family] {
			t.Errorf("family %q listed twice", e.Family)
		}
		seen[e.Family] = true
		if e.Package == "" || len(e.Roles) == 0 {
			t.Errorf("%q lacks a package or a role", e.Family)
		}
		switch {
		case e.Preinstalled:
			pre++
		case hasRole(e, Mono):
			monoChoices++
		default:
			otherChoices++
		}
	}
	if pre != 7 || monoChoices != 13 || otherChoices != 5 {
		t.Errorf("catalogue has %d preinstalled, %d monospace choices, %d other choices; spec says 7, 13, 5",
			pre, monoChoices, otherChoices)
	}
	for _, fam := range []string{"JetBrainsMono Nerd Font", "Libertinus Mono", "Terminess Nerd Font", "Alegreya Sans"} {
		if _, ok := Find(fam); !ok {
			t.Errorf("Find(%q) failed", fam)
		}
	}
	if _, ok := Find("jetbrainsmono nerd font"); !ok {
		t.Error("Find should ignore case")
	}
}

func TestNerdFamilies(t *testing.T) {
	names := NerdFamilies()
	if len(names) != 72 {
		t.Fatalf("got %d Nerd Fonts families, %s has 72", len(names), NerdFontsVersion)
	}
	pkg := regexp.MustCompile(`^(ttf|otf)-[a-z0-9-]+-nerd$|^ttf-nerd-fonts-symbols$`)
	release := 0
	for _, n := range names {
		p, ok := NerdPackage(n)
		if !ok {
			release++
			continue
		}
		if !pkg.MatchString(p) {
			t.Errorf("%s maps to %q", n, p)
		}
	}
	if release != 2 {
		t.Errorf("%d families have no Arch package; DepartureMono and UbuntuSans are the two", release)
	}
}

func fixture(t *testing.T, name string) FontInfo {
	t.Helper()
	data, err := os.ReadFile(filepath.Join("testdata", name))
	if err != nil {
		t.Fatal(err)
	}
	infos, err := ParseFcQuery(string(data))
	if err != nil {
		t.Fatal(err)
	}
	if len(infos) != 1 {
		t.Fatalf("%s: got %d faces", name, len(infos))
	}
	return infos[0]
}

func TestParseFcQuery(t *testing.T) {
	fi := fixture(t, "jetbrains-nerd.txt")
	if fi.Family != "JetBrainsMono Nerd Font" || fi.Spacing != 100 {
		t.Errorf("got %q spacing %d", fi.Family, fi.Spacing)
	}
	if !fi.Has('A') || !fi.Has(0xE0B0) || fi.Has(0x10FFFF) {
		t.Error("charset ranges parsed wrongly")
	}
	if proportional := fixture(t, "noto-sans.txt"); proportional.Spacing != 0 {
		t.Errorf("empty spacing should read as 0, got %d", proportional.Spacing)
	}
}

func TestParseFcQueryErrors(t *testing.T) {
	for name, in := range map[string]string{
		"no tabs":       "JetBrainsMono Nerd Font 100 20-7e\n",
		"bad spacing":   "Font\tmono\t20-7e\n",
		"bad charset":   "Font\t100\t20-zz\n",
		"reversed span": "Font\t100\t7e-20\n",
	} {
		t.Run(name, func(t *testing.T) {
			if _, err := ParseFcQuery(in); err == nil {
				t.Error("want an error")
			}
		})
	}
}

func TestCheck(t *testing.T) {
	tests := map[string]Verdict{
		"jetbrains-nerd.txt":   FullNerd,
		"dejavu-sans-mono.txt": FallbackIcons,
		"liberation-mono.txt":  BreaksTUI,
		"noto-sans.txt":        InterfaceOnly,
	}
	for file, want := range tests {
		t.Run(file, func(t *testing.T) {
			if got := Check(fixture(t, file)); got != want {
				t.Errorf("Check = %v, want %v", got, want)
			}
		})
	}
}

func TestVerdictString(t *testing.T) {
	want := map[Verdict]string{
		FullNerd:      "full Nerd Font",
		FallbackIcons: "works, icons from the Symbols fallback",
		InterfaceOnly: "interface text only (not monospace)",
		BreaksTUI:     "breaks terminal UIs (no box drawing)",
	}
	for v, s := range want {
		if v.String() != s {
			t.Errorf("%d.String() = %q, want %q", v, v.String(), s)
		}
	}
}

func TestUserConfRoundTrip(t *testing.T) {
	in := UserConf{
		Roles:   map[Role]string{Mono: "Dank Mono", UI: "Dank Mono", Serif: "Alegreya"},
		Follows: map[Role]bool{UI: true},
	}
	xml := RenderUserConf(in)
	if !strings.Contains(xml, `mode="prepend"`) || strings.Contains(xml, "prepend_first") {
		t.Error("the user file must insert before the generic name (prepend), not first")
	}
	got, err := ParseUserConf(xml)
	if err != nil {
		t.Fatal(err)
	}
	if len(got.Roles) != 3 || got.Roles[Mono] != "Dank Mono" || got.Roles[Serif] != "Alegreya" {
		t.Errorf("roles came back as %v", got.Roles)
	}
	if !got.Follows[UI] || got.Follows[Mono] || got.Follows[Serif] {
		t.Errorf("follows came back as %v, want only the interface role", got.Follows)
	}
	if _, err := ParseUserConf("<fontconfig><match>"); err == nil {
		t.Error("want an error for broken XML")
	}
}

func TestRenderUserConfEscapes(t *testing.T) {
	xml := RenderUserConf(UserConf{Roles: map[Role]string{Mono: `A & <B>`}})
	got, err := ParseUserConf(xml)
	if err != nil {
		t.Fatal(err)
	}
	if got.Roles[Mono] != `A & <B>` {
		t.Errorf("family came back as %q", got.Roles[Mono])
	}
}

func TestUserConfPath(t *testing.T) {
	if UserConfPath != ".config/subcult/fonts.conf" {
		t.Errorf("UserConfPath = %s; the system roles file includes subcult/fonts.conf from XDG_CONFIG_HOME", UserConfPath)
	}
}

func TestCatalogUsesMonoBuildsWhereFacesDiffer(t *testing.T) {
	for _, fam := range []string{"ProFont IIx Nerd Font Mono", "Monofur Nerd Font Mono"} {
		if _, ok := Find(fam); !ok {
			t.Errorf("%s missing; the plain family has proportional faces", fam)
		}
	}
}

// otf-monaspace-nerd installs five families; each finds the package
// (#4 Phase B M9).
func TestFindEveryMonaspaceFamily(t *testing.T) {
	for _, fam := range []string{"Ar", "Kr", "Ne", "Rn", "Xe"} {
		e, ok := Find("Monaspice" + fam + " Nerd Font")
		if !ok || e.Package != "otf-monaspace-nerd" {
			t.Errorf("Monaspice%s Nerd Font: %+v %v", fam, e, ok)
		}
	}
}

func TestFcPattern(t *testing.T) {
	for in, want := range map[string]string{
		"JetBrainsMono Nerd Font": "JetBrainsMono Nerd Font:",
		"Go-Mono":                 `Go\-Mono:`,
		`A,B:C\D`:                 `A\,B\:C\\D:`,
	} {
		if got := FcPattern(in); got != want {
			t.Errorf("FcPattern(%q) = %q, want %q", in, got, want)
		}
	}
}

func hasRole(e Entry, r Role) bool {
	for _, x := range e.Roles {
		if x == r {
			return true
		}
	}
	return false
}
