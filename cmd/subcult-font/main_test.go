package main

import (
	"bytes"
	"context"
	"crypto/sha256"
	"encoding/hex"
	"errors"
	"fmt"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strings"
	"testing"

	"git.subcult.tv/subculture-collective/subarchy/internal/font"
)

const (
	nerdLine = "JetBrainsMono Nerd Font\t100\t20-7e 2500-257f e0b0 f015\n"
	propLine = "Noto Sans\t\t20-7e\n"
)

// fakeRunner records commands and answers Output from a table keyed by
// the command's first words.
type fakeRunner struct {
	calls   [][]string
	outputs map[string]string
	fail    map[string]bool
	onRun   func(argv []string)
}

func (f *fakeRunner) key(argv []string) string {
	for n := len(argv); n > 0; n-- {
		k := strings.Join(argv[:n], " ")
		if _, ok := f.outputs[k]; ok {
			return k
		}
		if f.fail[k] {
			return k
		}
	}
	return ""
}

func (f *fakeRunner) Run(_ context.Context, argv ...string) error {
	f.calls = append(f.calls, argv)
	if f.onRun != nil {
		f.onRun(argv)
	}
	if f.fail[f.key(argv)] {
		return errors.New("failed")
	}
	return nil
}

func (f *fakeRunner) Output(_ context.Context, argv ...string) (string, error) {
	f.calls = append(f.calls, argv)
	k := f.key(argv)
	if f.fail[k] {
		return "", errors.New("failed")
	}
	return f.outputs[k], nil
}

func (f *fakeRunner) Has(string) bool { return true }

func (f *fakeRunner) ran(prefix ...string) bool {
	for _, c := range f.calls {
		if len(c) >= len(prefix) && strings.Join(c[:len(prefix)], " ") == strings.Join(prefix, " ") {
			return true
		}
	}
	return false
}

func newEnv(t *testing.T, r *fakeRunner) (env, *bytes.Buffer, *bytes.Buffer) {
	t.Helper()
	var out, errb bytes.Buffer
	return env{home: t.TempDir(), runner: r, stdin: strings.NewReader(""), stdout: &out, stderr: &errb,
		releaseBase: "http://127.0.0.1:1"}, &out, &errb
}

func installedFont(family, line string) *fakeRunner {
	return &fakeRunner{outputs: map[string]string{
		"fc-list -f %{file}\\n " + family + ":": "/fonts/a.ttf\n",
		"fc-query -f " + font.FcQueryFormat + " /fonts/a.ttf": line,
	}}
}

func readRoles(t *testing.T, e env) map[font.Role]string {
	t.Helper()
	data, err := os.ReadFile(confPath(e))
	if err != nil {
		t.Fatal(err)
	}
	roles, err := font.ParseUserConf(string(data))
	if err != nil {
		t.Fatal(err)
	}
	return roles
}

func TestSetWritesRoleAndRefreshes(t *testing.T) {
	r := installedFont("JetBrainsMono Nerd Font", nerdLine)
	e, _, errb := newEnv(t, r)
	if code := run(context.Background(), []string{"set", "JetBrainsMono Nerd Font"}, e); code != 0 {
		t.Fatalf("exit %d: %s", code, errb)
	}
	if got := readRoles(t, e)[font.Mono]; got != "JetBrainsMono Nerd Font" {
		t.Errorf("monospace role = %q", got)
	}
	if !r.ran("fc-cache", "-f") || !r.ran("pkill", "-USR1", "-x", "kitty") {
		t.Errorf("want fc-cache and a kitty reload, got %v", r.calls)
	}
}

func TestSetRefusesInterfaceOnlyForMonospace(t *testing.T) {
	r := installedFont("Noto Sans", propLine)
	e, _, _ := newEnv(t, r)
	if code := run(context.Background(), []string{"set", "Noto Sans"}, e); code != 2 {
		t.Fatalf("exit %d, want 2", code)
	}
	if _, err := os.Stat(confPath(e)); !os.IsNotExist(err) {
		t.Error("role file written after a refusal")
	}
	if code := run(context.Background(), []string{"set", "--force", "Noto Sans"}, e); code != 0 {
		t.Fatalf("--force exit %d", code)
	}
	if code := run(context.Background(), []string{"set", "--ui", "Noto Sans"}, e); code != 0 {
		t.Fatalf("--ui exit %d", code)
	}
	roles := readRoles(t, e)
	if roles[font.Mono] != "Noto Sans" || roles[font.UI] != "Noto Sans" {
		t.Errorf("roles = %v, want both kept", roles)
	}
}

