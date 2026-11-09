package main

import (
	"bytes"
	"errors"
	"os"
	"path/filepath"
	"strings"
	"testing"

	"git.subcult.tv/subculture-collective/subarchy/internal/systheme"
)

const palette = `{"schema": 1, "appearance": "light", "colors": {"base": "#eff1f5", "text": "#4c4f69", "mauve": "#8839ef"}}`

func newApp(t *testing.T) (*app, *bytes.Buffer, *bytes.Buffer, *[][]string) {
	t.Helper()
	home := t.TempDir()
	var out, errOut bytes.Buffer
	var calls [][]string
	a := &app{stdout: &out, stderr: &errOut, home: home, subcultPath: filepath.Join(home, "system"),
		elevate: func(tool string, args ...string) error {
			calls = append(calls, append([]string{tool}, args...))
			return nil
		},
		initramfs: func() error { return errors.New("mkinitcpio should not run in tests") },
	}
	if err := os.MkdirAll(filepath.Join(home, "system/default/theme"), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(home, "system/default/theme/palette.json"), []byte(`{"colors": {"base": "#100b19", "text": "#f0ece4"}}`), 0o644); err != nil {
		t.Fatal(err)
	}
	return a, &out, &errOut, &calls
}

func TestApplySystemPicksTheUserPaletteAndElevates(t *testing.T) {
	a, out, _, calls := newApp(t)
	if code := a.run([]string{"apply-system", "--dry-run"}); code != 0 {
		t.Fatalf("dry run from the system palette: %d %s", code, out.String())
	}
	if !strings.Contains(out.String(), "system/default/theme/palette.json") || !strings.Contains(out.String(), "base=#100b19,text=#f0ece4") || len(*calls) != 0 {
		t.Errorf("dry run: %s (%v)", out.String(), *calls)
	}
	user := filepath.Join(a.home, ".config/subcult/theme/palette.json")
	os.MkdirAll(filepath.Dir(user), 0o755)
	os.WriteFile(user, []byte(palette), 0o644)
	out.Reset()
	if code := a.run([]string{"apply-system"}); code != 0 {
		t.Fatalf("apply: %d %s", code, out.String())
	}
	if len(*calls) != 1 || (*calls)[0][0] != "pkexec" || (*calls)[0][1] != selfPath || (*calls)[0][2] != "system-apply" || !strings.Contains(strings.Join((*calls)[0], " "), "--colors base=#eff1f5,mauve=#8839ef,text=#4c4f69 --appearance light") {
		t.Errorf("elevation: %v", *calls)
	}
	if code := a.run([]string{"apply-system", "--elevate", "sudo"}); code != 0 || (*calls)[1][0] != "sudo" {
		t.Errorf("sudo elevation: %d %v", code, *calls)
	}
	if code := a.run([]string{"apply-system", "--elevate", "doas"}); code != 2 {
		t.Error("an unknown elevation tool was accepted")
	}
	os.WriteFile(user, []byte(`{"colors": {"base": "url(evil)"}}`), 0o644)
	if code := a.run([]string{"apply-system"}); code != 1 || len(*calls) != 2 {
		t.Error("a bad palette reached the privileged half")
	}
}

func TestSystemApplyWritesUnderRoot(t *testing.T) {
	a, out, errOut, _ := newApp(t)
	root := t.TempDir()
	for rel, c := range map[string]string{
		filepath.Join(systheme.SDDMThemeDir, "Main.qml"): "Rectangle {}\n",
		systheme.LimineConfPath:                          "timeout: 3\n/+Subarchy\n",
	} {
		os.MkdirAll(filepath.Join(root, filepath.Dir(rel)), 0o755)
		os.WriteFile(filepath.Join(root, rel), []byte(c), 0o644)
	}
	if code := a.run([]string{"system-apply", "--root", root, "--colors", "base=#000000,text=#ffffff", "--appearance", "dark"}); code != 0 {
		t.Fatalf("system-apply: %d %s %s", code, out.String(), errOut.String())
	}
	s := out.String()
	if !strings.Contains(s, "wrote /usr/share/sddm/themes/subarchy/theme.conf") || !strings.Contains(s, "wrote /boot/limine.conf") || !strings.Contains(s, "skipped: Plymouth") || !strings.Contains(s, "no initramfs rebuild") {
		t.Errorf("report: %s", s)
	}
	if code := a.run([]string{"system-apply", "--root", root, "--colors", "base=#zzzzzz"}); code != 2 {
		t.Error("a bad colour was accepted by the privileged half")
	}
	if code := a.run([]string{"system-apply", "--root", root}); code != 2 {
		t.Error("no colours was accepted")
	}
}

func TestMetadata(t *testing.T) {
	a, out, _, _ := newApp(t)
	if code := a.run([]string{"--subcult-metadata"}); code != 0 || !strings.Contains(out.String(), `"apply-system"`) || !strings.Contains(out.String(), `"hidden":true`) {
		t.Errorf("metadata: %d %s", code, out.String())
	}
}
