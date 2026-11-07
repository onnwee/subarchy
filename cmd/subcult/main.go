// Command subcult is Subarchy's command dispatcher. It routes
// "subcult <group> <action> [args]" to the subcult-<group>-<action>
// executable on PATH and lists commands with their metadata.
package main

import (
	"os"
	"path/filepath"
	"syscall"

	"git.subcult.tv/subculture-collective/subarchy/internal/dispatch"
)

func main() {
	reg, err := dispatch.Discover(filepath.SplitList(os.Getenv("PATH")))
	if err != nil {
		os.Stderr.WriteString("subcult: " + err.Error() + "\n")
		os.Exit(1)
	}
	app := &dispatch.App{
		Registry: reg,
		Stdout:   os.Stdout,
		Stderr:   os.Stderr,
		Exec: func(path string, argv []string) error {
			return syscall.Exec(path, argv, os.Environ())
		},
	}
	os.Exit(app.Run(os.Args[1:]))
}
