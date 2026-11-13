// Command subcult-font serves `subcult font ...` (shell and look design,
// "Fonts"): it points the three font roles at families, installs any Nerd
// Font, imports fonts the user owns, checks fonts and, on request, patches
// a copy with Nerd Font glyphs.
package main

import (
	"archive/zip"
	"bufio"
	"bytes"
	"context"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"errors"
	"flag"
	"fmt"
	"io"
	"net/http"
	"os"
	"path/filepath"
	"slices"
	"strings"
	"time"

	"git.subcult.tv/subculture-collective/subarchy/internal/atomicfile"
	"git.subcult.tv/subculture-collective/subarchy/internal/dispatch"
	"git.subcult.tv/subculture-collective/subarchy/internal/font"
	"git.subcult.tv/subculture-collective/subarchy/internal/update"
)

// fontPatcherSHA256 is the digest GitHub publishes for FontPatcher.zip in
// font.NerdFontsVersion (read 2026-11-07).
const fontPatcherSHA256 = "42bcb32145499a35732274c7fc48deb434ad0d2e0e118f98527c1479c6fa251a"

const releaseBase = "https://github.com/ryanoasis/nerd-fonts/releases/download"

var routes = []dispatch.Described{
	{Words: []string{"font", "list"}, Metadata: dispatch.Metadata{
		Summary: "List the curated fonts, what is installed and what each role uses", Args: "[--all]",
		Examples: []string{"subcult font list", "subcult font list --all"}}},
	{Words: []string{"font", "current"}, Metadata: dispatch.Metadata{
		Summary: "Show the family behind each font role", Examples: []string{"subcult font current"}}},
	{Words: []string{"font", "set"}, Metadata: dispatch.Metadata{
		Summary: "Use a font for the terminal and shell (or --ui, --serif)", Args: "<family> [--ui|--serif] [--force]", RequiresSudo: true,
		Examples: []string{`subcult font set "SpaceMono Nerd Font"`, `subcult font set --serif "Source Serif 4"`}}},
	{Words: []string{"font", "install"}, Metadata: dispatch.Metadata{
		Summary: "Install a curated font or any Nerd Font", Args: "<name>", RequiresSudo: true,
		Examples: []string{"subcult font install FiraCode", "subcult font install UbuntuSans"}}},
	{Words: []string{"font", "import"}, Metadata: dispatch.Metadata{
		Summary: "Add font files you own for your user", Args: "<files...>",
		Examples: []string{"subcult font import ~/Downloads/DankMono/*.otf"}}},
	{Words: []string{"font", "check"}, Metadata: dispatch.Metadata{
		Summary: "Check whether a font works in the terminal and shell", Args: "<family>",
		Examples: []string{`subcult font check "Dank Mono"`}}},
	{Words: []string{"font", "patch"}, Metadata: dispatch.Metadata{
		Summary: "Make a copy of a font with Nerd Font icons", Args: "<family>", RequiresSudo: true,
		Examples: []string{`subcult font patch "Dank Mono"`}}},
}

type env struct {
	home           string
	runner         update.Runner
	stdin          io.Reader
	stdout, stderr io.Writer
	releaseBase    string
	http           *http.Client
}

func main() {
	home, _ := os.UserHomeDir()
	e := env{home: home, stdin: os.Stdin, stdout: os.Stdout, stderr: os.Stderr, releaseBase: releaseBase,
		runner: update.ExecRunner{Stdin: os.Stdin, Stdout: os.Stdout, Stderr: os.Stderr}}
	os.Exit(run(context.Background(), os.Args[1:], e))
}

// errUsage marks mistakes in what the user asked for (exit 2).
var errUsage = errors.New("usage")