func TestSetUnknownFamilyNotInstalled(t *testing.T) {
	r := &fakeRunner{outputs: map[string]string{}}
	e, _, errb := newEnv(t, r)
	if code := run(context.Background(), []string{"set", "Nonexistent Font"}, e); code != 1 {
		t.Fatalf("exit %d, want 1", code)
	}
	if !strings.Contains(errb.String(), "not installed") {
		t.Errorf("stderr = %q", errb)
	}
}

func TestSetInstallsCatalogueFont(t *testing.T) {
	r := &fakeRunner{outputs: map[string]string{}}
	r.onRun = func(argv []string) {
		if argv[0] == "sudo" {
			r.outputs["fc-list -f %{file}\\n Agave Nerd Font:"] = "/fonts/a.ttf\n"
			r.outputs["fc-query -f "+font.FcQueryFormat+" /fonts/a.ttf"] = nerdLine
		}
	}
	e, _, errb := newEnv(t, r)
	if code := run(context.Background(), []string{"set", "Agave Nerd Font"}, e); code != 0 {
		t.Fatalf("exit %d: %s", code, errb)
	}
	if !r.ran("sudo", "pacman", "-S", "--needed", "ttf-agave-nerd") {
		t.Errorf("want the package installed, got %v", r.calls)
	}
}

func TestInstallRefusesUnknownNames(t *testing.T) {
	for _, name := range []string{"rm -rf /", "../../etc", "NotAFont"} {
		r := &fakeRunner{}
		e, _, _ := newEnv(t, r)
		if code := run(context.Background(), []string{"install", name}, e); code != 2 {
			t.Errorf("install %q exit %d, want 2", name, code)
		}
		if len(r.calls) != 0 {
			t.Errorf("install %q ran %v", name, r.calls)
		}
	}
}

func TestInstallUsesPacmanWhenPackaged(t *testing.T) {
	r := &fakeRunner{}
	e, _, _ := newEnv(t, r)
	if code := run(context.Background(), []string{"install", "firacode"}, e); code != 0 {
		t.Fatalf("exit %d", code)
	}
	if !r.ran("sudo", "pacman", "-S", "--needed", "ttf-firacode-nerd") {
		t.Errorf("calls = %v", r.calls)
	}
}

func releaseServer(t *testing.T, archive []byte, sum string) *httptest.Server {
	t.Helper()
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, req *http.Request) {
		switch req.URL.Path {
		case "/" + font.NerdFontsVersion + "/SHA-256.txt":
			fmt.Fprintf(w, "%s  UbuntuSans.tar.xz\n", sum)
		case "/" + font.NerdFontsVersion + "/UbuntuSans.tar.xz":
			w.Write(archive)
		default:
			http.NotFound(w, req)
		}
	}))
	t.Cleanup(srv.Close)
	return srv
}

func TestInstallReleaseChecksumMismatchLeavesNothing(t *testing.T) {
	srv := releaseServer(t, []byte("archive"), strings.Repeat("0", 64))
	r := &fakeRunner{}
	e, _, _ := newEnv(t, r)
	e.releaseBase = srv.URL
	if code := run(context.Background(), []string{"install", "UbuntuSans"}, e); code != 1 {
		t.Fatalf("exit %d, want 1", code)
	}
	if _, err := os.Stat(filepath.Join(e.home, ".local", "share", "fonts", "nerd-fonts", "UbuntuSans")); !os.IsNotExist(err) {
		t.Error("font folder exists after a checksum mismatch")
	}
	if r.ran("tar") {
		t.Error("unpacked an archive that failed its checksum")
	}
}

