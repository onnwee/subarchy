// Package font holds Subarchy's font catalogue, the font check and the
// user's role file (shell and look design, "Fonts"). Three fontconfig
// aliases are the roles; GTK, Qt, the shell and kitty all ask for them.
package font

import "strings"

// Role is a fontconfig alias that Subarchy treats as a font role.
type Role string

// The three roles.
const (
	Mono  Role = "monospace"
	UI    Role = "sans-serif"
	Serif Role = "serif"
)

// Entry is one font in the curated list.
type Entry struct {
	Family       string // as fontconfig reports it
	Package      string
	Roles        []Role
	Preinstalled bool
	Source       string   // "pacman", "aur" or "release"
	Also         []string // other families the same package installs
}

// Families returns the entry's family and the others its package installs.
func (e Entry) Families() []string {
	return append([]string{e.Family}, e.Also...)
}

// Catalog is the owner's list (2026-11-07): seven preinstalled fonts, then
// the choices installed when picked.
func Catalog() []Entry {
	mono := []Role{Mono}
	pre := func(family, pkg string, roles []Role) Entry {
		return Entry{Family: family, Package: pkg, Roles: roles, Preinstalled: true, Source: "pacman"}
	}
	pick := func(family, pkg string, roles []Role, source string) Entry {
		return Entry{Family: family, Package: pkg, Roles: roles, Source: source}
	}
	// otf-monaspace-nerd installs all five Monaspace families.
	monaspace := pick("MonaspiceNe Nerd Font", "otf-monaspace-nerd", mono, "pacman")
	monaspace.Also = []string{"MonaspiceAr Nerd Font", "MonaspiceKr Nerd Font", "MonaspiceRn Nerd Font", "MonaspiceXe Nerd Font"}
	return []Entry{
		pre("JetBrainsMono Nerd Font", "ttf-jetbrains-mono-nerd", mono),
		pre("3270 Nerd Font", "ttf-3270-nerd", mono),
		pre("AdwaitaMono Nerd Font", "ttf-adwaitamono-nerd", mono),
		pre("SpaceMono Nerd Font", "ttf-space-mono-nerd", mono),
		pre("ShureTechMono Nerd Font", "ttf-sharetech-mono-nerd", mono),
		pre("AtkynsonMono Nerd Font", "otf-atkinsonhyperlegiblemono-nerd", mono),
		pre("Libertinus Mono", "otf-libertinus", []Role{Serif}),

		pick("ComicShannsMono Nerd Font", "otf-comicshanns-nerd", mono, "pacman"),
		pick("Agave Nerd Font", "ttf-agave-nerd", mono, "pacman"),
		pick("UbuntuMono Nerd Font", "ttf-ubuntu-mono-nerd", mono, "pacman"),
		pick("CaskaydiaCove Nerd Font", "ttf-cascadia-code-nerd", mono, "pacman"),
		pick("BlexMono Nerd Font", "ttf-ibmplex-mono-nerd", mono, "pacman"),
		pick("VictorMono Nerd Font", "ttf-victor-mono-nerd", mono, "pacman"),
		monaspace,
		pick("IosevkaTerm Nerd Font", "ttf-iosevkaterm-nerd", mono, "pacman"),
		pick("OpenDyslexicM Nerd Font", "otf-opendyslexic-nerd", mono, "pacman"),
		pick("Monofur Nerd Font Mono", "ttf-monofur-nerd", mono, "pacman"),
		pick("ProFont IIx Nerd Font Mono", "ttf-profont-nerd", mono, "pacman"),
		pick("ProggyClean Nerd Font", "ttf-proggyclean-nerd", mono, "pacman"),
		pick("Terminess Nerd Font", "ttf-terminus-nerd", mono, "pacman"),

		pick("Alegreya Sans", "otf-alegreya-sans", []Role{UI}, "aur"),
		pick("Ubuntu Nerd Font", "ttf-ubuntu-nerd", []Role{UI}, "pacman"),
		pick("Alegreya", "otf-alegreya", []Role{Serif}, "aur"),
		pick("Source Serif 4", "adobe-source-serif-fonts", []Role{Serif}, "pacman"),
		pick("Crimson Pro", "otf-crimson-pro", []Role{Serif}, "pacman"),
	}
}

// Find looks a family up in the catalogue, ignoring case. A family that
// an entry's package also installs finds that entry.
func Find(family string) (Entry, bool) {
	for _, e := range Catalog() {
		for _, f := range e.Families() {
			if strings.EqualFold(f, family) {
				return e, true
			}
		}
	}
	return Entry{}, false
}

// FcPattern is a fontconfig pattern that matches the family by name.
// Backslash, '-', ':' and ',' are pattern syntax, so they are escaped.
func FcPattern(family string) string {
	var b strings.Builder
	for _, r := range family {
		if strings.ContainsRune(`\-:,`, r) {
			b.WriteByte('\\')
		}
		b.WriteRune(r)
	}
	return b.String() + ":"
}

// NerdFontsVersion is the Nerd Fonts release `install` and `patch` use.
const NerdFontsVersion = "v3.5.1"

