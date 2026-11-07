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

	work, err := os.MkdirTemp("", "subcult-cursor-")
	if err != nil {
		return err
	}
	defer os.RemoveAll(work)

	if err := os.MkdirAll(filepath.Dir(o.Out), 0o755); err != nil {
		return err
	}
	staging := o.Out + ".new"
	if err := os.RemoveAll(staging); err != nil {
		return err
	}
	for _, d := range []string{filepath.Join(staging, "cursors"), filepath.Join(work, "hc", "hyprcursors")} {
		if err := os.MkdirAll(d, 0o755); err != nil {
			return err
		}
	}
	defer os.RemoveAll(staging)

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
	return swap(staging, o.Out)
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
		fmt.Fprintf(&cfg, "%d %d %d %s\n", size, s.HotX*size/32, s.HotY*size/32, png)
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

// swap replaces dst with src: the old theme moves aside, the new one takes
// its name, then the old one is removed.
func swap(src, dst string) error {
	old := dst + ".old"
	if err := os.RemoveAll(old); err != nil {
		return err
	}
	if _, err := os.Lstat(dst); err == nil {
		if err := os.Rename(dst, old); err != nil {
			return err
		}
	}
	if err := os.Rename(src, dst); err != nil {
		return err
	}
	return os.RemoveAll(old)
}
