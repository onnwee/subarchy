package apps

import (
	"strings"
	"testing"
)

func TestInstallAndRemovePlans(t *testing.T) {
	tests := []struct {
		app             App
		install, remove string
		wantErr         bool
	}{
		{app: App{ID: "a", Source: SourceRepo, Packages: []string{"vlc", "vlc-plugin-ffmpeg"}},
			install: "sudo pacman -S --needed vlc vlc-plugin-ffmpeg", remove: "sudo pacman -Rns vlc vlc-plugin-ffmpeg"},
		{app: App{ID: "b", Source: SourceAUR, Packages: []string{"zen-browser-bin"}},
			install: "sudo pacman -S --needed zen-browser-bin", remove: "sudo pacman -Rns zen-browser-bin"},
		{app: App{ID: "c", Source: SourceMise, Packages: []string{"node@lts", "go"}},
			install: "mise use --global node@lts go", remove: "mise unuse --global node@lts; mise unuse --global go"},
		{app: App{ID: "d", Source: SourceFlatpak, Packages: []string{"org.example.App"}},
			install: "flatpak install --user flathub org.example.App", remove: "flatpak uninstall --user org.example.App"},
		{app: App{ID: "e", Source: SourceWebapp, URL: "https://example.com"}, wantErr: true},
		{app: App{ID: "f", Source: SourceBuild, Packages: []string{"x"}}, wantErr: true},
	}
	join := func(steps []Step) string {
		s := make([]string, len(steps))
		for i, st := range steps {
			s[i] = st.String()
		}
		return strings.Join(s, "; ")
	}
	for _, tt := range tests {
		t.Run(string(tt.app.Source), func(t *testing.T) {
			in, err := InstallPlanAt(tt.app, Paths{})
			if (err != nil) != tt.wantErr {
				t.Fatalf("install err = %v", err)
			}
			rm, err := RemovePlanAt(tt.app, Paths{})
			if (err != nil) != tt.wantErr {
				t.Fatalf("remove err = %v", err)
			}
			if tt.wantErr {
				return
			}
			if got := join(in); got != tt.install {
				t.Errorf("install = %q, want %q", got, tt.install)
			}
			if got := join(rm); got != tt.remove {
				t.Errorf("remove = %q, want %q", got, tt.remove)
			}
		})
	}
}

func TestDefaultPlan(t *testing.T) {
	kitty := App{ID: "kitty", Roles: []string{"terminal"}, Desktop: "kitty.desktop"}
	zen := App{ID: "zen", Roles: []string{"browser"}, Desktop: "zen.desktop"}
	cliamp := App{ID: "cliamp", Roles: []string{"music-player"}}
	noDesktop := App{ID: "x", Roles: []string{"pdf-viewer"}}

	steps, err := DefaultPlan("terminal", kitty, "/c")
	if err != nil || len(steps) != 1 || steps[0].Path != "/c/xdg-terminals.list" || steps[0].Content != "kitty.desktop\n" {
		t.Errorf("terminal: %v %v", steps, err)
	}
	steps, err = DefaultPlan("browser", zen, "/c")
	if err != nil || len(steps) != 2 || !strings.HasPrefix(steps[0].String(), "xdg-mime default zen.desktop x-scheme-handler/http") ||
		steps[1].String() != "xdg-settings set default-web-browser zen.desktop" {
		t.Errorf("browser: %v %v", steps, err)
	}
	if steps, err := DefaultPlan("music-player", cliamp, "/c"); err != nil || len(steps) != 0 {
		t.Errorf("music-player: %v %v", steps, err)
	}
	if _, err := DefaultPlan("browser", kitty, "/c"); err == nil {
		t.Error("kitty as browser should fail")
	}
	if _, err := DefaultPlan("pdf-viewer", noDesktop, "/c"); err == nil {
		t.Error("pdf-viewer without desktop should fail")
	}
	if got := mimeTypes["pdf-viewer"]; len(got) != 1 || got[0] != "application/pdf" {
		t.Errorf("mimeTypes = %v", got)
	}
}