// nerdFamilies maps every release archive name in NerdFontsVersion to its
// Arch package; an empty package means the release archive is the only
// source (checked against `pacman -Sl extra` on 2026-11-07).
var nerdFamilies = []struct{ name, pkg string }{
	{"0xProto", "ttf-0xproto-nerd"}, {"3270", "ttf-3270-nerd"}, {"AdwaitaMono", "ttf-adwaitamono-nerd"},
	{"Agave", "ttf-agave-nerd"}, {"AnnotationMono", "ttf-annotationmono-nerd"}, {"AnonymousPro", "ttf-anonymouspro-nerd"},
	{"Arimo", "ttf-arimo-nerd"}, {"AtkinsonHyperlegibleMono", "otf-atkinsonhyperlegiblemono-nerd"},
	{"AurulentSansMono", "otf-aurulent-nerd"}, {"BigBlueTerminal", "ttf-bigblueterminal-nerd"},
	{"BitstreamVeraSansMono", "ttf-bitstream-vera-mono-nerd"}, {"CascadiaCode", "ttf-cascadia-code-nerd"},
	{"CascadiaMono", "ttf-cascadia-mono-nerd"}, {"CodeNewRoman", "otf-codenewroman-nerd"},
	{"ComicShannsMono", "otf-comicshanns-nerd"}, {"CommitMono", "otf-commit-mono-nerd"}, {"Cousine", "ttf-cousine-nerd"},
	{"D2Coding", "ttf-d2coding-nerd"}, {"DaddyTimeMono", "ttf-daddytime-mono-nerd"}, {"DejaVuSansMono", "ttf-dejavu-nerd"},
	{"DepartureMono", ""}, {"DroidSansMono", "otf-droid-nerd"}, {"EnvyCodeR", "ttf-envycoder-nerd"},
	{"FantasqueSansMono", "ttf-fantasque-nerd"}, {"FiraCode", "ttf-firacode-nerd"}, {"FiraMono", "otf-firamono-nerd"},
	{"GeistMono", "otf-geist-mono-nerd"}, {"Go-Mono", "ttf-go-nerd"}, {"Gohu", "ttf-gohu-nerd"},
	{"GoogleSansCode", "ttf-googlesanscode-nerd"}, {"Hack", "ttf-hack-nerd"}, {"Hasklig", "otf-hasklig-nerd"},
	{"HeavyData", "ttf-heavydata-nerd"}, {"Hermit", "otf-hermit-nerd"}, {"iA-Writer", "ttf-iawriter-nerd"},
	{"IBMPlexMono", "ttf-ibmplex-mono-nerd"}, {"Inconsolata", "ttf-inconsolata-nerd"},
	{"InconsolataGo", "ttf-inconsolata-go-nerd"}, {"InconsolataLGC", "ttf-inconsolata-lgc-nerd"},
	{"IntelOneMono", "ttf-intone-nerd"}, {"Iosevka", "ttf-iosevka-nerd"}, {"IosevkaTerm", "ttf-iosevkaterm-nerd"},
	{"IosevkaTermSlab", "ttf-iosevkatermslab-nerd"}, {"JetBrainsMono", "ttf-jetbrains-mono-nerd"},
	{"Lekton", "ttf-lekton-nerd"}, {"LiberationMono", "ttf-liberation-mono-nerd"}, {"Lilex", "ttf-lilex-nerd"},
	{"MartianMono", "ttf-martian-mono-nerd"}, {"Meslo", "ttf-meslo-nerd"}, {"Monaspace", "otf-monaspace-nerd"},
	{"Monofur", "ttf-monofur-nerd"}, {"Monoid", "ttf-monoid-nerd"}, {"Mononoki", "ttf-mononoki-nerd"},
	{"MPlus", "ttf-mplus-nerd"}, {"NerdFontsSymbolsOnly", "ttf-nerd-fonts-symbols"}, {"Noto", "ttf-noto-nerd"},
	{"OpenDyslexic", "otf-opendyslexic-nerd"}, {"Overpass", "otf-overpass-nerd"}, {"ProFont", "ttf-profont-nerd"},
	{"ProggyClean", "ttf-proggyclean-nerd"}, {"Recursive", "ttf-recursive-nerd"}, {"RobotoMono", "ttf-roboto-mono-nerd"},
	{"ShareTechMono", "ttf-sharetech-mono-nerd"}, {"SourceCodePro", "ttf-sourcecodepro-nerd"},
	{"SpaceMono", "ttf-space-mono-nerd"}, {"Terminus", "ttf-terminus-nerd"}, {"Tinos", "ttf-tinos-nerd"},
	{"Ubuntu", "ttf-ubuntu-nerd"}, {"UbuntuMono", "ttf-ubuntu-mono-nerd"}, {"UbuntuSans", ""},
	{"VictorMono", "ttf-victor-mono-nerd"}, {"ZedMono", "ttf-zed-mono-nerd"},
}

// NerdFamilies lists the release archive names, in release order.
func NerdFamilies() []string {
	out := make([]string, len(nerdFamilies))
	for i, f := range nerdFamilies {
		out[i] = f.name
	}
	return out
}

// NerdPackage returns the Arch package for a release name (any case), or
// false when the release archive is the only source or the name is unknown.
func NerdPackage(name string) (string, bool) {
	for _, f := range nerdFamilies {
		if strings.EqualFold(f.name, name) {
			return f.pkg, f.pkg != ""
		}
	}
	return "", false
}

// IsNerdFamily reports whether name is a release archive name (any case)
// and returns its canonical spelling.
func IsNerdFamily(name string) (string, bool) {
	for _, f := range nerdFamilies {
		if strings.EqualFold(f.name, name) {
			return f.name, true
		}
	}
	return "", false
}