func run(ctx context.Context, args []string, e env) int {
	if len(args) == 1 && args[0] == dispatch.MetadataFlag {
		if err := json.NewEncoder(e.stdout).Encode(routes); err != nil {
			return 1
		}
		return 0
	}
	if e.http == nil {
		e.http = &http.Client{Timeout: 2 * time.Minute}
	}
	if len(args) == 0 {
		fmt.Fprintln(e.stderr, "Usage: subcult font list | current | set | install | import | check | patch")
		return 2
	}
	fs := flag.NewFlagSet("subcult font "+args[0], flag.ContinueOnError)
	fs.SetOutput(e.stderr)
	all := fs.Bool("all", false, "also list every Nerd Fonts family")
	ui := fs.Bool("ui", false, "set the interface font (sans-serif)")
	serif := fs.Bool("serif", false, "set the serif font")
	force := fs.Bool("force", false, "use a font the check advises against")
	// Flags may come before or after the family name.
	var flagArgs, rest []string
	for _, a := range args[1:] {
		if strings.HasPrefix(a, "-") && len(a) > 1 {
			flagArgs = append(flagArgs, a)
		} else {
			rest = append(rest, a)
		}
	}
	if err := fs.Parse(flagArgs); err != nil {
		return 2
	}
	if *ui && *serif {
		fmt.Fprintln(e.stderr, "subcult font: choose --ui or --serif, not both")
		return 2
	}

	var err error
	switch args[0] {
	case "current", "set", "import", "check", "patch":
		err = needFontconfig(e)
	}
	if err != nil {
		fmt.Fprintf(e.stderr, "subcult font: %v\n", err)
		return 1
	}
	switch args[0] {
	case "list":
		err = list(ctx, e, *all)
	case "current":
		err = current(ctx, e)
	case "set":
		role := font.Mono
		if *ui {
			role = font.UI
		} else if *serif {
			role = font.Serif
		}
		err = withOneName(rest, func(n string) error { return set(ctx, e, n, role, *force) })
	case "install":
		err = withOneName(rest, func(n string) error { return install(ctx, e, n) })
	case "import":
		err = importFonts(ctx, e, rest)
	case "check":
		err = withOneName(rest, func(n string) error { return check(ctx, e, n) })
	case "patch":
		err = withOneName(rest, func(n string) error { return patch(ctx, e, n) })
	default:
		err = fmt.Errorf("%w: unknown command %q", errUsage, args[0])
	}
	if err == nil {
		return 0
	}
	fmt.Fprintf(e.stderr, "subcult font: %v\n", err)
	if errors.Is(err, errUsage) {
		return 2
	}
	return 1
}

// needFontconfig fails when a fontconfig tool is missing, so that is not
// reported as a font that is not installed.
func needFontconfig(e env) error {
	var missing []string
	for _, t := range []string{"fc-list", "fc-match", "fc-query", "fc-cache"} {
		if !e.runner.Has(t) {
			missing = append(missing, t)
		}
	}
	if len(missing) > 0 {
		return fmt.Errorf("%s not found; install the fontconfig package", strings.Join(missing, ", "))
	}
	return nil
}

func withOneName(rest []string, fn func(string) error) error {
	if len(rest) != 1 || strings.TrimSpace(rest[0]) == "" {
		return fmt.Errorf("%w: give one font name (quote names with spaces)", errUsage)
	}
	return fn(rest[0])
}

func confPath(e env) string {
	return filepath.Join(e.home, font.UserConfPath)
}

// loadConf reads the role file. A missing file is an empty one; the
// error is for a file that cannot be read or parsed.
func loadConf(e env) (font.UserConf, error) {
	empty := font.UserConf{Roles: map[font.Role]string{}, Follows: map[font.Role]bool{}}
	data, err := os.ReadFile(confPath(e))
	if errors.Is(err, os.ErrNotExist) {
		return empty, nil
	}
	if err != nil {
		return empty, err
	}
	c, err := font.ParseUserConf(string(data))
	if err != nil {
		return empty, err
	}
	return c, nil
}

// loadConfOrWarn is loadConf for the commands that only show the roles: a
// broken file is reported on stderr and the roles show as defaults.
func loadConfOrWarn(e env) font.UserConf {
	c, err := loadConf(e)
	if err != nil {
		fmt.Fprintf(e.stderr, "subcult font: %s cannot be read (%v); showing the defaults\n", confPath(e), err)
	}
	return c
}

func resolved(ctx context.Context, e env, r font.Role) string {
	out, err := e.runner.Output(ctx, "fc-match", "-f", "%{family[0]}", string(r))
	if err != nil {
		return "?"
	}
	return strings.TrimSpace(out)
}