func TestInstallReleaseUnpacks(t *testing.T) {
	archive := []byte("archive")
	sum := sha256.Sum256(archive)
	srv := releaseServer(t, archive, hex.EncodeToString(sum[:]))
	r := &fakeRunner{}
	r.onRun = func(argv []string) {
		if argv[0] == "tar" { // simulate unpacking into the -C folder
			dest := argv[len(argv)-1]
			os.WriteFile(filepath.Join(dest, "UbuntuSansNerdFont-Regular.ttf"), []byte("x"), 0o644)
		}
	}
	e, _, errb := newEnv(t, r)
	e.releaseBase = srv.URL
	if code := run(context.Background(), []string{"install", "UbuntuSans"}, e); code != 0 {
		t.Fatalf("exit %d: %s", code, errb)
	}
	if _, err := os.Stat(filepath.Join(e.home, ".local", "share", "fonts", "nerd-fonts", "UbuntuSans", "UbuntuSansNerdFont-Regular.ttf")); err != nil {
		t.Errorf("font not in place: %v", err)
	}
	if !r.ran("fc-cache", "-f") {
		t.Error("no fc-cache after install")
	}
}

func TestCurrentReportsMismatch(t *testing.T) {
	r := &fakeRunner{outputs: map[string]string{
		"fc-match -f %{family[0]} monospace":  "JetBrainsMono Nerd Font",
		"fc-match -f %{family[0]} sans-serif": "JetBrainsMono Nerd Font Propo",
		"fc-match -f %{family[0]} serif":      "Libertinus Mono",
	}}
	e, out, _ := newEnv(t, r)
	os.MkdirAll(filepath.Dir(confPath(e)), 0o755)
	os.WriteFile(confPath(e), []byte(font.RenderUserConf(map[font.Role]string{font.Mono: "Dank Mono"})), 0o644)
	if code := run(context.Background(), []string{"current"}, e); code != 0 {
		t.Fatalf("exit %d", code)
	}
	lines := strings.Split(out.String(), "\n")
	if !strings.Contains(lines[0], "Dank Mono") || !strings.Contains(lines[0], "mismatch") {
		t.Errorf("monospace line = %q, want the configured family and a mismatch", lines[0])
	}
	if strings.Contains(lines[1], "mismatch") {
		t.Errorf("sans-serif line = %q has no configured family, so no mismatch", lines[1])
	}
}

func TestPatchDeclinedDoesNothing(t *testing.T) {
	r := installedFont("Dank Mono", "Dank Mono\t100\t20-7e 2500-257f\n")
	e, out, _ := newEnv(t, r)
	e.stdin = strings.NewReader("n\n")
	if code := run(context.Background(), []string{"patch", "Dank Mono"}, e); code != 0 {
		t.Fatalf("exit %d", code)
	}
	if !strings.Contains(out.String(), "licence") {
		t.Error("no licence warning before the question")
	}
	for _, c := range r.calls {
		if c[0] != "fc-list" {
			t.Errorf("declined patch ran %v", c)
		}
	}
}

func TestImportRejectsNonFonts(t *testing.T) {
	r := &fakeRunner{}
	e, _, _ := newEnv(t, r)
	f := filepath.Join(t.TempDir(), "notes.txt")
	os.WriteFile(f, []byte("x"), 0o644)
	if code := run(context.Background(), []string{"import", f}, e); code != 2 {
		t.Fatalf("exit %d, want 2", code)
	}
}

func TestImportCopiesAndChecks(t *testing.T) {
	src := filepath.Join(t.TempDir(), "DankMono-Regular.otf")
	os.WriteFile(src, []byte("font"), 0o644)
	r := &fakeRunner{outputs: map[string]string{}}
	e, out, errb := newEnv(t, r)
	target := filepath.Join(e.home, ".local", "share", "fonts", "subcult", "DankMono-Regular.otf")
	r.outputs["fc-query -f "+font.FcQueryFormat+" "+target] = "Dank Mono\t100\t20-7e 2500-257f\n"
	if code := run(context.Background(), []string{"import", src}, e); code != 0 {
		t.Fatalf("exit %d: %s", code, errb)
	}
	if _, err := os.Stat(target); err != nil {
		t.Errorf("not copied: %v", err)
	}
	if !strings.Contains(out.String(), "Symbols fallback") {
		t.Errorf("want the verdict printed, got %q", out)
	}
}
