package main

import (
	"bytes"
	"image"
	"image/png"
	"os"
	"path/filepath"
	"strings"
	"testing"

	"git.subcult.tv/subculture-collective/subarchy/internal/systheme"
)

func pngBytes(t *testing.T) []byte {
	t.Helper()
	var b bytes.Buffer
	if err := png.Encode(&b, image.NewRGBA(image.Rect(0, 0, 2, 1))); err != nil {
		t.Fatal(err)
	}
	return b.Bytes()
}

func shipSets(t *testing.T, a *app) {
	t.Helper()
	for rel, data := range map[string][]byte{
		"subarchy/boot.png": pngBytes(t), "subarchy/title.txt": []byte("SUBARCHY\n"),
		"subcult/login.png": pngBytes(t), "subcult/lock.png": pngBytes(t),
	} {
		full := filepath.Join(a.root, systheme.ScreensSystemDir, rel)
		os.MkdirAll(filepath.Dir(full), 0o755)
		if err := os.WriteFile(full, data, 0o644); err != nil {
			t.Fatal(err)
		}
	}
}

func TestScreensShowAndSet(t *testing.T) {
	a, out, errOut, calls := newApp(t)
	shipSets(t, a)
	if code := a.run([]string{"screens"}); code != 0 {
		t.Fatalf("show: %d %s", code, errOut.String())
	}
	for _, want := range []string{"boot   subarchy (default)", "login  subcult (default)", "subarchy     boot, title", "subcult      login, lock"} {
		if !strings.Contains(out.String(), want) {
			t.Errorf("show lacks %q:\n%s", want, out.String())
		}
	}
	out.Reset()
	if code := a.run([]string{"screens", "set", "--boot", "subcult", "--lock", "subarchy"}); code != 0 {
		t.Fatalf("set: %d %s", code, errOut.String())
	}
	if !strings.Contains(out.String(), "subcult has no boot.png") || !strings.Contains(out.String(), "subarchy has no lock.png") {
		t.Errorf("set notes: %s", out.String())
	}
	data, _ := os.ReadFile(a.screensPath())
	if s, err := systheme.ParseScreens(data); err != nil || s != (systheme.Screens{Boot: "subcult", Lock: "subarchy"}) {
		t.Errorf("screens.json: %s %v", data, err)
	}
	if code := a.run([]string{"screens", "set", "--login", "nope"}); code != 1 {
		t.Error("set accepted a set that does not exist")
	}
	if code := a.run([]string{"screens", "set"}); code != 2 {
		t.Error("set without a screen was accepted")
	}
	// apply-system carries the choice to the privileged half.
	if code := a.run([]string{"apply-system"}); code != 0 {
		t.Fatalf("apply: %s", errOut.String())
	}
	if got := strings.Join((*calls)[len(*calls)-1], " "); !strings.Contains(got, "--screens boot=subcult,login=subcult") {
		t.Errorf("elevation: %s", got)
	}
	os.WriteFile(a.screensPath(), []byte(`{"boot": "../x"}`), 0o644)
	if code := a.run([]string{"apply-system"}); code != 1 {
		t.Error("apply-system took a bad screens.json")
	}
}

func TestScreensAdd(t *testing.T) {
	a, out, errOut, _ := newApp(t)
	src := t.TempDir()
	os.WriteFile(filepath.Join(src, "boot.png"), pngBytes(t), 0o644)
	os.WriteFile(filepath.Join(src, "title.txt"), []byte("  MY BOX  \n"), 0o644)
	os.WriteFile(filepath.Join(src, "notes.md"), []byte("ignored"), 0o644)
	if code := a.run([]string{"screens", "add", "mine", src}); code != 0 {
		t.Fatalf("add: %d %s", code, errOut.String())
	}
	title, _ := os.ReadFile(filepath.Join(a.root, systheme.ScreensLocalDir, "mine/title.txt"))
	if string(title) != "MY BOX\n" || !strings.Contains(out.String(), "/etc/subcult/screens/mine/boot.png") {
		t.Errorf("added: %q %s", title, out.String())
	}
	if _, err := os.Stat(filepath.Join(a.root, systheme.ScreensLocalDir, "mine/notes.md")); err == nil {
		t.Error("copied a file that is not art")
	}
	if code := a.run([]string{"screens", "add", "mine", src}); code != 1 {
		t.Error("replaced a set without --replace")
	}
	if code := a.run([]string{"screens", "add", "--replace", "mine", src}); code != 0 {
		t.Errorf("--replace: %s", errOut.String())
	}
	for _, args := range [][]string{{"subcult", src}, {"../x", src}, {"mine"}} {
		if code := a.run(append([]string{"screens", "add"}, args...)); code != 2 {
			t.Errorf("add %v was accepted", args)
		}
	}
	bad := t.TempDir()
	os.WriteFile(filepath.Join(bad, "login.png"), []byte("not a png"), 0o644)
	if code := a.run([]string{"screens", "add", "other", bad}); code != 1 {
		t.Error("added a file that is not a PNG")
	}
	if code := a.run([]string{"screens", "add", "empty", t.TempDir()}); code != 1 {
		t.Error("added an empty set")
	}
	// On the real root, only root may add.
	a.root = "/"
	if code := a.run([]string{"screens", "add", "mine", src}); code != 1 || !strings.Contains(errOut.String(), "sudo") {
		t.Error("a user added a set to /etc")
	}
}