func current(ctx context.Context, e env) error {
	conf := loadConfOrWarn(e).Roles
	for _, r := range []font.Role{font.Mono, font.UI, font.Serif} {
		got := resolved(ctx, e, r)
		want, ok := conf[r]
		switch {
		case !ok:
			fmt.Fprintf(e.stdout, "%-11s (default)  resolves to %s\n", r, got)
		case !strings.EqualFold(want, got):
			fmt.Fprintf(e.stdout, "%-11s %s  resolves to %s  mismatch: is it installed?\n", r, want, got)
		default:
			fmt.Fprintf(e.stdout, "%-11s %s\n", r, want)
		}
	}
	return nil
}

func list(ctx context.Context, e env, all bool) error {
	conf := loadConfOrWarn(e).Roles
	inUse := map[string]bool{}
	for _, r := range []font.Role{font.Mono, font.UI, font.Serif} {
		if f, ok := conf[r]; ok {
			inUse[strings.ToLower(f)] = true
		} else {
			inUse[strings.ToLower(resolved(ctx, e, r))] = true
		}
	}
	installed := map[string]bool{}
	if out, err := e.runner.Output(ctx, "pacman", "-Qq"); err == nil {
		for _, p := range strings.Fields(out) {
			installed[p] = true
		}
	}
	// A family can be installed outside pacman (imported, or from a
	// release archive), so one fontconfig knows counts as installed too.
	known := map[string]bool{}
	if out, err := e.runner.Output(ctx, "fc-list", ":", "family"); err == nil {
		for _, l := range strings.Split(out, "\n") {
			for _, f := range strings.Split(l, ",") {
				if f = strings.TrimSpace(f); f != "" {
					known[strings.ToLower(f)] = true
				}
			}
		}
	}
	for _, en := range font.Catalog() {
		roles := make([]string, len(en.Roles))
		for i, r := range en.Roles {
			roles[i] = string(r)
		}
		for _, fam := range en.Families() {
			state := "available"
			if installed[en.Package] || known[strings.ToLower(fam)] {
				state = "installed"
			}
			mark := " "
			if inUse[strings.ToLower(fam)] {
				mark = "*"
			}
			fmt.Fprintf(e.stdout, "%s %-28s %-11s %s\n", mark, fam, strings.Join(roles, ","), state)
		}
	}
	if all {
		fmt.Fprintf(e.stdout, "\nNerd Fonts %s (subcult font install <name>):\n", font.NerdFontsVersion)
		for _, n := range font.NerdFamilies() {
			fmt.Fprintf(e.stdout, "  %s\n", n)
		}
	}
	return nil
}

// faces returns the files of an installed family.
func faces(ctx context.Context, e env, family string) []string {
	out, err := e.runner.Output(ctx, "fc-list", "-f", `%{file}\n`, font.FcPattern(family))
	if err != nil {
		return nil
	}
	var files []string
	for _, l := range strings.Split(out, "\n") {
		if l = strings.TrimSpace(l); l != "" {
			files = append(files, l)
		}
	}
	return files
}

func verdictOf(ctx context.Context, e env, file string) (font.FontInfo, font.Verdict, error) {
	out, err := e.runner.Output(ctx, "fc-query", "-f", font.FcQueryFormat, file)
	if err != nil {
		return font.FontInfo{}, 0, err
	}
	infos, err := font.ParseFcQuery(out)
	if err != nil || len(infos) == 0 {
		return font.FontInfo{}, 0, fmt.Errorf("cannot read %s", file)
	}
	return infos[0], font.Check(infos[0]), nil
}

