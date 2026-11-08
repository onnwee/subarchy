package main

import (
	"bytes"
	"encoding/json"
	"os"
	"path/filepath"
	"strings"
	"testing"

	"git.subcult.tv/subculture-collective/subarchy/internal/apps"
	"git.subcult.tv/subculture-collective/subarchy/internal/dispatch"
)

type harness struct {
	cli    *cli
	out    *bytes.Buffer
	errOut *bytes.Buffer
	ran    []string
	paths  apps.Paths
}

func newHarness(t *testing.T) *harness {
	t.Helper()
	config := filepath.Join(t.TempDir(), "config")
	h := &harness{out: &bytes.Buffer{}, errOut: &bytes.Buffer{}}
	h.paths = apps.Paths{
		System:       "../../default/apps.toml",
		User:         filepath.Join(config, "subcult", "apps.toml"),
		Defaults:     filepath.Join(config, "subcult", "defaults.toml"),
		Applications: "/home/u/.local/share/applications",
		Icons:        "/home/u/.local/share/icons",
	}
	h.cli = &cli{
		stdout: h.out,
		stderr: h.errOut,
		paths:  func() (apps.Paths, error) { return h.paths, nil },
		run: func(s apps.Step) error {
			h.ran = append(h.ran, s.String())
			return nil
		},
	}
	return h
}

func (h *harness) run(args ...string) int {
	h.out.Reset()
	h.errOut.Reset()
	h.ran = nil
	return h.cli.main(args)
}

func TestMetadata(t *testing.T) {
	h := newHarness(t)
	if code := h.run(dispatch.MetadataFlag); code != 0 {
		t.Fatalf("exit %d", code)
	}
	var got []dispatch.Described
	if err := json.Unmarshal(h.out.Bytes(), &got); err != nil {
		t.Fatal(err)
	}
	if len(got) != len(routes) || got[0].Words[0] != "app" {
		t.Errorf("metadata = %+v", got)
	}
}

func TestCommands(t *testing.T) {
	tests := []struct {
		args    []string
		code    int
		out     string // substring of stdout
		errOut  string // substring of stderr
		ran     string // joined steps run
		noSteps bool
	}{
		{args: nil, out: "Usage: subcult app"},
		{args: []string{"list"}, out: "kitty"},
		{args: []string{"list", "--role", "browser"}, out: "browser*"},
		{args: []string{"list", "--role", "nope"}, code: 1, errOut: "no apps for role"},
		{args: []string{"show", "vlc"}, out: "media-player\n"},
		{args: []string{"show", "nope"}, code: 1, errOut: `no app "nope"`},
		{args: []string{"install", "steam", "--dry-run"}, out: "sudo pacman -S --needed steam", noSteps: true},
		{args: []string{"install", "steam"}, ran: "sudo pacman -S --needed steam"},
		{args: []string{"install", "discord", "--dry-run"}, out: "write /home/u/.local/share/applications/discord.desktop", noSteps: true},
		{args: []string{"remove", "discord", "--dry-run"}, out: "rm -f /home/u/.local/share/applications/discord.desktop", noSteps: true},
		{args: []string{"webapp", "install", "Google Maps", "maps.google.com", "--dry-run"}, out: "write /home/u/.local/share/applications/google-maps.desktop", noSteps: true},
		{args: []string{"webapp", "install", "Maps", "https://maps.google.com", "--icon", "/tmp/maps.png", "--dry-run"}, out: "install -Dm644 /tmp/maps.png /home/u/.local/share/icons/hicolor/256x256/apps/maps.png\nwrite /home/u/.local/share/applications/maps.desktop", noSteps: true},
		{args: []string{"webapp", "remove", "Maps", "-n"}, out: "rm -f /home/u/.local/share/applications/maps.desktop", noSteps: true},
		{args: []string{"webapp", "install", "Bad", "not a url"}, code: 1, errOut: "whitespace"},
		{args: []string{"webapp", "install", "Bad"}, code: 2, errOut: "needs a name and a URL"},
		{args: []string{"webapp", "frob", "x"}, code: 2, errOut: "unknown action"},
		{args: []string{"remove", "-n", "lutris"}, out: "sudo pacman -Rns lutris", noSteps: true},
		{args: []string{"install"}, code: 2, errOut: "at least one app"},
		{args: []string{"default"}, out: "browser"},
		{args: []string{"default", "browser"}, out: "* zen"},
		{args: []string{"default", "browser", "chromium", "--dry-run"}, out: "xdg-settings set default-web-browser chromium.desktop", noSteps: true},
		{args: []string{"default", "browser", "kitty"}, code: 1, errOut: "cannot be the browser"},
		{args: []string{"validate"}, out: "catalogue ok"},
		{args: []string{"validate", "../../default/apps.toml"}, out: "ok"},
		{args: []string{"frobnicate"}, code: 2, errOut: "unknown subcommand"},
		{args: []string{"list", "--bogus"}, code: 2, errOut: "unknown option"},
	}
	for _, tt := range tests {
		t.Run(strings.Join(tt.args, " "), func(t *testing.T) {
			h := newHarness(t)
			code := h.run(tt.args...)
			if code != tt.code {
				t.Fatalf("exit %d, want %d; stderr: %s", code, tt.code, h.errOut)
			}
			if tt.out != "" && tt.code == 0 && !strings.Contains(h.out.String(), tt.out) {
				t.Errorf("stdout lacks %q:\n%s", tt.out, h.out)
			}
			if tt.errOut != "" && !strings.Contains(h.errOut.String(), tt.errOut) {
				t.Errorf("stderr lacks %q:\n%s", tt.errOut, h.errOut)
			}
			if tt.ran != "" && strings.Join(h.ran, "; ") != tt.ran {
				t.Errorf("ran %q, want %q", h.ran, tt.ran)
			}
			if tt.noSteps && len(h.ran) > 0 {
				t.Errorf("dry run executed %q", h.ran)
			}
		})
	}
}

func TestSetDefaultPersists(t *testing.T) {
	h := newHarness(t)
	if code := h.run("default", "terminal", "wezterm"); code != 0 {
		t.Fatalf("exit %d: %s", code, h.errOut)
	}
	want := "write " + filepath.Join(filepath.Dir(filepath.Dir(h.paths.Defaults)), "xdg-terminals.list") + ": org.wezfurlong.wezterm.desktop"
	if len(h.ran) != 1 || h.ran[0] != want {
		t.Errorf("ran %q, want %q", h.ran, want)
	}
	if _, err := os.Stat(h.paths.Defaults); err != nil {
		t.Fatal(err)
	}
	h.run("default", "terminal")
	if !strings.Contains(h.out.String(), "* wezterm") {
		t.Errorf("default not persisted:\n%s", h.out)
	}
}
