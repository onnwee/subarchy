package systheme

import (
	"bytes"
	"image"
	"image/color"
	"image/png"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

// tinyPNG is a valid PNG, w pixels wide, so sets can be told apart.
func tinyPNG(t *testing.T, w int) string {
	t.Helper()
	img := image.NewRGBA(image.Rect(0, 0, w, 1))
	img.Set(0, 0, color.RGBA{0, 255, 136, 255})
	var b bytes.Buffer
	if err := png.Encode(&b, img); err != nil {
		t.Fatal(err)
	}
	return b.String()
}

func TestParseScreens(t *testing.T) {
	s, err := ParseScreens([]byte(`{"boot": "subcult", "lock": "mine-2"}`))
	if err != nil || s != (Screens{Boot: "subcult", Lock: "mine-2"}) {
		t.Fatalf("%+v %v", s, err)
	}
	if got := s.WithDefaults(); got != (Screens{Boot: "subcult", Login: "subcult", Lock: "mine-2"}) {
		t.Errorf("defaults: %+v", got)
	}
	for _, bad := range []string{`{"boot": "../etc"}`, `{"boot": "UPPER"}`, `{"bot": "subcult"}`, `{"boot": "a/b"}`, `[]`} {
		if _, err := ParseScreens([]byte(bad)); err == nil {
			t.Errorf("accepted %s", bad)
		}
	}
}

func TestScreensArgs(t *testing.T) {
	if got := (Screens{}).Args(); got != "boot=subarchy,login=subcult" {
		t.Errorf("default args: %s", got)
	}
	s, err := ParseScreensArgs("boot=mine,login=subarchy")
	if err != nil || s.Boot != "mine" || s.Login != "subarchy" {
		t.Errorf("%+v %v", s, err)
	}
	if s, err := ParseScreensArgs(""); err != nil || s != DefaultScreens {
		t.Errorf("empty: %+v %v", s, err)
	}
	for _, bad := range []string{"boot=../x", "lock=subcult", "boot", "boot=a,login=/etc"} {
		if _, err := ParseScreensArgs(bad); err == nil {
			t.Errorf("accepted %q", bad)
		}
	}
}

func TestScreenFileLocalFirstAndRefusals(t *testing.T) {
	root := t.TempDir()
	put := func(rel, content string) {
		full := filepath.Join(root, rel)
		os.MkdirAll(filepath.Dir(full), 0o755)
		if err := os.WriteFile(full, []byte(content), 0o644); err != nil {
			t.Fatal(err)
		}
	}
	put(filepath.Join(ScreensSystemDir, "mine/boot.png"), tinyPNG(t, 1))
	put(filepath.Join(ScreensLocalDir, "mine/boot.png"), tinyPNG(t, 3))
	data, path, ok, err := ScreenFile(root, "mine", "boot.png")
	if err != nil || !ok || path != "/etc/subcult/screens/mine/boot.png" || string(data) != tinyPNG(t, 3) {
		t.Errorf("local first: %q %v %v", path, ok, err)
	}
	if _, _, ok, err := ScreenFile(root, "mine", "login.png"); ok || err != nil {
		t.Errorf("missing file: %v %v", ok, err)
	}
	put(filepath.Join(ScreensSystemDir, "bad/boot.png"), "not a png")
	if _, _, _, err := ScreenFile(root, "bad", "boot.png"); err == nil {
		t.Error("accepted a file that is not a PNG")
	}
	put(filepath.Join(ScreensSystemDir, "bad/title.txt"), "two\nlines")
	if _, _, _, err := ScreenFile(root, "bad", "title.txt"); err == nil {
		t.Error("accepted a two-line title")
	}
	os.MkdirAll(filepath.Join(root, ScreensSystemDir, "link"), 0o755)
	os.Symlink("/etc/shadow", filepath.Join(root, ScreensSystemDir, "link/boot.png"))
	if _, _, _, err := ScreenFile(root, "link", "boot.png"); err == nil || !strings.Contains(err.Error(), "not a regular file") {
		t.Errorf("followed a link: %v", err)
	}
	if _, _, _, err := ScreenFile(root, "../x", "boot.png"); err == nil {
		t.Error("accepted a path as a set name")
	}
	if got := strings.Join(ScreenSets(root), ","); got != "bad,link,mine" {
		t.Errorf("sets: %s", got)
	}
}

func TestApplyScreensChoice(t *testing.T) {
	root := fixtureRoot(t)
	p, _ := ParsePalette([]byte(sample))
	if _, err := Apply(root, p, Screens{}); err != nil {
		t.Fatal(err)
	}
	// SUBCULT at boot too: its set has no boot.png, so the packaged logo
	// comes back as a link, and the boot menu takes its title.
	rep, err := Apply(root, p, Screens{Boot: "subcult"})
	if err != nil {
		t.Fatal(err)
	}
	if !rep.PlymouthChanged {
		t.Errorf("changing the boot set must rebuild the splash: %+v", rep)
	}
	if link, err := os.Readlink(filepath.Join(root, PlymouthUserDir, "logo.png")); err != nil || link != "../subarchy/logo.png" {
		t.Errorf("logo after a set without boot.png: %q %v", link, err)
	}
	limine, _ := os.ReadFile(filepath.Join(root, LimineConfPath))
	if !strings.Contains(string(limine), "interface_branding: SUBCULT // Subarchy\n") || strings.Count(string(limine), "interface_branding:") != 1 {
		t.Errorf("limine: %s", limine)
	}
	// A login set without login.png leaves the logo line out.
	if _, err := Apply(root, p, Screens{Login: "subarchy"}); err != nil {
		t.Fatal(err)
	}
	conf, _ := os.ReadFile(filepath.Join(root, SDDMThemeDir, "theme.conf"))
	if strings.Contains(string(conf), "logo=") || !strings.Contains(string(conf), "logoName=SUBARCHY\n") {
		t.Errorf("sddm without login.png: %s", conf)
	}
	if _, err := Apply(root, p, Screens{Boot: "../../etc"}); err == nil {
		t.Error("Apply took a path as a set name")
	}
}