func set(ctx context.Context, e env, family string, role font.Role, force bool) error {
	// Rewriting a file that did not parse would keep only the new role.
	c, err := loadConf(e)
	if err != nil {
		return fmt.Errorf("%s cannot be read (%v); fix or delete it", confPath(e), err)
	}
	files := faces(ctx, e, family)
	if len(files) == 0 {
		en, ok := font.Find(family)
		if !ok {
			return fmt.Errorf("%s is not installed; `subcult font install` or `subcult font import` it first", family)
		}
		if err := pacmanInstall(ctx, e, en.Package); err != nil {
			return err
		}
		if files = faces(ctx, e, family); len(files) == 0 {
			return fmt.Errorf("%s is still not installed after installing %s", family, en.Package)
		}
	}
	// A family's faces can differ (Monofur's bold is proportional): judge it
	// by its best face, and store fontconfig's own spelling of the family.
	info, v, err := bestFace(ctx, e, files)
	if err != nil {
		return err
	}
	if role == font.Mono && (v == font.InterfaceOnly || v == font.BreaksTUI) && !force {
		return fmt.Errorf("%s: %s; use --force to set it anyway", info.Family, v)
	}
	c.Roles[role] = info.Family
	switch role {
	case font.UI:
		c.Follows[font.UI] = false
	case font.Mono:
		// The interface follows monospace unless it was set on its own.
		if _, set := c.Roles[font.UI]; !set || c.Follows[font.UI] {
			c.Roles[font.UI] = info.Family
			if len(faces(ctx, e, info.Family+" Propo")) > 0 {
				c.Roles[font.UI] = info.Family + " Propo"
			}
			c.Follows[font.UI] = true
		}
	}
	if err := writeAtomic(confPath(e), []byte(font.RenderUserConf(c))); err != nil {
		return err
	}
	if err := e.runner.Run(ctx, "fc-cache", "-f"); err != nil {
		return err
	}
	_ = e.runner.Run(ctx, "pkill", "-USR1", "-x", "kitty") // no kitty running is fine
	fmt.Fprintf(e.stdout, "%s: %s (%s)\n", role, info.Family, v)
	return nil
}

func bestFace(ctx context.Context, e env, files []string) (font.FontInfo, font.Verdict, error) {
	var best font.FontInfo
	bestV := font.Verdict(-1)
	var firstErr error
	for _, f := range files {
		info, v, err := verdictOf(ctx, e, f)
		if err != nil {
			if firstErr == nil {
				firstErr = err
			}
			continue
		}
		if bestV < 0 || v < bestV {
			best, bestV = info, v
		}
	}
	if bestV < 0 {
		return font.FontInfo{}, 0, firstErr
	}
	return best, bestV, nil
}

func pacmanInstall(ctx context.Context, e env, pkg string) error {
	return e.runner.Run(ctx, "sudo", "pacman", "-S", "--needed", pkg)
}

func install(ctx context.Context, e env, name string) error {
	if en, ok := font.Find(name); ok {
		return pacmanInstall(ctx, e, en.Package)
	}
	canonical, ok := font.IsNerdFamily(name)
	if !ok {
		return fmt.Errorf("%w: %q is not in the font list or Nerd Fonts %s (see `subcult font list --all`)",
			errUsage, name, font.NerdFontsVersion)
	}
	if pkg, ok := font.NerdPackage(canonical); ok {
		return pacmanInstall(ctx, e, pkg)
	}
	return installRelease(ctx, e, canonical)
}

func installRelease(ctx context.Context, e env, name string) error {
	base := filepath.Join(e.home, ".local", "share", "fonts", "nerd-fonts")
	if err := os.MkdirAll(base, 0o755); err != nil {
		return err
	}
	tmp, err := os.MkdirTemp(base, ".install-")
	if err != nil {
		return err
	}
	defer os.RemoveAll(tmp)

	sums, err := fetch(ctx, e, "SHA-256.txt")
	if err != nil {
		return err
	}
	file := name + ".tar.xz"
	want := ""
	for _, l := range strings.Split(string(sums), "\n") {
		if f := strings.Fields(l); len(f) == 2 && f[1] == file {
			want = f[0]
		}
	}
	if want == "" {
		return fmt.Errorf("no checksum for %s in the %s release", file, font.NerdFontsVersion)
	}
	archive, err := fetch(ctx, e, file)
	if err != nil {
		return err
	}
	if got := sha256.Sum256(archive); hex.EncodeToString(got[:]) != want {
		return fmt.Errorf("%s does not match its published checksum; nothing installed", file)
	}
	archivePath := filepath.Join(tmp, file)
	if err := os.WriteFile(archivePath, archive, 0o644); err != nil {
		return err
	}
	unpacked := filepath.Join(tmp, "unpacked")
	if err := os.Mkdir(unpacked, 0o755); err != nil {
		return err
	}
	if err := e.runner.Run(ctx, "tar", "-xJf", archivePath, "-C", unpacked); err != nil {
		return err
	}
	final := filepath.Join(base, name)
	if err := os.RemoveAll(final); err != nil {
		return err
	}
	if err := os.Rename(unpacked, final); err != nil {
		return err
	}
	if err := e.runner.Run(ctx, "fc-cache", "-f"); err != nil {
		return err
	}
	fmt.Fprintf(e.stdout, "Installed %s into %s\n", name, final)
	return nil
}

