// Command subcult-cursor serves `subcult cursor ...`: Subarchy's own cursor,
// coloured from a palette role (shell and look design, "Cursor").
//
//	subcult cursor apply                   rebuild from cursor.json and apply
//	subcult cursor set [--role R] [--size N]  change the choice, then apply
//	subcult cursor build --role R --out DIR   build only (packaging, tests)
package main

import (
	"context"
	"encoding/json"
	"errors"
	"flag"
	"fmt"
	"io"
	"os"
	"path/filepath"

	"git.subcult.tv/subculture-collective/subarchy/internal/cursor"
	"git.subcult.tv/subculture-collective/subarchy/internal/dispatch"
	"git.subcult.tv/subculture-collective/subarchy/internal/update"
)

var routes = []dispatch.Described{
	{Words: []string{"cursor", "apply"}, Metadata: dispatch.Metadata{
		Summary:  "Rebuild the cursor in the chosen theme colour and apply it",
		Examples: []string{"subcult cursor apply"}}},
	{Words: []string{"cursor", "set"}, Metadata: dispatch.Metadata{
		Summary: "Choose the cursor colour (a palette role) and size", Args: "[--role <role>] [--size 24|32|48]",
		Examples: []string{"subcult cursor set --role green", "subcult cursor set --size 32"}}},
	{Words: []string{"cursor", "build"}, Metadata: dispatch.Metadata{
		Summary: "Build the cursor theme into a folder", Args: "--role <role> --out <dir>", Hidden: true}},
}

type env struct {
	home, system string
	runner       update.Runner
	stdout       io.Writer
	stderr       io.Writer
}

func main() {
	home, _ := os.UserHomeDir()
	system := os.Getenv("SUBCULT_PATH")
	if system == "" {
		system = "/usr/share/subcult"
	}
	e := env{home: home, system: system, stdout: os.Stdout, stderr: os.Stderr,
		runner: update.ExecRunner{Stdout: io.Discard, Stderr: os.Stderr}}
	os.Exit(run(context.Background(), os.Args[1:], e))
}

func run(ctx context.Context, args []string, e env) int {
	if len(args) == 1 && args[0] == dispatch.MetadataFlag {
		if err := json.NewEncoder(e.stdout).Encode(routes); err != nil {
			return 1
		}
		return 0
	}
	if len(args) == 0 {
		fmt.Fprintln(e.stderr, "Usage: subcult cursor apply | set [--role <role>] [--size 24|32|48] | build --role <role> --out <dir>")
		return 2
	}
	fs := flag.NewFlagSet("subcult cursor "+args[0], flag.ContinueOnError)
	fs.SetOutput(e.stderr)
	role := fs.String("role", "", "palette role for the fill")
	size := fs.Int("size", 0, "cursor size in pixels")
	palettePath := fs.String("palette", "", "palette.json to use alone (default: the system palette with the user's roles on top)")
	src := fs.String("src", filepath.Join(e.system, "default", "cursor"), "folder with the shapes")
	out := fs.String("out", "", "theme folder (build only)")
	if err := fs.Parse(args[1:]); err != nil {
		return 2
	}
	var palette cursor.Palette
	var err error
	if *palettePath != "" {
		palette, err = cursor.LoadPalette(*palettePath)
	} else {
		// The system palette underneath, the user's valid roles on top, so a
		// broken theme file never stops the cursor.
		var warnings []string
		palette, warnings, err = cursor.LoadLayered(
			filepath.Join(e.system, "default", "theme", "palette.json"),
			filepath.Join(e.home, ".config", "subcult", "theme", "palette.json"))
		for _, w := range warnings {
			fmt.Fprintf(e.stderr, "subcult cursor: warning: %s\n", w)
		}
	}
	if err != nil {
		fmt.Fprintf(e.stderr, "subcult cursor: %v\n", err)
		return 1
	}
	settingsPath := filepath.Join(e.home, ".config", "subcult", "cursor.json")

	switch args[0] {
	case "build":
		if *role == "" || *out == "" {
			fmt.Fprintln(e.stderr, "subcult cursor build: --role and --out are required")
			return 2
		}
		return report(e, build(ctx, e, palette, *src, *out, cursor.Settings{Role: *role, Size: cursor.Default.Size}))
	case "apply":
		return report(e, apply(ctx, e, palette, *src, cursor.LoadSettings(settingsPath)))
	case "set":
		s := cursor.LoadSettings(settingsPath)
		if *role != "" {
			s.Role = *role
		}
		if *size != 0 {
			s.Size = *size
		}
		if err := cursor.Validate(s, palette); err != nil {
			return report(e, err)
		}
		if err := cursor.SaveSettings(settingsPath, s); err != nil {
			return report(e, err)
		}
		return report(e, apply(ctx, e, palette, *src, s))
	}
	fmt.Fprintf(e.stderr, "subcult cursor: unknown command %q\n", args[0])
	return 2
}

func build(ctx context.Context, e env, p cursor.Palette, src, out string, s cursor.Settings) error {
	if err := cursor.Validate(s, p); err != nil {
		return err
	}
	fill := p[s.Role]
	line, err := cursor.Outline(fill, colourOr(p, "crust", "#06040A"), colourOr(p, "text", "#F0ECE4"))
	if err != nil {
		return err
	}
	return cursor.Build(ctx, e.runner, cursor.BuildOptions{Src: src, Out: out, Fill: fill, Line: line})
}

func apply(ctx context.Context, e env, p cursor.Palette, src string, s cursor.Settings) error {
	if err := cursor.Validate(s, p); err != nil {
		// A theme without the chosen role falls back to the default role.
		s.Role = cursor.Default.Role
		if err := cursor.Validate(s, p); err != nil {
			return err
		}
	}
	out := filepath.Join(e.home, ".local", "share", "icons", cursor.ThemeName)
	if err := build(ctx, e, p, src, out, s); err != nil {
		return err
	}
	if os.Getenv("HYPRLAND_INSTANCE_SIGNATURE") != "" && e.runner.Has("hyprctl") {
		if err := e.runner.Run(ctx, "hyprctl", "setcursor", cursor.ThemeName, fmt.Sprint(s.Size)); err != nil {
			return err
		}
	}
	if e.runner.Has("gsettings") {
		for _, kv := range [][2]string{{"cursor-theme", cursor.ThemeName}, {"cursor-size", fmt.Sprint(s.Size)}} {
			if err := e.runner.Run(ctx, "gsettings", "set", "org.gnome.desktop.interface", kv[0], kv[1]); err != nil {
				return err
			}
		}
	}
	fmt.Fprintf(e.stdout, "Cursor: %s (%s) at %d px\n", s.Role, p[s.Role], s.Size)
	return nil
}

func colourOr(p cursor.Palette, role, fallback string) string {
	if v, ok := p[role]; ok {
		return v
	}
	return fallback
}

func report(e env, err error) int {
	if err == nil {
		return 0
	}
	fmt.Fprintf(e.stderr, "subcult cursor: %v\n", err)
	if errors.Is(err, cursor.ErrInvalid) {
		return 2
	}
	return 1
}
