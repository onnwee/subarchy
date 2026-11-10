package cursor

import (
	"context"
	"os"
	"path/filepath"
	"strings"
	"testing"

	"git.subcult.tv/subculture-collective/subarchy/internal/cursor/cursortest"
)

// shapeDir holds one shape whose hotspot does not divide evenly at 24 px.
func shapeDir(t *testing.T) string {
	t.Helper()
	src := t.TempDir()
	writeFile(t, filepath.Join(src, "shapes.tsv"), "default\t13\t3\tleft_ptr\n")
	writeFile(t, filepath.Join(src, "default.svg"), `<svg xmlns="http://www.w3.org/2000/svg"/>`)
	return src
}

func buildInto(t *testing.T, tools *cursortest.Tools, out string) error {
	t.Helper()
	return Build(context.Background(), tools, BuildOptions{Src: shapeDir(t), Out: out, Fill: "#A78BFA", Line: "#06040A"})
}

func TestBuildRoundsXcursorHotspots(t *testing.T) {
	tools := &cursortest.Tools{}
	if err := buildInto(t, tools, filepath.Join(t.TempDir(), ThemeName)); err != nil {
		t.Fatal(err)
	}
	// 13/32 of 24 px is 9.75 and 3/32 is 2.25: 10 and 2, not 9 and 2.
	for _, want := range []string{"24 10 2 ", "32 13 3 ", "48 20 5 "} {
		if !strings.Contains(tools.Configs["default"], want) {
			t.Errorf("xcursorgen config lacks %q:\n%s", want, tools.Configs["default"])
		}
	}
}

func TestFailedBuildKeepsPreviousTheme(t *testing.T) {
	for _, failing := range []string{"rsvg-convert", "xcursorgen", "hyprcursor-util"} {
		t.Run(failing, func(t *testing.T) {
			parent := t.TempDir()
			out := filepath.Join(parent, ThemeName)
			if err := os.MkdirAll(out, 0o755); err != nil {
				t.Fatal(err)
			}
			writeFile(t, filepath.Join(out, "index.theme"), "previous")
			if err := buildInto(t, &cursortest.Tools{Fail: failing}, out); err == nil {
				t.Fatal("want the build to fail")
			}
			if data, _ := os.ReadFile(filepath.Join(out, "index.theme")); string(data) != "previous" {
				t.Errorf("previous theme changed: %q", data)
			}
			if entries, _ := os.ReadDir(parent); len(entries) != 1 {
				t.Errorf("scratch folders left beside the theme: %v", entries)
			}
		})
	}
}

func TestSwapPutsTheOldThemeBackWhenTheNewOneCannotMoveIn(t *testing.T) {
	dir := t.TempDir()
	dst, old := filepath.Join(dir, "theme"), filepath.Join(dir, "old")
	if err := os.MkdirAll(dst, 0o755); err != nil {
		t.Fatal(err)
	}
	writeFile(t, filepath.Join(dst, "index.theme"), "previous")
	if err := swap(filepath.Join(dir, "missing"), dst, old); err == nil {
		t.Fatal("want an error when the new theme is missing")
	}
	if data, _ := os.ReadFile(filepath.Join(dst, "index.theme")); string(data) != "previous" {
		t.Errorf("the old theme is not back in place: %q", data)
	}
}