func fetch(ctx context.Context, e env, file string) ([]byte, error) {
	url := strings.TrimRight(e.releaseBase, "/") + "/" + font.NerdFontsVersion + "/" + file
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, url, nil)
	if err != nil {
		return nil, err
	}
	resp, err := e.http.Do(req)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		return nil, fmt.Errorf("%s: %s", url, resp.Status)
	}
	return io.ReadAll(io.LimitReader(resp.Body, 512<<20))
}

var fontExt = map[string]bool{".ttf": true, ".otf": true, ".ttc": true}

func importFonts(ctx context.Context, e env, files []string) error {
	if len(files) == 0 {
		return fmt.Errorf("%w: give the font files to import", errUsage)
	}
	seen := map[string]string{}
	for _, f := range files {
		if !fontExt[strings.ToLower(filepath.Ext(f))] {
			return fmt.Errorf("%w: %s is not a .ttf, .otf or .ttc file", errUsage, f)
		}
		base := filepath.Base(f)
		if prev, ok := seen[base]; ok {
			return fmt.Errorf("%w: %s and %s have the same file name; rename one", errUsage, prev, f)
		}
		seen[base] = f
	}
	dir := filepath.Join(e.home, ".local", "share", "fonts", "subcult")
	// Every file is read and checked before any is copied, so a file
	// fontconfig cannot read never lands in the font directory and a
	// different font is never replaced.
	type imported struct {
		target string
		data   []byte
		info   font.FontInfo
		v      font.Verdict
	}
	var todo []imported
	for _, f := range files {
		data, err := os.ReadFile(f)
		if err != nil {
			return err
		}
		info, v, err := verdictOf(ctx, e, f)
		if err != nil {
			return fmt.Errorf("fontconfig cannot read %s (%v); nothing imported", f, err)
		}
		t := filepath.Join(dir, filepath.Base(f))
		if old, err := os.ReadFile(t); err == nil && !bytes.Equal(old, data) {
			return fmt.Errorf("%s already holds a different file; delete it or rename %s; nothing imported", t, f)
		}
		todo = append(todo, imported{t, data, info, v})
	}
	if err := os.MkdirAll(dir, 0o755); err != nil {
		return err
	}
	for _, im := range todo {
		if err := writeAtomic(im.target, im.data); err != nil {
			return err
		}
	}
	if err := e.runner.Run(ctx, "fc-cache", "-f"); err != nil {
		return err
	}
	for _, im := range todo {
		fmt.Fprintf(e.stdout, "%s: %s: %s\n", filepath.Base(im.target), im.info.Family, im.v)
	}
	return nil
}

func check(ctx context.Context, e env, family string) error {
	files := faces(ctx, e, family)
	if len(files) == 0 {
		return fmt.Errorf("%s is not installed", family)
	}
	for _, f := range files {
		_, v, err := verdictOf(ctx, e, f)
		if err != nil {
			return err
		}
		fmt.Fprintf(e.stdout, "%s: %s\n", filepath.Base(f), v)
	}
	return nil
}

