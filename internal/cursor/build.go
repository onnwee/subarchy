package cursor

import (
	"context"
	"fmt"
	"os"
	"path/filepath"
	"strings"

	"git.subcult.tv/subculture-collective/subarchy/internal/update"
)

// BuildOptions says where the shapes are, where the theme goes and which
// colours to use.
type BuildOptions struct {
	Src, Out   string // shape folder (SVGs and shapes.tsv); theme folder
	Fill, Line string // #RRGGBB
}

// Build renders every shape with rsvg-convert, writes Xcursor files with
// xcursorgen (aliases as symlinks), compiles a hyprcursor theme with
// hyprcursor-util, and swaps the result into o.Out in one rename, so a
// failed build leaves the previous theme in place.
func Build(ctx context.Context, r update.Runner, o BuildOptions) error {
	f, err := os.Open(filepath.Join(o.Src, "shapes.tsv"))
	if err != nil {
		return err
	}
	shapes, err := ParseShapes(f)
	f.Close()
	if err != nil {
		return err
	}

	// Scratch space sits next to the destination so every rename below stays
	// on one filesystem (TMPDIR is often a tmpfs), and each build has its own.
	if err := os.MkdirAll(filepath.Dir(o.Out), 0o755); err != nil {
		return err
	}
	work, err := os.MkdirTemp(filepath.Dir(o.Out), "."+ThemeName+"-")
	if err != nil {
		return err
	}
	defer os.RemoveAll(work)
	staging := filepath.Join(work, "theme")
	for _, d := range []string{filepath.Join(staging, "cursors"), filepath.Join(work, "hc", "hyprcursors")} {
		if err := os.MkdirAll(d, 0o755); err != nil {
			return err
		}
	}

	for _, s := range shapes {
		if err := buildShape(ctx, r, o, s, work, staging); err != nil {
			return fmt.Errorf("%s: %w", s.Name, err)
		}
	}

	manifest := fmt.Sprintf("name = %s\ndescription = Subarchy cursor\nversion = 1\ncursors_directory = hyprcursors\n", ThemeName)
	if err := os.WriteFile(filepath.Join(work, "hc", "manifest.hl"), []byte(manifest), 0o644); err != nil {
		return err
	}
	if err := r.Run(ctx, "hyprcursor-util", "--create", filepath.Join(work, "hc")); err != nil {
		return err
	}
	compiled := filepath.Join(work, "theme_"+ThemeName)
	if err := os.Rename(filepath.Join(compiled, "hyprcursors"), filepath.Join(staging, "hyprcursors")); err != nil {
		return err
	}
	if err := os.Rename(filepath.Join(compiled, "manifest.hl"), filepath.Join(staging, "manifest.hl")); err != nil {
		return err
	}
	index := fmt.Sprintf("[Icon Theme]\nName=%s\nComment=Subarchy cursor, fill %s\n", ThemeName, o.Fill)
	if err := os.WriteFile(filepath.Join(staging, "index.theme"), []byte(index), 0o644); err != nil {
		return err
	}
	return swap(staging, o.Out, filepath.Join(work, "old"))
}

func buildShape(ctx context.Context, r update.Runner, o BuildOptions, s Shape, work, staging string) error {
	raw, err := os.ReadFile(filepath.Join(o.Src, s.Name+".svg"))
	if err != nil {
		return err
	}
	svg := []byte(Colourise(string(raw), o.Fill, o.Line))
	svgPath := filepath.Join(work, s.Name+".svg")
	if err := os.WriteFile(svgPath, svg, 0o644); err != nil {
		return err
	}

	var cfg strings.Builder
	for _, size := range Sizes {
		png := filepath.Join(work, fmt.Sprintf("%s-%d.png", s.Name, size))
		if err := r.Run(ctx, "rsvg-convert", "-w", fmt.Sprint(size), "-h", fmt.Sprint(size), "-o", png, svgPath); err != nil {
			return err
		}
		// Rounded to the nearest pixel: truncating put 13/32 at 24 px on 9, not 10.
		fmt.Fprintf(&cfg, "%d %d %d %s\n", size, (s.HotX*size+16)/32, (s.HotY*size+16)/32, png)
	}
	cfgPath := filepath.Join(work, s.Name+".cfg")
	if err := os.WriteFile(cfgPath, []byte(cfg.String()), 0o644); err != nil {
		return err
	}
	if err := r.Run(ctx, "xcursorgen", cfgPath, filepath.Join(staging, "cursors", s.Name)); err != nil {
		return err
	}
	for _, alias := range s.Aliases {
		if err := os.Symlink(s.Name, filepath.Join(staging, "cursors", alias)); err != nil {
			return err
		}
	}

	dir := filepath.Join(work, "hc", "hyprcursors", s.Name)
	if err := os.MkdirAll(dir, 0o755); err != nil {
		return err
	}
	if err := os.WriteFile(filepath.Join(dir, s.Name+".svg"), svg, 0o644); err != nil {
		return err
	}
	meta := fmt.Sprintf("resize_algorithm = bilinear\nhotspot_x = %.4f\nhotspot_y = %.4f\nnominal_size = 1.0\ndefine_size = 0, %s.svg\n",
		float64(s.HotX)/32, float64(s.HotY)/32, s.Name)
	if len(s.Aliases) > 0 {
		meta += "define_override = " + strings.Join(s.Aliases, ";") + "\n"
	}
	return os.WriteFile(filepath.Join(dir, "meta.hl"), []byte(meta), 0o644)
}

// swap replaces dst with src: the old theme moves aside to old (inside the
// build's scratch folder, removed with it), the new one takes its name. If
// the new one cannot move in, the old theme goes back.
func swap(src, dst, old string) error {
	moved := false
	if _, err := os.Lstat(dst); err == nil {
		if err := os.Rename(dst, old); err != nil {
			return err
		}
		moved = true
	}
	err := os.Rename(src, dst)
	if err != nil && moved {
		if back := os.Rename(old, dst); back != nil {
			return fmt.Errorf("%w; the previous theme is still at %s: %v", err, old, back)
		}
	}
	return err
}
