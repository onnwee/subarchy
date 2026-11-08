package apps

import (
	"strings"
	"testing"
)

func TestWebappID(t *testing.T) {
	for in, want := range map[string]string{"Google Maps": "google-maps", "HEY": "hey", "  X  ": "x", "a/b c": "a-b-c", "Ünïcode!": "n-code"} {
		got, err := WebappID(in)
		if err != nil || got != want {
			t.Errorf("WebappID(%q) = %q, %v; want %q", in, got, err, want)
		}
	}
	for _, bad := range []string{"", "/", "---", "   "} {
		if _, err := WebappID(bad); err == nil {
			t.Errorf("WebappID(%q) must fail", bad)
		}
	}
}

func TestNormalizeURL(t *testing.T) {
	for in, want := range map[string]string{"maps.google.com": "https://maps.google.com", "http://x.test/a": "http://x.test/a", " https://discord.com/channels/@me ": "https://discord.com/channels/@me"} {
		got, err := NormalizeURL(in)
		if err != nil || got != want {
			t.Errorf("NormalizeURL(%q) = %q, %v; want %q", in, got, err, want)
		}
	}
	for _, bad := range []string{"", "not a url", "ftp://x.test", "javascript:alert(1)", "file:///etc/passwd", "https://"} {
		if _, err := NormalizeURL(bad); err == nil {
			t.Errorf("NormalizeURL(%q) must fail", bad)
		}
	}
}

func TestWMClassMatchesOmarchyEntry(t *testing.T) {
	// Omarchy 4.5's Discord.desktop carries this class for the same URL.
	if got := WMClass("https://discord.com/channels/@me"); got != "chrome-discord.com__channels_@me-Default" {
		t.Errorf("WMClass = %q", got)
	}
	if got := WMClass("https://maps.google.com"); got != "chrome-maps.google.com_-Default" {
		t.Errorf("WMClass = %q", got)
	}
}

func TestWebappPlan(t *testing.T) {
	steps, err := WebappPlan("/apps", "/icons", "Google Maps", "maps.google.com", "")
	if err != nil || len(steps) != 1 {
		t.Fatalf("steps = %v, %v", steps, err)
	}
	if steps[0].Path != "/apps/google-maps.desktop" {
		t.Errorf("path = %q", steps[0].Path)
	}
	for _, want := range []string{"Name=Google Maps\n", "Exec=chromium --app=https://maps.google.com\n", "Icon=web-browser\n", "StartupWMClass=chrome-maps.google.com_-Default\n", "Type=Application\n"} {
		if !strings.Contains(steps[0].Content, want) {
			t.Errorf("entry lacks %q:\n%s", want, steps[0].Content)
		}
	}
	withIcon, err := WebappPlan("/apps", "/icons", "Maps", "https://maps.google.com", "/tmp/maps.svg")
	if err != nil || len(withIcon) != 2 {
		t.Fatalf("steps = %v, %v", withIcon, err)
	}
	if got := strings.Join(withIcon[0].Argv, " "); got != "install -Dm644 /tmp/maps.svg /icons/hicolor/256x256/apps/maps.svg" {
		t.Errorf("icon step = %q", got)
	}
	if !strings.Contains(withIcon[1].Content, "Icon=maps\n") {
		t.Error("the entry must use the installed icon")
	}
	if _, err := WebappPlan("/apps", "/icons", "Bad", "not a url", ""); err == nil {
		t.Error("a bad URL must fail")
	}
	remove, err := WebappRemovePlan("/apps", "/icons", "Google Maps")
	if err != nil || len(remove) != 1 || remove[0].Argv[2] != "/apps/google-maps.desktop" {
		t.Errorf("remove = %v, %v", remove, err)
	}
}

func TestDiscordEntryMatchesTheCatalogue(t *testing.T) {
	// applications/discord.desktop is what WebappDesktop would write for
	// the catalogue's Discord, with its own icon.
	got := WebappDesktop("Discord", "https://discord.com/channels/@me", "discord")
	for _, want := range []string{"Exec=chromium --app=https://discord.com/channels/@me\n", "StartupWMClass=chrome-discord.com__channels_@me-Default\n", "Icon=discord\n"} {
		if !strings.Contains(got, want) {
			t.Errorf("lacks %q", want)
		}
	}
}