func patch(ctx context.Context, e env, family string) error {
	files := faces(ctx, e, family)
	if len(files) == 0 {
		return fmt.Errorf("%s is not installed", family)
	}
	fmt.Fprintf(e.stdout, "This writes a separate copy of %s with Nerd Font icons added; the original stays as it is.\n"+
		"Many commercial font licences forbid modified copies. Check the licence of %s before you go on.\n"+
		"Patch a copy? [y/N] ", family, family)
	answer, _ := bufio.NewReader(e.stdin).ReadString('\n')
	if a := strings.ToLower(strings.TrimSpace(answer)); a != "y" && a != "yes" {
		fmt.Fprintln(e.stdout, "Nothing changed.")
		return nil
	}
	if !e.runner.Has("fontforge") {
		if err := pacmanInstall(ctx, e, "fontforge"); err != nil {
			return err
		}
	}
	zipData, err := fetch(ctx, e, "FontPatcher.zip")
	if err != nil {
		return err
	}
	if got := sha256.Sum256(zipData); hex.EncodeToString(got[:]) != fontPatcherSHA256 {
		return errors.New("FontPatcher.zip does not match its pinned checksum; nothing patched")
	}
	tmp, err := os.MkdirTemp("", "subcult-font-patcher-")
	if err != nil {
		return err
	}
	defer os.RemoveAll(tmp)
	if err := unzip(zipData, tmp); err != nil {
		return err
	}
	out := filepath.Join(e.home, ".local", "share", "fonts", "subcult-patched")
	if err := os.MkdirAll(out, 0o755); err != nil {
		return err
	}
	before := modTimes(out)
	for _, f := range files {
		if err := e.runner.Run(ctx, "fontforge", "-script", filepath.Join(tmp, "font-patcher"),
			"--complete", "--outputdir", out, f); err != nil {
			return err
		}
	}
	if err := e.runner.Run(ctx, "fc-cache", "-f"); err != nil {
		return err
	}
	families := patchedFamilies(ctx, e, out, before)
	if len(families) == 0 {
		fmt.Fprintf(e.stdout, "Patched copies are in %s.\n", out)
		return nil
	}
	fmt.Fprintf(e.stdout, "Patched copies are in %s: %s; use subcult font set %q.\n", out, strings.Join(families, ", "), families[0])
	return nil
}

// modTimes lists the files in dir with their modification times.
func modTimes(dir string) map[string]time.Time {
	times := map[string]time.Time{}
	entries, _ := os.ReadDir(dir)
	for _, en := range entries {
		if info, err := en.Info(); err == nil && info.Mode().IsRegular() {
			times[en.Name()] = info.ModTime()
		}
	}
	return times
}

// patchedFamilies names the distinct families of the files in dir that are
// new or rewritten since before, as fontconfig reads them. The curated
// list does not show patched copies, so the patch reports them itself.
func patchedFamilies(ctx context.Context, e env, dir string, before map[string]time.Time) []string {
	var families []string
	seen := map[string]bool{}
	for name, t := range modTimes(dir) {
		if old, ok := before[name]; ok && old.Equal(t) {
			continue
		}
		info, _, err := verdictOf(ctx, e, filepath.Join(dir, name))
		if err != nil || seen[info.Family] {
			continue
		}
		seen[info.Family] = true
		families = append(families, info.Family)
	}
	slices.Sort(families)
	return families
}

func unzip(data []byte, dest string) error {
	zr, err := zip.NewReader(bytes.NewReader(data), int64(len(data)))
	if err != nil {
		return err
	}
	for _, f := range zr.File {
		target := filepath.Join(dest, f.Name)
		if !strings.HasPrefix(target, filepath.Clean(dest)+string(os.PathSeparator)) {
			return fmt.Errorf("FontPatcher.zip: unsafe path %s", f.Name)
		}
		if f.FileInfo().IsDir() {
			if err := os.MkdirAll(target, 0o755); err != nil {
				return err
			}
			continue
		}
		if err := os.MkdirAll(filepath.Dir(target), 0o755); err != nil {
			return err
		}
		rc, err := f.Open()
		if err != nil {
			return err
		}
		body, err := io.ReadAll(io.LimitReader(rc, 64<<20))
		rc.Close()
		if err != nil {
			return err
		}
		if err := os.WriteFile(target, body, f.Mode().Perm()|0o600); err != nil {
			return err
		}
	}
	return nil
}

func writeAtomic(path string, data []byte) error {
	return atomicfile.Write(path, data, 0o644)
}
