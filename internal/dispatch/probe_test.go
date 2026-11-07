package dispatch

import (
	"fmt"
	"io"
	"os"
	"path/filepath"
	"reflect"
	"testing"
)

// fakeEnv makes the test binary act as a compiled subcult command.
const fakeEnv = "SUBCULT_DISPATCH_FAKE"

func TestMain(m *testing.M) {
	if os.Getenv(fakeEnv) == "1" && len(os.Args) > 1 && os.Args[1] == MetadataFlag {
		fmt.Print(`[
		  {"words":["app","list"],"summary":"List apps"},
		  {"words":["app","install"],"summary":"Install an app","requires_sudo":true},
		  {"words":["theme","set"],"summary":"Not mine"}
		]`)
		os.Exit(0)
	}
	os.Exit(m.Run())
}

func copyExe(t *testing.T, dst string) {
	t.Helper()
	src, err := os.Executable()
	if err != nil {
		t.Fatal(err)
	}
	in, err := os.Open(src)
	if err != nil {
		t.Fatal(err)
	}
	defer in.Close()
	out, err := os.OpenFile(dst, os.O_CREATE|os.O_WRONLY, 0o755)
	if err != nil {
		t.Fatal(err)
	}
	if _, err := io.Copy(out, in); err != nil {
		t.Fatal(err)
	}
	if err := out.Close(); err != nil {
		t.Fatal(err)
	}
}

func TestCompiledCommandRoutes(t *testing.T) {
	t.Setenv(fakeEnv, "1")
	dir := t.TempDir()
	copyExe(t, filepath.Join(dir, "subcult-app"))
	reg, err := Discover([]string{dir})
	if err != nil {
		t.Fatal(err)
	}
	cmds := reg.Commands(false)
	if len(cmds) != 2 {
		t.Fatalf("want 2 routes (the out-of-group one dropped), got %+v", cmds)
	}
	c, rest, ok := reg.Resolve([]string{"app", "install", "zen"})
	if !ok {
		t.Fatal("app install did not resolve")
	}
	if c.Binary != "subcult-app" || !reflect.DeepEqual(c.ArgPrefix, []string{"install"}) || !reflect.DeepEqual(rest, []string{"zen"}) || !c.RequiresSudo {
		t.Fatalf("got %+v rest %v", c, rest)
	}
	var argv []string
	app := &App{Registry: reg, Stdout: io.Discard, Stderr: io.Discard, Exec: func(_ string, a []string) error { argv = a; return nil }}
	if code := app.Run([]string{"app", "list", "--json"}); code != 0 {
		t.Fatalf("code %d", code)
	}
	if want := []string{"subcult-app", "list", "--json"}; !reflect.DeepEqual(argv, want) {
		t.Fatalf("argv %v, want %v", argv, want)
	}
}

func TestCompiledCommandWithoutMetadata(t *testing.T) {
	dir := t.TempDir()
	copyExe(t, filepath.Join(dir, "subcult-tool")) // fakeEnv unset: probe fails
	reg, err := Discover([]string{dir})
	if err != nil {
		t.Fatal(err)
	}
	if c, _, ok := reg.Resolve([]string{"tool"}); !ok || c.Summary != "" || len(c.ArgPrefix) != 0 {
		t.Fatalf("want a plain entry, got %+v ok=%v", c, ok)
	}
}
